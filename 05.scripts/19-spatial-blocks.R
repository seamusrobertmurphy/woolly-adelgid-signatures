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


# --- from chunk pipe-lidar-metrics, definitions this script depends on ---
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
DENS_FLOOR   <- 4     # points per m2, below which the canopy model cell
                      # rule fails: at 4 only 1.8 percent of 1 m cells are
                      # empty from pulse spacing alone, at 2 it is 13.5
UNDER_TOP    <- 5     # m, top of the understorey stratum
MID_TOP      <- 15    # m, top of the midstorey stratum, spanning the 11 to 12 m
                      # band in which @Boucher_2020 located the adelgid signal
# The book interpolates terrain at 0.5 m on a 1 ha clip. These polygons run to
# 353 ha, where 0.5 m is 14 million cells and inverse distance weighting takes
# a quarter of an hour for one polygon. The interpolator is kept and the
# resolution matched to the 1 m canopy model, which discards finer terrain
# detail anyway.
DTM_RES_FINE <- 1.0   # m, terrain resolution


blocks_path <- file.path(derived, "spatial-blocks.csv")
N_FOLDS <- 5L
N_BLOCKS <- 10L      # two blocks per fold at least, per the pre-registration
ADJ_M <- 50          # polygons within this distance share a block
SEED <- 20260815L

if (!file.exists(blocks_path)) local({
  a <- sf::st_read(file.path(derived, "analysis-set.geojson"), quiet = TRUE)
  poly_id <- sprintf("P%03d", seq_len(nrow(a)))
  eroded <- sf::st_buffer(sf::st_transform(sf::st_geometry(a), BC_ALBERS),
                          -BUFFER_M)
  rm(a)

  # The sample the models will see: polygons with structural metrics at or above
  # the density floor. Blocking is built on exactly those units so that fold
  # sizes are the ones actually used.
  st <- read.csv(struct_path, stringsAsFactors = FALSE)
  keep_id <- st$poly_id[st$dens_used >= DENS_FLOOR]
  k <- match(keep_id, poly_id)
  eroded <- eroded[k]

  # Forced groups first: connected components of the within-50 m graph.
  nb <- sf::st_is_within_distance(eroded, eroded, dist = ADJ_M)
  grp <- seq_along(nb)
  repeat {
    changed <- FALSE
    for (i in seq_along(nb)) {
      g <- min(grp[nb[[i]]])
      if (any(grp[nb[[i]]] != g)) { grp[nb[[i]]] <- g; changed <- TRUE }
    }
    if (!changed) break
  }
  grp <- as.integer(factor(grp))

  ctr <- sf::st_coordinates(sf::st_centroid(eroded))
  # One representative point per forced group, so clustering cannot split a
  # group that must stay together.
  gc_x <- tapply(ctr[, 1], grp, mean); gc_y <- tapply(ctr[, 2], grp, mean)
  gpts <- cbind(as.numeric(gc_x), as.numeric(gc_y))

  set.seed(SEED)
  nb_use <- min(N_BLOCKS, nrow(gpts))
  pam_fit <- cluster::pam(gpts, k = nb_use)
  block_of_group <- pam_fit$clustering
  block <- block_of_group[grp]

  # Whole blocks to folds, largest first into the emptiest fold, so folds are
  # balanced on size and on nothing else. The label is not consulted.
  sizes <- sort(table(block), decreasing = TRUE)
  fold_of_block <- integer(0)
  load <- rep(0L, N_FOLDS)
  for (b in names(sizes)) {
    f <- which.min(load)
    fold_of_block[b] <- f
    load[f] <- load[f] + as.integer(sizes[[b]])
  }
  fold <- as.integer(fold_of_block[as.character(block)])

  out <- data.frame(poly_id = keep_id, block = as.integer(block), fold = fold,
                    forced_group = grp,
                    x = ctr[, 1], y = ctr[, 2], stringsAsFactors = FALSE)
  write.csv(out, blocks_path, row.names = FALSE)
})


