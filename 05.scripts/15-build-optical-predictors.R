# Build the optical predictor table: Sentinel-2 composite, indices and polygon
# summaries, in Google Earth Engine.
#
# Step 15 of the pipeline in
# docs/science-superpowers/plans/2026-08-14-adelgid-attribution-plan.md.
#
# LANGUAGE DEVIATION FROM THE PLAN. The plan names this step
# `15-build-optical-predictors.js`, an Earth Engine Code Editor script. It is
# written in R against rgee instead, because a `.js` file cannot be executed
# from this machine: it would have to be pasted into a browser, its output would
# land in Drive rather than in the repository, and the standing convention that
# a number must be recomputable from saved code would be broken. The Earth
# Engine logic is identical; only the client differs. Raised for Seamus to
# overrule on 2026-08-14.
#
# WHAT THIS SCRIPT MAY NOT DO. It never reads a label. The analysis set is
# stripped to geometry and a positional identifier before anything is sent to
# Earth Engine, and the output is asserted to carry no agent, severity or host
# column. Pre-registration precedes any join of a predictor to a label.
#
# METHOD, following the data preparation section of the manuscript.
#   1. Scenes are Sentinel-2 Level 2A surface reflectance over the leaf-on
#      window of the label epoch, 1 June 2019 to 30 September 2021, with less
#      than forty percent scene cloud cover.
#   2. Cloud, cloud shadow, snow, water, saturated and dark pixels are masked
#      from the scene classification layer before compositing.
#   3. Each scene is corrected for topographic illumination by SCS+C (Soenen,
#      Peddle and Coburn 2005), which preserves the geotropic growth assumption
#      appropriate to forest canopies. The empirical c parameter is fitted per
#      scene and per band by linear regression of reflectance on the
#      illumination condition, over the sample polygons buffered outward, so
#      that the correction is calibrated on the terrain it is applied to.
#   4. A per-pixel median composite is formed from the corrected scenes.
#   5. Bands and indices are summarised to the inward-buffered survey polygon as
#      a mean and a standard deviation, so a heterogeneous polygon is not
#      represented solely by a central value.
#
# PARAMETERS THAT PRE-REGISTRATION FIXES. The inward buffer distance and the
# index set are provisional here and are fixed at pre-registration. A tasselled
# cap transform is a candidate addition and is deliberately absent: the
# Sentinel-2 coefficients have not been read from their source publication, and
# unverified coefficients are not written into code.
#
# Usage:
#   Rscript 05.scripts/15-build-optical-predictors.R [--limit N] [--getinfo]
#
#   --limit N        restrict to the first N polygons, for a smoke test
#   --getinfo        fetch results in the foreground instead of exporting to an
#                    Earth Engine asset; only sane for a small --limit
#   --read-asset ID  read a completed or running export instead of starting a
#                    new one, so an interrupted poll costs nothing

suppressMessages({
  library(sf)
  library(rgee)
})

args <- commandArgs(trailingOnly = TRUE)
opt_val <- function(flag, default = NA) {
  k <- match(flag, args)
  if (is.na(k) || k == length(args)) default else args[k + 1L]
}
LIMIT <- suppressWarnings(as.integer(opt_val("--limit")))
USE_GETINFO <- "--getinfo" %in% args
READ_ASSET <- opt_val("--read-asset")

root <- normalizePath(".")
stopifnot(dir.exists(file.path(root, "02.inputs")))
derived <- file.path(root, "02.inputs", "derived")

EE_PROJECT  <- "murphys-deforisk"
BC_ALBERS   <- 3005
START       <- "2019-06-01"
END         <- "2021-09-30"
MAX_CLOUD   <- 40         # scene cloud cover, percent
BUFFER_M    <- 20         # inward erosion of the survey polygon, provisional
FIT_PAD_M   <- 5000       # outward pad of the region the c parameter is fitted on
FIT_SCALE   <- 100        # metres, scale of the c parameter fit
FIT_MIN_PX  <- 500        # minimum valid pixels in the fit region to keep a scene
SUMM_SCALE  <- 20         # metres, scale of the polygon summary

BANDS <- c("B2", "B3", "B4", "B5", "B6", "B7", "B8", "B8A", "B11", "B12")
# Scene classification classes retained: 4 vegetation, 5 not vegetated,
# 7 unclassified. Masked: 0 no data, 1 saturated, 2 dark area, 3 cloud shadow,
# 6 water, 8 and 9 cloud medium and high probability, 10 cirrus, 11 snow.
SCL_KEEP <- c(4L, 5L, 7L)

# ---------------------------------------------------------------- the sample

aset <- st_read(file.path(derived, "analysis-set.geojson"), quiet = TRUE)
n_all <- nrow(aset)

# poly_id is positional in the frozen file. The file is the sample and is not
# rebuilt, so the position is stable; every downstream step derives the same
# identifier from the same file in the same way.
poly_id <- sprintf("P%03d", seq_len(n_all))

# Everything except geometry is dropped here. No label reaches Earth Engine and
# none can reach the output table.
geom <- st_transform(st_geometry(aset), BC_ALBERS)
rm(aset)

if (!is.na(LIMIT) && LIMIT < n_all) {
  keep <- seq_len(LIMIT)
  geom <- geom[keep]
  poly_id <- poly_id[keep]
  message("SMOKE TEST: restricted to ", LIMIT, " polygons")
}

# Sketch-mapped boundaries are approximate, so the polygon is eroded before it
# is summarised. Polygons too small to survive erosion are dropped and counted.
eroded <- st_buffer(geom, -BUFFER_M)
alive <- !st_is_empty(eroded)
n_dropped <- sum(!alive)
dropped_ids <- poly_id[!alive]
eroded <- eroded[alive]
poly_id <- poly_id[alive]

message(n_all, " polygons in the frozen sample")
message(n_dropped, " lost to the ", BUFFER_M, " m inward buffer",
        if (n_dropped) paste0(": ", paste(dropped_ids, collapse = ", ")) else "")
message(length(poly_id), " polygons carried forward")
stopifnot(length(poly_id) > 0)

polys <- st_sf(poly_id = poly_id, geometry = st_transform(eroded, 4326))
stopifnot(identical(setdiff(names(polys), "geometry"), "poly_id"))

# ------------------------------------------------------------- Earth Engine

ee_Initialize(project = EE_PROJECT, quiet = TRUE)

fc <- sf_as_ee(polys)

# The c parameter is fitted over the sample polygons padded outward, rather than
# over the whole scene, so that the regression describes the terrain and cover
# the correction is applied to and the computation stays bounded.
fit_region <- sf_as_ee(
  st_transform(st_union(st_buffer(st_union(geom), FIT_PAD_M)), 4326))

dem <- ee$ImageCollection("COPERNICUS/DEM/GLO30")$
  select("DEM")$
  mosaic()$
  setDefaultProjection("EPSG:3857", NULL, 30)
terrain <- ee$Terrain$products(dem)
slope_rad  <- terrain$select("slope")$multiply(pi / 180)
aspect_rad <- terrain$select("aspect")$multiply(pi / 180)

mask_scl <- function(img) {
  scl <- img$select("SCL")
  keep <- scl$eq(SCL_KEEP[1])
  for (k in SCL_KEEP[-1]) keep <- keep$Or(scl$eq(k))
  img$updateMask(keep)
}

# Illumination condition, the cosine of the solar incidence angle on the local
# surface. Pixels with a non-positive value face away from the sun and are
# masked rather than corrected, since the correction is undefined there.
illumination <- function(img) {
  sz <- ee$Number(img$get("MEAN_SOLAR_ZENITH_ANGLE"))$multiply(pi / 180)
  sa <- ee$Number(img$get("MEAN_SOLAR_AZIMUTH_ANGLE"))$multiply(pi / 180)
  cos_z <- ee$Image$constant(sz$cos())
  sin_z <- ee$Image$constant(sz$sin())
  il <- cos_z$multiply(slope_rad$cos())$add(
    sin_z$multiply(slope_rad$sin())$multiply(aspect_rad$subtract(sa)$cos()))
  il$rename("IL")
}

prepare <- function(img) {
  refl <- mask_scl(img)$select(BANDS)$divide(10000)
  il <- illumination(img)
  refl$updateMask(il$gt(0))$
    addBands(il)$
    copyProperties(img, list("system:time_start",
                             "MEAN_SOLAR_ZENITH_ANGLE",
                             "MEAN_SOLAR_AZIMUTH_ANGLE"))
}

# SCS+C. rho_corrected = rho * (cos(slope) cos(zenith) + c) / (IL + c), with
# c the ratio of intercept to slope from the per-band regression of reflectance
# on IL. A non-positive fitted slope is physically wrong, so c is forced large
# and the correction collapses to the identity for that band.
correct_scsc <- function(img) {
  sz <- ee$Number(img$get("MEAN_SOLAR_ZENITH_ANGLE"))$multiply(pi / 180)
  il <- img$select("IL")

  design <- ee$Image$constant(1)$rename("constant")$
    addBands(il)$
    addBands(img$select(BANDS))$
    updateMask(il$mask())

  fit <- design$reduceRegion(
    reducer = ee$Reducer$linearRegression(numX = 2L, numY = length(BANDS)),
    geometry = fit_region,
    scale = FIT_SCALE,
    maxPixels = 1e9,
    tileScale = 4L)

  coefs <- ee$Array(fit$get("coefficients"))
  intercept <- ee$Image$constant(
    coefs$slice(0L, 0L, 1L)$project(list(1L))$toList())$rename(BANDS)
  slope <- ee$Image$constant(
    coefs$slice(0L, 1L, 2L)$project(list(1L))$toList())$rename(BANDS)

  cimg <- intercept$divide(slope)
  cimg <- cimg$where(slope$lte(0), 1e6)
  cimg <- cimg$where(cimg$lte(0), 1e6)

  numer <- ee$Image$constant(sz$cos())$multiply(slope_rad$cos())$add(cimg)
  denom <- il$add(cimg)

  img$select(BANDS)$multiply(numer$divide(denom))$
    copyProperties(img, list("system:time_start"))
}

# Scenes with too few valid pixels in the fit region cannot support the
# regression and are dropped rather than corrected from a degenerate fit.
count_fit_px <- function(img) {
  n <- img$select("B8")$reduceRegion(
    reducer = ee$Reducer$count(),
    geometry = fit_region,
    scale = FIT_SCALE,
    maxPixels = 1e9,
    tileScale = 4L)$get("B8")
  img$set("n_fit", n)
}

raw <- ee$ImageCollection("COPERNICUS/S2_SR_HARMONIZED")$
  filterBounds(fit_region)$
  filterDate(START, END)$
  filter(ee$Filter$lt("CLOUDY_PIXEL_PERCENTAGE", MAX_CLOUD))

n_raw <- raw$size()$getInfo()
message(n_raw, " Sentinel-2 scenes match the window and cloud filter")
stopifnot(n_raw > 0)

prepared <- raw$map(ee_utils_pyfunc(prepare))$
  map(ee_utils_pyfunc(count_fit_px))$
  filter(ee$Filter$gt("n_fit", FIT_MIN_PX))

n_fit <- prepared$size()$getInfo()
message(n_fit, " scenes carry at least ", FIT_MIN_PX,
        " valid pixels over the sample and are corrected")
stopifnot(n_fit > 0)

composite <- prepared$map(ee_utils_pyfunc(correct_scsc))$median()

# ------------------------------------------------------------------ indices
# Selected for sensitivity to canopy water content and to visible and shortwave
# change. Provisional; the set is fixed at pre-registration.

nd <- function(a, b, name) composite$normalizedDifference(c(a, b))$rename(name)

indices <- nd("B8", "B4",  "NDVI")$
  addBands(nd("B8",  "B11", "NDMI"))$
  addBands(nd("B8",  "B12", "NBR"))$
  addBands(nd("B8",  "B5",  "NDRE1"))$
  addBands(nd("B8",  "B3",  "GNDVI"))$
  addBands(composite$select("B11")$divide(composite$select("B8"))$rename("MSI"))$
  addBands(composite$select("B11")$divide(composite$select("B12"))$rename("SWIRR"))$
  addBands(composite$expression(
    "2.5 * (nir - red) / (nir + 6 * red - 7.5 * blue + 1)",
    list(nir = composite$select("B8"),
         red = composite$select("B4"),
         blue = composite$select("B2")))$rename("EVI"))

stack <- composite$addBands(indices)
VARS <- c(BANDS, "NDVI", "NDMI", "NBR", "NDRE1", "GNDVI", "MSI", "SWIRR", "EVI")

# ------------------------------------------------------- polygon summaries

reducer <- ee$Reducer$mean()$
  combine(reducer2 = ee$Reducer$stdDev(), sharedInputs = TRUE)$
  combine(reducer2 = ee$Reducer$count(), sharedInputs = TRUE)

summaries <- stack$reduceRegions(
  collection = fc,
  reducer = reducer,
  scale = SUMM_SCALE,
  tileScale = 4L)

stamp <- format(Sys.Date(), "%Y%m%d")
out_csv <- file.path(derived, "predictors-optical.csv")
log_csv <- file.path(derived, "predictors-optical-log.csv")

if (USE_GETINFO) {
  message("fetching in the foreground")
  got <- summaries$getInfo()
  rows <- lapply(got$features, function(f) as.data.frame(f$properties,
                                                         stringsAsFactors = FALSE))
} else if (!is.na(READ_ASSET)) {
  # Resume. The export is already running or finished; wait for the asset to
  # become readable rather than starting the computation again.
  message("reading ", READ_ASSET)
  got <- NULL
  for (attempt in seq_len(240)) {
    got <- tryCatch(ee$FeatureCollection(READ_ASSET)$getInfo(),
                    error = function(e) NULL)
    if (!is.null(got)) break
    message("asset not readable yet, attempt ", attempt)
    Sys.sleep(30)
  }
  if (is.null(got)) stop("asset ", READ_ASSET, " never became readable")
  rows <- lapply(got$features, function(f) as.data.frame(f$properties,
                                                         stringsAsFactors = FALSE))
} else {
  asset_id <- sprintf("projects/%s/assets/adelgid-optical-%s", EE_PROJECT, stamp)
  message("exporting to ", asset_id)
  try(ee_manage_delete(asset_id), silent = TRUE)
  task <- ee_table_to_asset(collection = summaries,
                           description = paste0("adelgid_optical_", stamp),
                           assetId = asset_id)
  task$start()

  # Poll to completion rather than for a fixed number of attempts. The export
  # over the full sample runs for several minutes, and reading the asset before
  # the task has written it fails with a misleading "not found".
  repeat {
    st <- task$status()
    if (st$state %in% c("COMPLETED", "FAILED", "CANCELLED", "CANCEL_REQUESTED"))
      break
    message("export ", st$state, ", waiting")
    Sys.sleep(30)
  }
  if (st$state != "COMPLETED")
    stop("Earth Engine export ", st$state, ": ",
         if (is.null(st$error_message)) "no message given" else st$error_message)

  got <- ee$FeatureCollection(asset_id)$getInfo()
  rows <- lapply(got$features, function(f) as.data.frame(f$properties,
                                                         stringsAsFactors = FALSE))
}

tab <- do.call(rbind, lapply(rows, function(r) {
  wanted <- c("poly_id", unlist(lapply(VARS, function(v)
    paste0(v, c("_mean", "_stdDev", "_count")))))
  missing <- setdiff(wanted, names(r))
  for (m in missing) r[[m]] <- NA_real_
  r[, wanted, drop = FALSE]
}))
tab <- tab[order(tab$poly_id), ]

# The guard that matters: no label may leave this script.
forbidden <- grep("PEST|SPECIES|SEVERITY|AGENT|CAPTURE|lidar|offset|AREA",
                  names(tab), ignore.case = TRUE, value = TRUE)
stopifnot(length(forbidden) == 0)

write.csv(tab, out_csv, row.names = FALSE)

write.csv(data.frame(
  parameter = c("collection", "start", "end", "max_scene_cloud_pct",
                "scl_kept", "scenes_matched", "scenes_corrected",
                "topographic_correction", "dem", "c_fit_scale_m",
                "c_fit_pad_m", "c_fit_min_pixels", "inward_buffer_m",
                "summary_scale_m", "polygons_in", "polygons_dropped_by_buffer",
                "polygons_out", "built"),
  value = c("COPERNICUS/S2_SR_HARMONIZED", START, END, MAX_CLOUD,
            paste(SCL_KEEP, collapse = " "), n_raw, n_fit,
            "SCS+C", "COPERNICUS/DEM/GLO30", FIT_SCALE,
            FIT_PAD_M, FIT_MIN_PX, BUFFER_M,
            SUMM_SCALE, n_all, n_dropped,
            nrow(tab), as.character(Sys.Date())),
  stringsAsFactors = FALSE), log_csv, row.names = FALSE)

cat("\nOPTICAL PREDICTORS\n")
cat("  scenes matched:   ", n_raw, "\n")
cat("  scenes corrected: ", n_fit, "\n")
cat("  polygons:         ", nrow(tab), " of ", n_all, "\n", sep = "")
cat("  variables:        ", length(VARS), " each as mean and standard deviation\n")
cat("  pixels per polygon: median ",
    round(median(tab$B8_count, na.rm = TRUE)), ", min ",
    round(min(tab$B8_count, na.rm = TRUE)), "\n", sep = "")
cat("\nwrote", out_csv, "\n")
cat("wrote", log_csv, "\n")
