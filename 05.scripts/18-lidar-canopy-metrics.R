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
# The common density is raised from the 8 of the programme nominal because the
# midstorey and permeability metrics below depend on pulses reaching the lower
# canopy, and the delivered archive supports it: per-polygon delivered density
# has a median of 43.9 and raising the target from 8 to 16 costs three polygons.
TARGET_DENS  <- 16    # points per m2, the common density
UNDER_TOP    <- 5     # m, top of the understorey stratum
MID_TOP      <- 15    # m, top of the midstorey stratum, spanning the 11 to 12 m
                      # band in which @Boucher_2020 located the adelgid signal
# The book interpolates terrain at 0.5 m on a 1 ha clip. These polygons run to
# 353 ha, where 0.5 m is 14 million cells and inverse distance weighting takes
# a quarter of an hour for one polygon. The interpolator is kept and the
# resolution matched to the 1 m canopy model, which discards finer terrain
# detail anyway.
DTM_RES_FINE <- 1.0   # m, terrain resolution

if (!file.exists(struct_path)) local({
  library(lidR)
  # lidR defaults to one thread here. The interpolation and decimation steps
  # below are the run's cost and both parallelise, so give them half the cores
  # and leave the rest for the operating system on an 8 GB machine.
  # This lidR build carries no OpenMP support, so the thread setting has no
  # effect and every step below is single threaded. Recorded because it is the
  # reason the run is measured in hours.
  lidR::set_lidr_threads(4L)

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
  canopy_metrics <- function(las, chm, pg) {
    z <- las@data$Z
    z <- z[is.finite(z) & z >= CANOPY_MIN_H]
    if (length(z) < 100) return(NULL)
    first <- las@data[las@data$ReturnNumber == 1L, ]
    zf <- first$Z[is.finite(first$Z)]

    # The full profile, not only the canopy, because the three variables below
    # describe what happens beneath it. Returns are taken from 0.5 m upward so
    # that ground and near-ground returns do not dominate the proportions.
    zall <- las@data$Z
    zall <- zall[is.finite(zall) & zall >= 0.5]

    q <- stats::quantile(z, c(.25, .50, .75, .95, .99), names = FALSE)
    # The 99th percentile stands in for the maximum throughout. The delivered
    # tiles carry a low-noise class but no high-noise class, so a single bird or
    # atmospheric return tens of metres above the canopy would otherwise set the
    # ceiling for every ratio below it and drive them all towards zero.
    ztop <- q[5]

    # Cell accounting is confined to the polygon. The canopy model is
    # rectangular and its corners lie outside, where an empty cell means absence
    # of polygon rather than absence of canopy; counting those as gaps is what
    # would put gap fraction at 0.85 beside a canopy cover of 0.94.
    inside <- terra::rasterize(terra::vect(pg), chm, field = 1)
    in_cell <- !is.na(terra::values(inside, mat = FALSE))
    v <- terra::values(chm, mat = FALSE)
    n_cells <- sum(in_cell)
    v_in <- v[in_cell]
    v_in <- v_in[!is.na(v_in)]

    # Within the polygon an empty cell is counted as gap rather than as missing:
    # at the common density a 1 m cell expects several returns, so an empty one
    # is an opening. Contiguous patches only, since a single empty cell is where
    # one pulse found a hole in a crown, which is a property of the sampling
    # rather than of the stand.
    gap_r <- terra::ifel(!is.na(inside) & (is.na(chm) | chm < CANOPY_MIN_H),
                         1, NA)
    patches <- terra::patches(gap_r, directions = 8, zeroAsNA = TRUE)
    psz <- terra::freq(patches)
    keep_px <- if (is.null(psz) || !nrow(psz)) 0 else
      sum(psz$count[psz$count * (CHM_RES^2) >= GAP_MIN_AREA])
    gap_frac <- if (n_cells > 0) keep_px / n_cells else NA_real_

    data.frame(
      # Family 1, vertical redistribution
      zq25 = q[1], zq50 = q[2], zq75 = q[3], zq95 = q[4],
      zq25_zq95 = if (q[4] > 0) q[1] / q[4] else NA_real_,
      # Canopy relief ratio, (mean - min) / (top - min) over canopy returns.
      crr = if (ztop > min(z)) (mean(z) - min(z)) / (ztop - min(z)) else NA_real_,
      above_two_thirds = sum(z > (2 / 3) * ztop) / length(z),
      # Family 2, surface roughness
      rumple = tryCatch(lidR::rumple_index(chm), error = function(e) NA_real_),
      chm_sd = if (length(v_in) > 1) stats::sd(v_in) else NA_real_,
      cv_first = if (length(zf) > 1 && mean(zf) != 0)
        stats::sd(zf) / mean(zf) else NA_real_,
      # Family 4, the lower profile, following @Boucher_2020, who located 60
      # percent of the variation in hemlock mortality in midstorey plant area
      # and canopy permeability rather than in the overstorey.
      # rh10 is the height below which a tenth of returns fall, the discrete
      # return analogue of the waveform RH10 that paper used for permeability:
      # a canopy thinning from beneath lets pulses deeper and lowers it.
      rh10 = if (length(zall) > 10)
        stats::quantile(zall, 0.10, names = FALSE) else NA_real_,
      p_mid = if (length(zall))
        sum(zall >= UNDER_TOP & zall < MID_TOP) / length(zall) else NA_real_,
      p_under = if (length(zall))
        sum(zall < UNDER_TOP) / length(zall) else NA_real_,
      # Family 3, density and openness, the control
      cover = if (length(zf)) sum(zf >= CANOPY_MIN_H) / length(zf) else NA_real_,
      gap_frac = gap_frac,
      # Vertical complexity index: Shannon entropy of the height distribution in
      # 1 m bins, normalised by the entropy of a uniform distribution over the
      # same bins, so 1 is an evenly filled profile and 0 a single layer.
      vci = tryCatch(lidR::VCI(z, zmax = ztop, by = 1), error = function(e) NA_real_),
      ztop = ztop, n_cells = n_cells,
      stringsAsFactors = FALSE)
  }

  one_polygon <- function(i) {
    tl <- map[map$poly_id == poly_id[i], ]
    if (!nrow(tl)) return("no tile matched in the index")
    paths <- file.path(lidar_dir, tl$year, tl$filename)
    area_m2 <- as.numeric(sf::st_area(eroded[i]))

    grd <- list(); veg <- list()
    for (k in seq_along(paths)) {
      hdr <- lidR::readLASheader(paths[k])
      crs_tile <- sf::st_crs(hdr)
      if (is.na(crs_tile)) return("tile carries no CRS")
      pg <- sf::st_transform(eroded[i], crs_tile)
      bb <- sf::st_bbox(pg)
      xy <- sprintf("-keep_xy %f %f %f %f",
                    bb["xmin"], bb["ymin"], bb["xmax"], bb["ymax"])

      # One read per tile, not two. A reader must decompress every point in a
      # chunk before it can discard any, so a second pass for ground costs a
      # second full decompression and buys nothing: reading once and splitting
      # in memory halves the only expensive step in this block. The full tile is
      # released before the next one is opened, so the peak is one tile.
      las <- tryCatch(lidR::readLAS(paths[k], select = "xyzrc", filter = xy),
                      error = function(e) NULL)
      if (is.null(las) || lidR::is.empty(las)) next

      # Noise removal before anything else, by statistical outlier removal,
      # following the lidar-forestry book. Without it a single high return sets
      # the canopy ceiling and every ratio built on it collapses towards zero.
      las <- tryCatch(lidR::classify_noise(las, lidR::sor(k = 10, m = 3)),
                      error = function(e) las)
      las <- lidR::filter_poi(las, Classification != LASNOISE)
      if (lidR::is.empty(las)) next

      # Ground at full density: the terrain surface should be as good as the
      # delivery allows, and ground returns are a small share of the whole.
      g <- lidR::filter_poi(las, Classification == 2L)
      if (!lidR::is.empty(g)) grd[[length(grd) + 1L]] <- g

      # Everything else brought down towards the common density with a margin,
      # so the merged cloud never holds the delivered density.
      dens <- tn$density_actual[match(tl$filename[k], tn$filename)]
      v <- if (is.finite(dens) && dens > TARGET_DENS * 2)
        lidR::decimate_points(las, lidR::random(TARGET_DENS * 2)) else las
      if (!lidR::is.empty(v)) veg[[length(veg) + 1L]] <- v
      rm(las); invisible(gc())
    }
    # The index is a footprint layer and its footprints claim ground the
    # delivered clouds do not cover, so a polygon can match a tile and still
    # have no points in it. That is a coverage fact and is reported, not
    # silently dropped.
    if (!length(grd) || !length(veg))
      return("no returns inside the polygon: the tile index claims coverage the point cloud does not contain")

    g <- if (length(grd) == 1) grd[[1]] else do.call(rbind, grd)
    v <- if (length(veg) == 1) veg[[1]] else do.call(rbind, veg)
    pg <- sf::st_transform(eroded[i], sf::st_crs(v))
    v <- tryCatch(lidR::clip_roi(v, pg), error = function(e) NULL)
    if (is.null(v) || lidR::is.empty(v)) return("no returns after clipping to the polygon")
    dens_raw <- nrow(v@data) / area_m2 / (if (length(veg)) 1 else 1)

    # Terrain from class 2 returns only. The delivered tiles carry no vegetation
    # classes, so ground is the one class that can be trusted.
    # Triangulation rather than the inverse distance weighting the
    # lidar-forestry book prefers [@Tu_2020], and the deviation is measured
    # rather than assumed. On one polygon's 806,000 ground returns the two
    # surfaces agree to 0.19 m with a correlation of 0.9999, but triangulation
    # takes 5.1 s against 61 s and leaves 180 cells to nearest-neighbour
    # fallback against 71,357. The book's parameters are tuned to a 1 ha clip;
    # these polygons reach 353 ha, where a 50 m search radius is often empty.
    # The tiles carry a delivered ground class, so the cloth simulation filter
    # the book applies to unclassified data is not needed [@Zhang_2016].
    dtm <- tryCatch(lidR::rasterize_terrain(g, res = DTM_RES_FINE,
                                            algorithm = lidR::tin()),
                    error = function(e) NULL)
    if (is.null(dtm)) return("terrain surface could not be interpolated")
    v <- tryCatch(lidR::normalize_height(v, dtm), error = function(e) NULL)
    if (is.null(v)) return("height normalisation failed")

    # The common density. Every metric responds to density and density tracks
    # campaign, so this is what stops the model reading the aircraft.
    v <- tryCatch(lidR::decimate_points(v, lidR::homogenize(TARGET_DENS, res = 1)),
                  error = function(e) v)
    dens_used <- nrow(v@data) / area_m2

    # Triangulated surface with an 8 m maximum edge, following the
    # lidar-forestry book. The edge limit is also the gap rule: an opening wider
    # than 8 m is left empty rather than interpolated across.
    chm <- tryCatch(lidR::rasterize_canopy(v, res = CHM_RES,
                                           algorithm = lidR::dsmtin(max_edge = 8)),
                    error = function(e) NULL)
    if (is.null(chm)) return("canopy height model could not be built")

    m <- canopy_metrics(v, chm, pg)
    if (is.null(m)) return("fewer than 100 canopy returns above the canopy threshold")
    cbind(data.frame(poly_id = poly_id[i], area_ha = round(area_m2 / 1e4, 2),
                     n_tiles = nrow(tl), lidar_year = lidar_year[i],
                     dens_raw = round(dens_raw, 1),
                     dens_used = round(dens_used, 2),
                     stringsAsFactors = FALSE), m)
  }

  # Each polygon is written as it finishes, and a restart skips whatever is
  # already recorded. The run takes hours and this machine has interrupted it
  # more than once; holding the whole table in memory until the end means an
  # interruption at the eightieth polygon discards the other seventy-nine.
  part_path <- file.path(derived, "predictors-structural-partial.csv")
  drop_path <- file.path(derived, "structural-dropped.csv")
  append_row <- function(df, path) {
    write.table(df, path, sep = ",", row.names = FALSE, qmethod = "double",
                col.names = !file.exists(path), append = file.exists(path))
  }
  done_ids <- character(0)
  for (p in c(part_path, drop_path))
    if (file.exists(p)) done_ids <- c(done_ids, read.csv(p)$poly_id)
  if (length(done_ids))
    message("resuming: ", length(done_ids), " polygons already recorded")

  for (i in seq_len(n_all)) {
    if (poly_id[i] %in% done_ids) next
    r <- tryCatch(one_polygon(i),
                  error = function(e) paste("error:", conditionMessage(e)))
    if (is.character(r) || is.null(r)) {
      why <- if (is.null(r)) "unknown" else r
      # A polygon that produced no metrics is written out with its reason, so
      # the difference between the frozen sample and this table is auditable
      # rather than a silent shrinkage.
      append_row(data.frame(poly_id = poly_id[i], reason = why,
                            stringsAsFactors = FALSE), drop_path)
      message(sprintf("  %s DROPPED (%d of %d): %s", poly_id[i], i, n_all, why))
    } else {
      append_row(r, part_path)
      message(sprintf("  %s ok (%d of %d)", poly_id[i], i, n_all))
    }
    invisible(gc())
  }
  tab <- read.csv(part_path, stringsAsFactors = FALSE)
  tab <- tab[order(tab$poly_id), ]
  drops <- if (file.exists(drop_path))
    read.csv(drop_path, stringsAsFactors = FALSE) else data.frame()
  tab <- tab[order(tab$poly_id), ]

  # The guard that matters: no label may leave this block. lidar_year is a
  # design covariate and is named so it cannot be mistaken for one.
  stopifnot(length(grep("PEST|SPECIES|SEVERITY|AGENT|CAPTURE", names(tab),
                        ignore.case = TRUE)) == 0)
  write.csv(tab, struct_path, row.names = FALSE)
  # The partial file has served its purpose. Leaving it would let a
  # deliberate re-run resume instead of recomputing, which is not what
  # deleting the output asks for.
  if (file.exists(part_path)) invisible(file.remove(part_path))

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
              BUFFER_M, n_all, nrow(tab), nrow(drops),
              min(tab$dens_raw), median(tab$dens_raw), max(tab$dens_raw),
              median(tab$dens_used), as.character(Sys.Date())),
    stringsAsFactors = FALSE), struct_log, row.names = FALSE)
})


