# Build the radar predictor table: Sentinel-1 GRD terrain-flattened backscatter
# and its temporal dispersion, summarised to the survey polygon, in Google Earth
# Engine.
#
# Step 16 of the pipeline in
# docs/science-superpowers/plans/2026-08-14-adelgid-attribution-plan.md.
#
# LANGUAGE DEVIATION FROM THE PLAN. The plan names this step
# `16-build-radar-predictors.js`, an Earth Engine Code Editor script. It is
# written in R against rgee for the reason recorded in script 15: a `.js` file
# cannot be executed from this machine, its output would land in Drive rather
# than in the repository, and the convention that a number be recomputable from
# saved code would break. The Earth Engine logic is unchanged; only the client
# differs.
#
# WHAT THIS SCRIPT MAY NOT DO. It never reads a label. The analysis set is
# stripped to geometry and a positional identifier before anything is sent to
# Earth Engine, and the output is asserted to carry no agent, severity or host
# column. Pre-registration precedes any join of a predictor to a label.
#
# METHOD, following the data preparation section of the manuscript. The
# manuscript specifies orbit refinement, border and thermal noise removal,
# radiometric calibration, terrain flattening against a digital elevation model,
# Range Doppler terrain correction, masking of layover and shadow with the
# sample reduction reported, temporal averaging for speckle, and the mean and
# temporal dispersion of VV and VH retained separately. Where each step is
# performed, and what could not be verified, is set out here.
#
#   1. FROM THE COLLECTION. `COPERNICUS/S1_GRD` is delivered pre-processed with
#      the Sentinel-1 Toolbox. The Earth Engine catalogue page, read on
#      2026-08-14, lists exactly three steps: "Thermal noise removal",
#      "Radiometric calibration", and "Terrain correction using SRTM 30 or ASTER
#      DEM for areas greater than 60 degrees latitude, where SRTM is not
#      available", with the final values converted to decibels by 10*log10.
#      Terrain correction here is Range Doppler orthorectification of position,
#      not radiometric terrain flattening.
#
#      NOT VERIFIED. That page does not state that an orbit file is applied and
#      does not state that GRD border noise removal is performed. Earlier
#      versions of the page are widely quoted as listing both, but the page as
#      it stands does not, and a processing step is not asserted from memory.
#      The manuscript sentence claiming orbit refinement therefore rests on
#      nothing this script can confirm and is flagged for correction. Border
#      noise is handled below rather than assumed.
#
#   2. ADDED HERE, BORDER NOISE. Two conservative measures, because the
#      collection does not document the step. Each scene is clipped to its own
#      footprint eroded inward by BORDER_ERODE_M, which removes the swath edge
#      where the artefact lives, and pixels below BORDER_FLOOR_DB are masked,
#      that value being far below any physical return from forest or from water
#      and characteristic of the low-intensity border strip. Both parameters are
#      provisional and are fixed at pre-registration.
#
#   3. ADDED HERE, TERRAIN FLATTENING. Radiometric slope correction by the
#      angular volumetric model, appropriate to a vegetated surface, following
#      Vollrath, Mullissa and Reiche (2020), Remote Sensing 12(11):1867. The
#      equations were read from the paper and the implementation checked against
#      the authors' own module at ESA-PhiLab/radiometric-slope-correction
#      (javascript/slope_correction_module.js), both on 2026-08-14. As printed:
#
#         gamma0   = sigma0 / cos(theta_i)
#         alpha_r  = arctan(tan(alpha_s) cos(phi_r))
#         gamma0_f = gamma0 * tan(90 - theta_i) / tan(90 - theta_i + alpha_r)
#
#      with theta_i the incidence angle, alpha_s the terrain slope, phi_r the
#      radar look direction minus the slope aspect, and alpha_r the slope
#      steepness in the range direction. The look direction is taken, as the
#      authors take it, from the aspect of the incidence angle band.
#
#   4. ADDED HERE, LAYOVER AND SHADOW. Masked on the conditions as printed:
#      active layover where alpha_r > theta_i, active shadow where
#      alpha_r < -(90 - theta_i). The retained fraction of every polygon is
#      written to the output so the reduction is reported rather than absorbed.
#
#   5. TEMPORAL STATISTICS, AND WHY THEY ARE COMPUTED WITHIN ORBIT PASS. The
#      manuscript asks for temporal averaging across the scene stack and for the
#      mean and the temporal dispersion retained separately. Ascending and
#      descending passes view the same slope from opposite sides, and terrain
#      flattening reduces but does not erase the difference. Pooling the passes
#      into one time series would therefore inflate the dispersion by an amount
#      that varies with slope and aspect, which is precisely the terrain-driven
#      predictor the preparation section exists to prevent. Both statistics are
#      accordingly formed within pass and then combined across passes unweighted:
#      the level as the mean of the per-pass mean power, the dispersion as the
#      root of the mean per-pass variance. A pass carrying fewer than
#      MIN_PASS_SCENES scenes is dropped and counted. This is a deviation from
#      the plan's silence on the point, not from anything it fixes, and it is
#      recorded for pre-registration.
#
#      The level is averaged in power and converted to decibels afterwards,
#      because averaging decibels averages logarithms and biases the result low.
#      The dispersion is the standard deviation of the decibel series, since
#      speckle is multiplicative and so additive in the log, which makes the
#      decibel standard deviation a dispersion that does not scale with level.
#
#   6. SUMMARISATION. Each of the four pixel-level variables is reduced to the
#      inward-buffered survey polygon as a mean and a standard deviation, so a
#      heterogeneous polygon is not represented solely by a central value. The
#      buffer distance matches script 15.
#
# PARAMETERS THAT PRE-REGISTRATION FIXES. The inward buffer, the border noise
# floor and erosion, the minimum scenes per pass, and the choice of the
# volumetric over the surface scattering model are provisional here.
#
# Usage:
#   Rscript 05.scripts/16-build-radar-predictors.R [--limit N] [--getinfo]
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

EE_PROJECT   <- "murphys-deforisk"
BC_ALBERS    <- 3005
START        <- "2019-06-01"   # the window of script 15, so the two sensors
END          <- "2021-09-30"   # describe the same epoch
BUFFER_M     <- 20      # inward erosion of the survey polygon, as in script 15
BORDER_ERODE_M <- 1000  # inward erosion of the scene footprint, border noise
BORDER_FLOOR_DB <- -30  # backscatter below this is border artefact, not target
MIN_PASS_SCENES <- 5    # a pass with fewer scenes gives no usable dispersion
SUMM_SCALE   <- 20      # metres, scale of the polygon summary, as in script 15
HEADING_SCALE <- 1000   # metres, scale of the look direction estimate

POLS   <- c("VV", "VH")
PASSES <- c("ASCENDING", "DESCENDING")
VARS   <- c("VV_gamma0", "VH_gamma0", "VV_tsd", "VH_tsd")

# ---------------------------------------------------------------- the sample

aset <- st_read(file.path(derived, "analysis-set.geojson"), quiet = TRUE)
n_all <- nrow(aset)

# poly_id is positional in the frozen file, derived here exactly as script 15
# derives it, so the two predictor tables join on a common key.
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

# Scene selection is bounded by the sample itself. sf_as_ee on an sfc returns an
# ee$Geometry, not a Feature; calling $geometry() on it would raise.
region <- sf_as_ee(st_transform(st_union(geom), 4326))

dem <- ee$ImageCollection("COPERNICUS/DEM/GLO30")$
  select("DEM")$
  mosaic()$
  setDefaultProjection("EPSG:3857", NULL, 30)

ninety_rad <- ee$Image$constant(90)$multiply(pi / 180)

# Angular radiometric slope correction, volumetric model. Faithful to Vollrath,
# Mullissa and Reiche (2020) and to the authors' module; see the header.
slope_correct <- function(img) {
  scene <- img$geometry()
  proj <- img$select("VV")$projection()

  # The look direction is the aspect of the incidence angle surface, taken at a
  # coarse scale over the scene because it is near constant across the swath.
  heading <- ee$Terrain$aspect(img$select("angle"))$
    reduceRegion(reducer = ee$Reducer$mean(),
                 geometry = scene,
                 scale = HEADING_SCALE,
                 maxPixels = 1e9,
                 bestEffort = TRUE)$get("aspect")

  sigma0_pow <- ee$Image$constant(10)$pow(img$select(POLS)$divide(10))

  # Radar geometry
  theta_i <- img$select("angle")$multiply(pi / 180)$clip(scene)
  phi_i <- ee$Image$constant(heading)$multiply(pi / 180)

  # Terrain geometry, evaluated in the projection of the radar image
  alpha_s <- ee$Terrain$slope(dem)$select("slope")$
    multiply(pi / 180)$setDefaultProjection(proj)$clip(scene)
  phi_s <- ee$Terrain$aspect(dem)$select("aspect")$
    multiply(pi / 180)$setDefaultProjection(proj)$clip(scene)

  # Slope steepness in the range direction
  phi_r <- phi_i$subtract(phi_s)
  alpha_r <- alpha_s$tan()$multiply(phi_r$cos())$atan()

  # gamma0 = sigma0 / cos(theta_i), then the volumetric scattering area factor
  gamma0 <- sigma0_pow$divide(theta_i$cos())
  scf <- ninety_rad$subtract(theta_i)$add(alpha_r)$tan()$
    divide(ninety_rad$subtract(theta_i)$tan())
  gamma0_flat <- gamma0$divide(scf)

  g_db <- ee$Image$constant(10)$multiply(gamma0_flat$log10())$
    select(POLS)$rename(POLS)

  # Valid where neither in active layover nor in active shadow
  valid <- alpha_r$lt(theta_i)$
    And(alpha_r$gt(ninety_rad$subtract(theta_i)$multiply(-1)))

  g_db$updateMask(valid)$
    updateMask(g_db$gt(BORDER_FLOOR_DB))$
    clip(scene$buffer(-BORDER_ERODE_M, 100))$
    copyProperties(img, list("system:time_start", "orbitProperties_pass"))
}

to_power <- function(img) {
  ee$Image$constant(10)$pow(img$select(POLS)$divide(10))$
    copyProperties(img, list("system:time_start"))
}

raw <- ee$ImageCollection("COPERNICUS/S1_GRD")$
  filterBounds(region)$
  filterDate(START, END)$
  filter(ee$Filter$eq("instrumentMode", "IW"))$
  filter(ee$Filter$eq("resolution_meters", 10))$
  filter(ee$Filter$listContains("transmitterReceiverPolarisation", "VV"))$
  filter(ee$Filter$listContains("transmitterReceiverPolarisation", "VH"))

n_raw <- raw$size()$getInfo()
message(n_raw, " Sentinel-1 IW GRD scenes match the window, mode and polarisation")
stopifnot(n_raw > 0)

corrected <- raw$map(ee_utils_pyfunc(slope_correct))

# ------------------------------------------- per pass, then across passes
# Within pass because the two look directions are not interchangeable on slopes
# even after flattening; see the header.

pow_list <- list()
var_list <- list()
pass_n <- setNames(integer(length(PASSES)), PASSES)

for (p in PASSES) {
  cp <- corrected$filter(ee$Filter$eq("orbitProperties_pass", p))
  n_p <- cp$size()$getInfo()
  pass_n[p] <- n_p
  message(n_p, " scenes on the ", p, " pass")
  if (n_p < MIN_PASS_SCENES) {
    message("  dropped: fewer than ", MIN_PASS_SCENES, " scenes")
    next
  }
  # Level in power, dispersion in decibels.
  pow_list[[p]] <- cp$map(ee_utils_pyfunc(to_power))$mean()
  var_list[[p]] <- cp$select(POLS)$reduce(ee$Reducer$stdDev())$pow(2)
}

n_used <- sum(pass_n[names(pow_list)])
stopifnot(length(pow_list) > 0)
message(length(pow_list), " pass(es) retained, ", n_used, " scenes in total")

mean_pow <- ee$ImageCollection$fromImages(unname(pow_list))$mean()
gamma_db <- mean_pow$log10()$multiply(10)$rename(c("VV_gamma0", "VH_gamma0"))

pooled_sd <- ee$ImageCollection$fromImages(unname(var_list))$mean()$sqrt()$
  rename(c("VV_tsd", "VH_tsd"))

# An unmasked copy of one band gives the polygon's full pixel count at the same
# grid, so the layover and shadow loss can be reported as a retained fraction
# rather than left implicit in a smaller count.
all_band <- gamma_db$select("VV_gamma0")$unmask(-999)$rename("ALL")

stack <- gamma_db$addBands(pooled_sd)$addBands(all_band)

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
out_csv <- file.path(derived, "predictors-radar.csv")
log_csv <- file.path(derived, "predictors-radar-log.csv")

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
  asset_id <- sprintf("projects/%s/assets/adelgid-radar-%s", EE_PROJECT, stamp)
  message("exporting to ", asset_id)
  try(ee_manage_delete(asset_id), silent = TRUE)
  task <- ee_table_to_asset(collection = summaries,
                           description = paste0("adelgid_radar_", stamp),
                           assetId = asset_id)
  task$start()

  # Poll to completion rather than for a fixed number of attempts. Reading the
  # asset before the task has written it fails with a misleading "not found".
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
  wanted <- c("poly_id",
              unlist(lapply(VARS, function(v)
                paste0(v, c("_mean", "_stdDev", "_count")))),
              "ALL_count")
  missing <- setdiff(wanted, names(r))
  for (m in missing) r[[m]] <- NA_real_
  r[, wanted, drop = FALSE]
}))
tab <- tab[order(tab$poly_id), ]

# The reduction the manuscript requires to be reported: what layover, shadow and
# the border measures removed from each polygon.
tab$retained_frac <- round(tab$VV_gamma0_count / tab$ALL_count, 4)

# The guard that matters: no label may leave this script.
forbidden <- grep("PEST|SPECIES|SEVERITY|AGENT|CAPTURE|lidar|offset|AREA",
                  names(tab), ignore.case = TRUE, value = TRUE)
stopifnot(length(forbidden) == 0)

write.csv(tab, out_csv, row.names = FALSE)

write.csv(data.frame(
  parameter = c("collection", "start", "end", "instrument_mode",
                "polarisations", "resolution_m", "scenes_matched",
                "scenes_ascending", "scenes_descending", "scenes_used",
                "passes_retained", "min_scenes_per_pass",
                "collection_preprocessing", "orbit_file",
                "border_noise_handling", "border_floor_db",
                "border_erode_m", "terrain_flattening", "dem",
                "layover_shadow_mask", "temporal_statistics",
                "inward_buffer_m", "summary_scale_m", "heading_scale_m",
                "polygons_in", "polygons_dropped_by_buffer", "polygons_out",
                "min_retained_frac", "median_retained_frac", "built"),
  value = c("COPERNICUS/S1_GRD", START, END, "IW",
            paste(POLS, collapse = " "), 10, n_raw,
            pass_n[["ASCENDING"]], pass_n[["DESCENDING"]], n_used,
            paste(names(pow_list), collapse = " "), MIN_PASS_SCENES,
            "thermal noise removal, radiometric calibration, Range Doppler terrain correction",
            "not documented by the Earth Engine catalogue, not asserted",
            "scene footprint eroded and low-intensity floor masked, applied here",
            BORDER_FLOOR_DB,
            BORDER_ERODE_M, "angular volumetric model, Vollrath et al. 2020",
            "COPERNICUS/DEM/GLO30",
            "active layover alpha_r > theta_i, active shadow alpha_r < -(90 - theta_i)",
            "within orbit pass, level as mean power, dispersion as dB standard deviation",
            BUFFER_M, SUMM_SCALE, HEADING_SCALE,
            n_all, n_dropped, nrow(tab),
            min(tab$retained_frac, na.rm = TRUE),
            median(tab$retained_frac, na.rm = TRUE),
            as.character(Sys.Date())),
  stringsAsFactors = FALSE), log_csv, row.names = FALSE)

cat("\nRADAR PREDICTORS\n")
cat("  scenes matched:   ", n_raw, "\n")
cat("  scenes used:      ", n_used, " over ", length(pow_list), " pass(es)\n", sep = "")
cat("  polygons:         ", nrow(tab), " of ", n_all, "\n", sep = "")
cat("  variables:        ", length(VARS),
    " each as mean and standard deviation\n")
cat("  pixels per polygon: median ",
    round(median(tab$VV_gamma0_count, na.rm = TRUE)), ", min ",
    round(min(tab$VV_gamma0_count, na.rm = TRUE)), "\n", sep = "")
cat("  retained fraction:  median ",
    sprintf("%.3f", median(tab$retained_frac, na.rm = TRUE)), ", min ",
    sprintf("%.3f", min(tab$retained_frac, na.rm = TRUE)), "\n", sep = "")
cat("\nwrote", out_csv, "\n")
cat("wrote", log_csv, "\n")
