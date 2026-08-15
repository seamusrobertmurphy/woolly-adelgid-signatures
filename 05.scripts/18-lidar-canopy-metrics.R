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


# --- from chunk pipe-lidar-fetch, definitions this script depends on ---
tile_map_path <- file.path(derived, "lidar-tile-map.csv")
tile_need_path <- file.path(derived, "lidar-tiles-needed.csv")
lidar_dir <- file.path(inputs, "lidar")
# Two streams, not four. Four saturates the link, and the object store then
# refuses new connections for seventy-five seconds at a time, so the run spends
# longer timing out than downloading.
FETCH_JOBS <- 2L

# The guard is on the tiles being complete, not on the manifest existing. A
# resume after a dropped connection must re-enter this block, and it would not
# if the presence of the manifest were taken as proof the retrieval finished.
lidar_complete <- function() {
  if (!file.exists(tile_need_path)) return(FALSE)
  tn <- read.csv(tile_need_path)
  p <- file.path(lidar_dir, tn$year, tn$filename)
  all(file.exists(p)) && all(file.size(p) == tn$bytes)
}


struct_path <- file.path(derived, "predictors-structural.csv")
struct_log <- file.path(derived, "predictors-structural-log.csv")

# Provisional, and fixed at pre-registration.
CANOPY_MIN_H <- 2     # m, the canopy threshold, shared by cover and gap fraction
CHM_RES      <- 1     # m, canopy height model resolution
DTM_RES      <- 1     # m, terrain surface resolution
GAP_MIN_AREA <- 4     # m2, smallest patch of low canopy counted as a gap
TARGET_DENS  <- 8     # points per m2, the common density, the programme nominal

if (!file.exists(struct_path)) local({
  library(lidR)

  a <- sf::st_read(file.path(derived, "analysis-set.geojson"), quiet = TRUE)
  n_all <- nrow(a)
  poly_id <- sprintf("P%03d", seq_len(n_all))
  # Acquisition year is a design covariate, not a label, and is carried so the
  # campaign sensitivity can be run without rereading the sample.
  lidar_year <- a$lidar_year
  geom <- sf::st_transform(sf::st_geometry(a), BC_ALBERS)
  rm(a)
  eroded <- sf::st_buffer(geom, -BUFFER_M)

  map <- read.csv(tile_map_path, stringsAsFactors = FALSE)
  tn <- read.csv(tile_need_path, stringsAsFactors = FALSE)

  # A smoke-test switch, as scripts 15 and 16 carry. Unset in a render, so the
  # full sample is processed; set to a small number to check the machinery on a
  # few polygons before committing hours to all of them.
  lim <- suppressWarnings(as.integer(Sys.getenv("ADELGID_LIMIT", "")))
  if (!is.na(lim) && lim < n_all) {
    message("SMOKE TEST: first ", lim, " polygons")
    n_all <- lim
  }

  # --- the three metric families, each computed on the normalised cloud -----
  # Family 1 tests vertical redistribution, the prediction that top-down dieback
  # moves canopy material downward while the lower canopy persists.
  # Family 2 tests surface roughness, the prediction that gout and branch
  # deformation roughen the crown.
  # Family 3 describes density and openness, the response both agents share. It
  # is a control: if it alone separates the agents, the result is about damage
  # intensity rather than damage geometry.
  canopy_metrics <- function(las, chm, area_m2) {
    z <- las@data$Z
    z <- z[is.finite(z) & z >= CANOPY_MIN_H]
    if (length(z) < 100) return(NULL)
    first <- las@data[las@data$ReturnNumber == 1L, ]
    zf <- first$Z[is.finite(first$Z)]

    q <- stats::quantile(z, c(.25, .50, .75, .95), names = FALSE)
    zmax <- max(z)

    v <- terra::values(chm, mat = FALSE)
    v_in <- v[!is.na(v)]
    # An empty cell is counted as gap, not as missing: at the common density a
    # 1 m cell expects several returns, so an empty one is an opening rather
    # than an absence of survey.
    n_cells <- length(v)
    n_gap_cells <- sum(is.na(v) | v < CANOPY_MIN_H)

    # Contiguous low patches only. A single empty cell is where one pulse found
    # a hole in a crown, which is a property of the sampling rather than of the
    # stand, so patches below GAP_MIN_AREA are not counted as gaps.
    gap_mask <- terra::ifel(is.na(chm) | chm < CANOPY_MIN_H, 1, NA)
    patches <- terra::patches(gap_mask, directions = 8, zeroAsNA = TRUE)
    psz <- terra::freq(patches)
    keep_px <- if (is.null(psz) || !nrow(psz)) 0 else
      sum(psz$count[psz$count * (CHM_RES^2) >= GAP_MIN_AREA])
    gap_frac <- keep_px * (CHM_RES^2) / area_m2

    data.frame(
      # Family 1, vertical redistribution
      zq25 = q[1], zq50 = q[2], zq75 = q[3], zq95 = q[4],
      zq25_zq95 = if (q[4] > 0) q[1] / q[4] else NA_real_,
      # Canopy relief ratio, (mean - min) / (max - min) over canopy returns.
      crr = if (zmax > min(z)) (mean(z) - min(z)) / (zmax - min(z)) else NA_real_,
      above_two_thirds = sum(z > (2 / 3) * zmax) / length(z),
      # Family 2, surface roughness
      rumple = tryCatch(lidR::rumple_index(chm), error = function(e) NA_real_),
      chm_sd = if (length(v_in) > 1) stats::sd(v_in) else NA_real_,
      cv_first = if (length(zf) > 1 && mean(zf) != 0)
        stats::sd(zf) / mean(zf) else NA_real_,
      # Family 3, density and openness, the control
      cover = if (length(zf)) sum(zf >= CANOPY_MIN_H) / length(zf) else NA_real_,
      gap_frac = gap_frac,
      # Vertical complexity index: Shannon entropy of the height distribution in
      # 1 m bins, normalised by the entropy of a uniform distribution over the
      # same bins, so 1 is an evenly filled profile and 0 a single layer.
      vci = tryCatch(lidR::VCI(z, zmax = zmax, by = 1), error = function(e) NA_real_),
      n_gap_cells = n_gap_cells, n_cells = n_cells,
      stringsAsFactors = FALSE)
  }

  one_polygon <- function(i) {
    tl <- map[map$poly_id == poly_id[i], ]
    if (!nrow(tl)) return(NULL)
    paths <- file.path(lidar_dir, tl$year, tl$filename)
    area_m2 <- as.numeric(sf::st_area(eroded[i]))

    grd <- list(); veg <- list()
    for (k in seq_along(paths)) {
      hdr <- lidR::readLASheader(paths[k])
      crs_tile <- sf::st_crs(hdr)
      if (is.na(crs_tile)) return(NULL)
      pg <- sf::st_transform(eroded[i], crs_tile)
      bb <- sf::st_bbox(pg)
      xy <- sprintf("-keep_xy %f %f %f %f",
                    bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"])

      # Ground at full density: the terrain surface should be as good as the
      # delivery allows, and ground returns are a small share of the whole.
      g <- tryCatch(lidR::readLAS(paths[k], select = "xyzc",
                                  filter = paste(xy, "-keep_class 2")),
                    error = function(e) NULL)
      if (!is.null(g) && !lidR::is.empty(g)) grd[[length(grd) + 1L]] <- g

      # Everything else decimated at read, to the target density with a margin,
      # so the memory never holds the delivered density.
      dens <- tn$density_actual[match(tl$filename[k], tn$filename)]
      frac <- if (is.finite(dens) && dens > TARGET_DENS)
        min(1, (TARGET_DENS * 3) / dens) else 1
      f2 <- if (frac < 1)
        paste(xy, sprintf("-keep_random_fraction %.4f", frac)) else xy
      v <- tryCatch(lidR::readLAS(paths[k], select = "xyzrc", filter = f2),
                    error = function(e) NULL)
      if (!is.null(v) && !lidR::is.empty(v)) veg[[length(veg) + 1L]] <- v
    }
    if (!length(grd) || !length(veg)) return(NULL)

    g <- if (length(grd) == 1) grd[[1]] else do.call(rbind, grd)
    v <- if (length(veg) == 1) veg[[1]] else do.call(rbind, veg)
    pg <- sf::st_transform(eroded[i], sf::st_crs(v))
    v <- tryCatch(lidR::clip_roi(v, pg), error = function(e) NULL)
    if (is.null(v) || lidR::is.empty(v)) return(NULL)
    dens_raw <- nrow(v@data) / area_m2 / (if (length(veg)) 1 else 1)

    # Terrain from class 2 returns only. The delivered tiles carry no vegetation
    # classes, so ground is the one class that can be trusted.
    dtm <- tryCatch(lidR::rasterize_terrain(g, res = DTM_RES,
                                            algorithm = lidR::tin()),
                    error = function(e) NULL)
    if (is.null(dtm)) return(NULL)
    v <- tryCatch(lidR::normalize_height(v, dtm), error = function(e) NULL)
    if (is.null(v)) return(NULL)

    # The common density. Every metric responds to density and density tracks
    # campaign, so this is what stops the model reading the aircraft.
    v <- tryCatch(lidR::decimate_points(v, lidR::homogenize(TARGET_DENS, res = 1)),
                  error = function(e) v)
    dens_used <- nrow(v@data) / area_m2

    chm <- tryCatch(lidR::rasterize_canopy(v, res = CHM_RES,
                                           algorithm = lidR::p2r(subcircle = 0.15)),
                    error = function(e) NULL)
    if (is.null(chm)) return(NULL)

    m <- canopy_metrics(v, chm, area_m2)
    if (is.null(m)) return(NULL)
    cbind(data.frame(poly_id = poly_id[i], area_ha = round(area_m2 / 1e4, 2),
                     n_tiles = nrow(tl), lidar_year = lidar_year[i],
                     dens_raw = round(dens_raw, 1),
                     dens_used = round(dens_used, 2),
                     stringsAsFactors = FALSE), m)
  }

  rows <- list(); failed <- character(0)
  for (i in seq_len(n_all)) {
    r <- tryCatch(one_polygon(i), error = function(e) {
      message("  ", poly_id[i], " failed: ", conditionMessage(e)); NULL })
    if (is.null(r)) failed <- c(failed, poly_id[i]) else rows[[length(rows) + 1L]] <- r
    message(sprintf("  %s %s (%d of %d)", poly_id[i],
                    if (is.null(r)) "FAILED" else "ok", i, n_all))
    invisible(gc())
  }
  tab <- do.call(rbind, rows)
  tab <- tab[order(tab$poly_id), ]

  # The guard that matters: no label may leave this block. lidar_year is a
  # design covariate and is named so it cannot be mistaken for one.
  stopifnot(length(grep("PEST|SPECIES|SEVERITY|AGENT|CAPTURE", names(tab),
                        ignore.case = TRUE)) == 0)
  write.csv(tab, struct_path, row.names = FALSE)

  write.csv(data.frame(
    parameter = c("source", "tiles", "tile_points", "canopy_min_h_m",
                  "chm_res_m", "dtm_res_m", "gap_min_area_m2",
                  "target_density_pts_m2", "ground_class", "normalisation",
                  "chm_algorithm", "gap_rule", "inward_buffer_m",
                  "polygons_in", "polygons_out", "polygons_failed",
                  "density_before_min", "density_before_median",
                  "density_before_max", "density_after_median", "built"),
    value = c("LidarBC classified point clouds", nrow(tn),
              format(sum(as.numeric(tn$bytes)), big.mark = ","),
              CANOPY_MIN_H, CHM_RES, DTM_RES, GAP_MIN_AREA, TARGET_DENS,
              "2 (ground); tiles carry no vegetation classes",
              "TIN terrain from class 2, heights normalised above it",
              "p2r with 0.15 m subcircle",
              paste0("CHM cell below ", CANOPY_MIN_H,
                     " m or empty, in contiguous patches of at least ",
                     GAP_MIN_AREA, " m2"),
              BUFFER_M, n_all, nrow(tab), length(failed),
              min(tab$dens_raw), median(tab$dens_raw), max(tab$dens_raw),
              median(tab$dens_used), as.character(Sys.Date())),
    stringsAsFactors = FALSE), struct_log, row.names = FALSE)
})


