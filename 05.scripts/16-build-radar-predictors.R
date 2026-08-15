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

# --- from chunk pipe-optical, definitions this script depends on ---
opt_path <- file.path(derived, "predictors-optical.csv")
opt_log <- file.path(derived, "predictors-optical-log.csv")

EE_PROJECT <- "murphys-deforisk"
S2_START <- "2019-06-01"
S2_END <- "2021-09-30"
BUFFER_M <- 20            # inward erosion of the survey polygon, provisional
SUMM_SCALE <- 20          # metres, scale of the polygon summary


rad_path <- file.path(derived, "predictors-radar.csv")
rad_log <- file.path(derived, "predictors-radar-log.csv")

if (!file.exists(rad_path)) local({
  library(rgee)
  BORDER_ERODE_M <- 1000   # inward erosion of the scene footprint, border noise
  BORDER_FLOOR_DB <- -30   # below this is border artefact, not target
  MIN_PASS_SCENES <- 5     # a pass with fewer gives no usable dispersion
  HEADING_SCALE <- 1000    # metres, scale of the look direction estimate
  POLS <- c("VV", "VH")
  PASSES <- c("ASCENDING", "DESCENDING")
  VARS <- c("VV_gamma0", "VH_gamma0", "VV_tsd", "VH_tsd")

  a <- sf::st_read(file.path(derived, "analysis-set.geojson"), quiet = TRUE)
  n_all <- nrow(a)
  poly_id <- sprintf("P%03d", seq_len(n_all))
  geom <- sf::st_transform(sf::st_geometry(a), BC_ALBERS)
  rm(a)
  eroded <- sf::st_buffer(geom, -BUFFER_M)
  alive <- !sf::st_is_empty(eroded)
  n_dropped <- sum(!alive)
  polys <- sf::st_sf(poly_id = poly_id[alive],
                     geometry = sf::st_transform(eroded[alive], 4326))
  stopifnot(identical(setdiff(names(polys), "geometry"), "poly_id"))

  ee_Initialize(project = EE_PROJECT, quiet = TRUE)
  fc <- sf_as_ee(polys)
  # sf_as_ee on an sfc returns an ee$Geometry, not a Feature.
  region <- sf_as_ee(sf::st_transform(sf::st_union(geom), 4326))

  dem <- ee$ImageCollection("COPERNICUS/DEM/GLO30")$select("DEM")$mosaic()$
    setDefaultProjection("EPSG:3857", NULL, 30)
  ninety_rad <- ee$Image$constant(90)$multiply(pi / 180)

  # Angular radiometric slope correction, volumetric model. The equations were
  # read from Vollrath, Mullissa and Reiche (2020) and the implementation checked
  # against the authors' own module:
  #   gamma0   = sigma0 / cos(theta_i)
  #   alpha_r  = arctan(tan(alpha_s) cos(phi_r))
  #   gamma0_f = gamma0 * tan(90 - theta_i) / tan(90 - theta_i + alpha_r)
  slope_correct <- function(img) {
    scene <- img$geometry()
    proj <- img$select("VV")$projection()
    # The look direction is the aspect of the incidence angle surface, taken
    # coarsely because it is near constant across the swath.
    heading <- ee$Terrain$aspect(img$select("angle"))$
      reduceRegion(reducer = ee$Reducer$mean(), geometry = scene,
                   scale = HEADING_SCALE, maxPixels = 1e9, bestEffort = TRUE)$
      get("aspect")
    sigma0_pow <- ee$Image$constant(10)$pow(img$select(POLS)$divide(10))
    theta_i <- img$select("angle")$multiply(pi / 180)$clip(scene)
    phi_i <- ee$Image$constant(heading)$multiply(pi / 180)
    # Terrain geometry, evaluated in the projection of the radar image.
    alpha_s <- ee$Terrain$slope(dem)$select("slope")$multiply(pi / 180)$
      setDefaultProjection(proj)$clip(scene)
    phi_s <- ee$Terrain$aspect(dem)$select("aspect")$multiply(pi / 180)$
      setDefaultProjection(proj)$clip(scene)
    alpha_r <- alpha_s$tan()$multiply(phi_i$subtract(phi_s)$cos())$atan()
    gamma0 <- sigma0_pow$divide(theta_i$cos())
    scf <- ninety_rad$subtract(theta_i)$add(alpha_r)$tan()$
      divide(ninety_rad$subtract(theta_i)$tan())
    g_db <- ee$Image$constant(10)$multiply(gamma0$divide(scf)$log10())$
      select(POLS)$rename(POLS)
    # Valid where neither in active layover nor in active shadow.
    valid <- alpha_r$lt(theta_i)$
      And(alpha_r$gt(ninety_rad$subtract(theta_i)$multiply(-1)))
    g_db$updateMask(valid)$updateMask(g_db$gt(BORDER_FLOOR_DB))$
      clip(scene$buffer(-BORDER_ERODE_M, 100))$
      copyProperties(img, list("system:time_start", "orbitProperties_pass"))
  }

  to_power <- function(img) {
    ee$Image$constant(10)$pow(img$select(POLS)$divide(10))$
      copyProperties(img, list("system:time_start"))
  }

  raw <- ee$ImageCollection("COPERNICUS/S1_GRD")$
    filterBounds(region)$filterDate(S2_START, S2_END)$
    filter(ee$Filter$eq("instrumentMode", "IW"))$
    filter(ee$Filter$eq("resolution_meters", 10))$
    filter(ee$Filter$listContains("transmitterReceiverPolarisation", "VV"))$
    filter(ee$Filter$listContains("transmitterReceiverPolarisation", "VH"))
  n_raw <- raw$size()$getInfo()
  corrected <- raw$map(ee_utils_pyfunc(slope_correct))

  pow_list <- list(); var_list <- list()
  pass_n <- stats::setNames(integer(length(PASSES)), PASSES)
  for (p in PASSES) {
    cp <- corrected$filter(ee$Filter$eq("orbitProperties_pass", p))
    n_p <- cp$size()$getInfo()
    pass_n[p] <- n_p
    if (n_p < MIN_PASS_SCENES) next
    pow_list[[p]] <- cp$map(ee_utils_pyfunc(to_power))$mean()
    var_list[[p]] <- cp$select(POLS)$reduce(ee$Reducer$stdDev())$pow(2)
  }
  n_used <- sum(pass_n[names(pow_list)])
  stopifnot(length(pow_list) > 0)

  gamma_db <- ee$ImageCollection$fromImages(unname(pow_list))$mean()$
    log10()$multiply(10)$rename(c("VV_gamma0", "VH_gamma0"))
  pooled_sd <- ee$ImageCollection$fromImages(unname(var_list))$mean()$sqrt()$
    rename(c("VV_tsd", "VH_tsd"))
  # An unmasked copy of one band gives the polygon's full pixel count on the
  # same grid, so the layover and shadow loss is reported as a retained fraction
  # rather than left implicit in a smaller count.
  all_band <- gamma_db$select("VV_gamma0")$unmask(-999)$rename("ALL")
  stack <- gamma_db$addBands(pooled_sd)$addBands(all_band)

  reducer <- ee$Reducer$mean()$
    combine(reducer2 = ee$Reducer$stdDev(), sharedInputs = TRUE)$
    combine(reducer2 = ee$Reducer$count(), sharedInputs = TRUE)
  summaries <- stack$reduceRegions(collection = fc, reducer = reducer,
                                   scale = SUMM_SCALE, tileScale = 4L)

  asset_id <- sprintf("projects/%s/assets/adelgid-radar-%s", EE_PROJECT,
                      format(Sys.Date(), "%Y%m%d"))
  try(ee_manage_delete(asset_id), silent = TRUE)
  task <- ee_table_to_asset(collection = summaries,
                            description = "adelgid_radar", assetId = asset_id)
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
      paste0(v, c("_mean", "_stdDev", "_count")))), "ALL_count")
    for (m in setdiff(wanted, names(r))) r[[m]] <- NA_real_
    r[, wanted, drop = FALSE]
  }))
  tab <- tab[order(tab$poly_id), ]
  # The reduction the methods require to be reported.
  tab$retained_frac <- round(tab$VV_gamma0_count / tab$ALL_count, 4)

  stopifnot(length(grep("PEST|SPECIES|SEVERITY|AGENT|CAPTURE|lidar|offset|AREA",
                        names(tab), ignore.case = TRUE)) == 0)
  write.csv(tab, rad_path, row.names = FALSE)
  write.csv(data.frame(
    parameter = c("collection", "start", "end", "instrument_mode",
                  "polarisations", "resolution_m", "scenes_matched",
                  "scenes_ascending", "scenes_descending", "scenes_used",
                  "collection_preprocessing", "orbit_file",
                  "border_noise_handling", "border_floor_db", "border_erode_m",
                  "terrain_flattening", "dem", "layover_shadow_mask",
                  "temporal_statistics", "inward_buffer_m", "summary_scale_m",
                  "polygons_in", "polygons_dropped_by_buffer", "polygons_out",
                  "min_retained_frac", "built"),
    value = c("COPERNICUS/S1_GRD", S2_START, S2_END, "IW",
              paste(POLS, collapse = " "), 10, n_raw,
              pass_n[["ASCENDING"]], pass_n[["DESCENDING"]], n_used,
              "thermal noise removal, calibration, Range Doppler terrain correction",
              "not documented by the Earth Engine catalogue, not asserted",
              "scene footprint eroded and low-intensity floor masked, applied here",
              BORDER_FLOOR_DB, BORDER_ERODE_M,
              "angular volumetric model, Vollrath et al. 2020",
              "COPERNICUS/DEM/GLO30",
              "active layover alpha_r > theta_i, active shadow alpha_r < -(90 - theta_i)",
              "within orbit pass, level as mean power, dispersion as dB standard deviation",
              BUFFER_M, SUMM_SCALE, n_all, n_dropped, nrow(tab),
              min(tab$retained_frac, na.rm = TRUE), as.character(Sys.Date())),
    stringsAsFactors = FALSE), rad_log, row.names = FALSE)
})


