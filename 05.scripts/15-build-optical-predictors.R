# GENERATED FILE. Do not edit.
# Written from 01.manuscript/manuscript.qmd by the pipe-purl chunk.
# Edit the chunk in the manuscript and regenerate; edits here are lost.
# Run from the repository root.

suppressMessages({ library(sf); library(terra) })
root <- normalizePath('.')
inputs <- file.path(root, '02.inputs')
outputs <- file.path(root, '03.outputs')
derived <- file.path(inputs, 'derived')
BC_ALBERS <- 3005

opt_path <- file.path(derived, "predictors-optical.csv")
opt_log <- file.path(derived, "predictors-optical-log.csv")

EE_PROJECT <- "murphys-deforisk"
S2_START <- "2019-06-01"
S2_END <- "2021-09-30"
BUFFER_M <- 20            # inward erosion of the survey polygon, provisional
SUMM_SCALE <- 20          # metres, scale of the polygon summary

if (!file.exists(opt_path)) local({
  library(rgee)
  MAX_CLOUD  <- 40        # scene cloud cover, percent
  FIT_PAD_M  <- 5000      # outward pad of the region the c parameter is fitted on
  FIT_SCALE  <- 100       # metres, scale of the c parameter fit
  FIT_MIN_PX <- 500       # minimum valid pixels in the fit region to keep a scene

  BANDS <- c("B2", "B3", "B4", "B5", "B6", "B7", "B8", "B8A", "B11", "B12")
  # Scene classification classes retained: 4 vegetation, 5 not vegetated,
  # 7 unclassified. Masked: 0 no data, 1 saturated, 2 dark, 3 cloud shadow,
  # 6 water, 8 and 9 cloud, 10 cirrus, 11 snow.
  SCL_KEEP <- c(4L, 5L, 7L)

  a <- sf::st_read(file.path(derived, "analysis-set.geojson"), quiet = TRUE)
  n_all <- nrow(a)
  # poly_id is positional in the frozen file, and every predictor block derives
  # it the same way, so the three tables join on a common key.
  poly_id <- sprintf("P%03d", seq_len(n_all))
  # Everything except geometry is dropped here. No label reaches Earth Engine.
  geom <- sf::st_transform(sf::st_geometry(a), BC_ALBERS)
  rm(a)

  # Sketch-mapped boundaries are approximate, so the polygon is eroded before it
  # is summarised. Polygons too small to survive erosion are dropped and counted.
  eroded <- sf::st_buffer(geom, -BUFFER_M)
  alive <- !sf::st_is_empty(eroded)
  n_dropped <- sum(!alive)
  eroded <- eroded[alive]; poly_id <- poly_id[alive]
  polys <- sf::st_sf(poly_id = poly_id,
                     geometry = sf::st_transform(eroded, 4326))
  stopifnot(identical(setdiff(names(polys), "geometry"), "poly_id"))

  ee_Initialize(project = EE_PROJECT, quiet = TRUE)
  fc <- sf_as_ee(polys)
  # The c parameter is fitted over the sample padded outward, rather than over
  # the whole scene, so the regression describes the terrain the correction is
  # applied to and the computation stays bounded.
  fit_region <- sf_as_ee(sf::st_transform(
    sf::st_union(sf::st_buffer(sf::st_union(geom), FIT_PAD_M)), 4326))

  dem <- ee$ImageCollection("COPERNICUS/DEM/GLO30")$select("DEM")$mosaic()$
    setDefaultProjection("EPSG:3857", NULL, 30)
  terrain <- ee$Terrain$products(dem)
  slope_rad <- terrain$select("slope")$multiply(pi / 180)
  aspect_rad <- terrain$select("aspect")$multiply(pi / 180)

  mask_scl <- function(img) {
    scl <- img$select("SCL")
    keep <- scl$eq(SCL_KEEP[1])
    for (k in SCL_KEEP[-1]) keep <- keep$Or(scl$eq(k))
    img$updateMask(keep)
  }

  # Illumination condition, the cosine of the solar incidence angle on the local
  # surface. A non-positive value faces away from the sun and is masked.
  illumination <- function(img) {
    sz <- ee$Number(img$get("MEAN_SOLAR_ZENITH_ANGLE"))$multiply(pi / 180)
    sa <- ee$Number(img$get("MEAN_SOLAR_AZIMUTH_ANGLE"))$multiply(pi / 180)
    il <- ee$Image$constant(sz$cos())$multiply(slope_rad$cos())$add(
      ee$Image$constant(sz$sin())$multiply(slope_rad$sin())$
        multiply(aspect_rad$subtract(sa)$cos()))
    il$rename("IL")
  }

  prepare <- function(img) {
    refl <- mask_scl(img)$select(BANDS)$divide(10000)
    il <- illumination(img)
    refl$updateMask(il$gt(0))$addBands(il)$
      copyProperties(img, list("system:time_start",
                               "MEAN_SOLAR_ZENITH_ANGLE",
                               "MEAN_SOLAR_AZIMUTH_ANGLE"))
  }

  # SCS+C. rho_corrected = rho * (cos(slope) cos(zenith) + c) / (IL + c), with c
  # the ratio of intercept to slope from the per-band regression of reflectance
  # on IL. A non-positive fitted slope is physically wrong, so c is forced large
  # and the correction collapses to the identity for that band.
  correct_scsc <- function(img) {
    sz <- ee$Number(img$get("MEAN_SOLAR_ZENITH_ANGLE"))$multiply(pi / 180)
    il <- img$select("IL")
    design <- ee$Image$constant(1)$rename("constant")$addBands(il)$
      addBands(img$select(BANDS))$updateMask(il$mask())
    fit <- design$reduceRegion(
      reducer = ee$Reducer$linearRegression(numX = 2L, numY = length(BANDS)),
      geometry = fit_region, scale = FIT_SCALE, maxPixels = 1e9, tileScale = 4L)
    coefs <- ee$Array(fit$get("coefficients"))
    intercept <- ee$Image$constant(
      coefs$slice(0L, 0L, 1L)$project(list(1L))$toList())$rename(BANDS)
    slope <- ee$Image$constant(
      coefs$slice(0L, 1L, 2L)$project(list(1L))$toList())$rename(BANDS)
    cimg <- intercept$divide(slope)
    cimg <- cimg$where(slope$lte(0), 1e6)
    cimg <- cimg$where(cimg$lte(0), 1e6)
    numer <- ee$Image$constant(sz$cos())$multiply(slope_rad$cos())$add(cimg)
    img$select(BANDS)$multiply(numer$divide(il$add(cimg)))$
      copyProperties(img, list("system:time_start"))
  }

  # Scenes with too few valid pixels cannot support the regression and are
  # dropped rather than corrected from a degenerate fit.
  count_fit_px <- function(img) {
    img$set("n_fit", img$select("B8")$reduceRegion(
      reducer = ee$Reducer$count(), geometry = fit_region, scale = FIT_SCALE,
      maxPixels = 1e9, tileScale = 4L)$get("B8"))
  }

  raw <- ee$ImageCollection("COPERNICUS/S2_SR_HARMONIZED")$
    filterBounds(fit_region)$filterDate(S2_START, S2_END)$
    filter(ee$Filter$lt("CLOUDY_PIXEL_PERCENTAGE", MAX_CLOUD))
  n_raw <- raw$size()$getInfo()

  prepared <- raw$map(ee_utils_pyfunc(prepare))$
    map(ee_utils_pyfunc(count_fit_px))$
    filter(ee$Filter$gt("n_fit", FIT_MIN_PX))
  n_fit <- prepared$size()$getInfo()

  composite <- prepared$map(ee_utils_pyfunc(correct_scsc))$median()

  # Indices selected for sensitivity to canopy water content and to visible and
  # shortwave change. Provisional; the set is fixed at pre-registration.
  nd <- function(x, y, nm) composite$normalizedDifference(c(x, y))$rename(nm)
  indices <- nd("B8", "B4", "NDVI")$
    addBands(nd("B8", "B11", "NDMI"))$
    addBands(nd("B8", "B12", "NBR"))$
    addBands(nd("B8", "B5", "NDRE1"))$
    addBands(nd("B8", "B3", "GNDVI"))$
    addBands(composite$select("B11")$divide(composite$select("B8"))$rename("MSI"))$
    addBands(composite$select("B11")$divide(composite$select("B12"))$rename("SWIRR"))$
    addBands(composite$expression(
      "2.5 * (nir - red) / (nir + 6 * red - 7.5 * blue + 1)",
      list(nir = composite$select("B8"), red = composite$select("B4"),
           blue = composite$select("B2")))$rename("EVI"))

  stack <- composite$addBands(indices)
  VARS <- c(BANDS, "NDVI", "NDMI", "NBR", "NDRE1", "GNDVI", "MSI", "SWIRR", "EVI")

  reducer <- ee$Reducer$mean()$
    combine(reducer2 = ee$Reducer$stdDev(), sharedInputs = TRUE)$
    combine(reducer2 = ee$Reducer$count(), sharedInputs = TRUE)
  summaries <- stack$reduceRegions(collection = fc, reducer = reducer,
                                   scale = SUMM_SCALE, tileScale = 4L)

  # Drive credentials are not set on this machine, so the export goes to an
  # Earth Engine asset and is read back. Polling is to completion rather than
  # for a fixed number of attempts: reading the asset before the task has
  # written it fails with a misleading "not found".
  asset_id <- sprintf("projects/%s/assets/adelgid-optical-%s", EE_PROJECT,
                      format(Sys.Date(), "%Y%m%d"))
  try(ee_manage_delete(asset_id), silent = TRUE)
  task <- ee_table_to_asset(collection = summaries,
                            description = "adelgid_optical", assetId = asset_id)
  task$start()
  repeat {
    st <- task$status()
    if (st$state %in% c("COMPLETED", "FAILED", "CANCELLED", "CANCEL_REQUESTED"))
      break
    Sys.sleep(30)
  }
  if (st$state != "COMPLETED") stop("Earth Engine export ", st$state)

  got <- ee$FeatureCollection(asset_id)$getInfo()
  rows <- lapply(got$features, function(f)
    as.data.frame(f$properties, stringsAsFactors = FALSE))
  tab <- do.call(rbind, lapply(rows, function(r) {
    wanted <- c("poly_id", unlist(lapply(VARS, function(v)
      paste0(v, c("_mean", "_stdDev", "_count")))))
    for (m in setdiff(wanted, names(r))) r[[m]] <- NA_real_
    r[, wanted, drop = FALSE]
  }))
  tab <- tab[order(tab$poly_id), ]

  # The guard that matters: no label may leave this block.
  stopifnot(length(grep("PEST|SPECIES|SEVERITY|AGENT|CAPTURE|lidar|offset|AREA",
                        names(tab), ignore.case = TRUE)) == 0)
  write.csv(tab, opt_path, row.names = FALSE)
  write.csv(data.frame(
    parameter = c("collection", "start", "end", "max_scene_cloud_pct",
                  "scl_kept", "scenes_matched", "scenes_corrected",
                  "topographic_correction", "dem", "c_fit_scale_m",
                  "c_fit_pad_m", "c_fit_min_pixels", "inward_buffer_m",
                  "summary_scale_m", "polygons_in", "polygons_dropped_by_buffer",
                  "polygons_out", "built"),
    value = c("COPERNICUS/S2_SR_HARMONIZED", S2_START, S2_END, MAX_CLOUD,
              paste(SCL_KEEP, collapse = " "), n_raw, n_fit, "SCS+C",
              "COPERNICUS/DEM/GLO30", FIT_SCALE, FIT_PAD_M, FIT_MIN_PX,
              BUFFER_M, SUMM_SCALE, n_all, n_dropped, nrow(tab),
              as.character(Sys.Date())), stringsAsFactors = FALSE),
    opt_log, row.names = FALSE)
})


