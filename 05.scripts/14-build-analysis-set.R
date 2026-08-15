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

# --- from chunk pipe-basemap, definitions this script depends on ---
bm_path <- file.path(derived, "basemap.gpkg")
hs_path <- file.path(derived, "hillshade.tif")

# Map frame, slightly wider than the analysis envelope so the island sits inside
# a margin rather than against the neatline. This is the view the figures show.
FRAME <- c(xmin = -129.2, ymin = 48.0, xmax = -122.3, ymax = 51.4)
# Data are clipped wider than the view. The figures plot at a fixed aspect ratio,
# which expands the shorter axis past the view rectangle; land cropped at the
# view would stop short of the neatline and leave a band of sea where the
# mainland belongs.
PAD <- 1.2
DATA_FRAME <- FRAME + c(-PAD, -PAD, PAD, PAD)


set_path <- file.path(derived, "analysis-set.geojson")
restr_path <- file.path(derived, "analysis-set-restriction.csv")

if (!file.exists(set_path) || !file.exists(restr_path)) local({
  MAX_OFFSET <- 5
  # A point in Strathcona Park, well inland, used to pick Vancouver Island out of
  # the land layer by containment rather than by area, so the selection cannot
  # silently attach to a different landmass.
  VI_SEED <- c(-125.60, 49.60)

  v <- sf::st_transform(sf::st_make_valid(sf::st_read(
    file.path(derived, "vi-fir-agents.geojson"), quiet = TRUE)), BC_ALBERS)
  tl <- sf::st_transform(sf::st_make_valid(sf::st_read(
    file.path(derived, "lidar-tiles.geojson"), quiet = TRUE)), BC_ALBERS)

  # 2. Host held constant, so the comparison is attribution rather than host
  # discrimination.
  v <- v[v$TREE_SPECIES_CODE %in% "BA", ]

  # 3 and 4. Lidar coverage, and an acquisition within MAX_OFFSET years.
  hit <- sf::st_intersects(v, tl)
  v$lidar_tiles <- lengths(hit)
  v$lidar_year <- vapply(seq_len(nrow(v)), function(k) {
    if (!v$lidar_tiles[k]) return(NA_integer_)
    ys <- tl$year[hit[[k]]]; ys <- ys[!is.na(ys)]
    if (!length(ys)) return(NA_integer_)
    ys[which.min(abs(ys - v$CAPTURE_YEAR[k]))]
  }, integer(1))
  v$year_offset <- abs(v$lidar_year - v$CAPTURE_YEAR)
  aset <- v[!is.na(v$year_offset) & v$year_offset <= MAX_OFFSET, ]

  # 5. Vancouver Island only. Off the island the record is 43 bark beetle to 5
  # adelgid and 38 of 48 polygons come from one 2020 acquisition, so landmass and
  # campaign each predict the agent almost perfectly. Blocking does not answer a
  # confound that holds within folds as well as across them, so region is
  # neutralised by restriction, the instrument already used for host.
  land_l <- sf::st_transform(sf::st_make_valid(
    sf::st_read(bm_path, "land", quiet = TRUE)), BC_ALBERS)
  seed <- sf::st_transform(sf::st_sfc(sf::st_point(VI_SEED), crs = 4326),
                           BC_ALBERS)
  island <- land_l[lengths(sf::st_intersects(land_l, seed)) > 0, ]
  stopifnot(nrow(island) == 1)
  on_island <- lengths(sf::st_intersects(
    sf::st_centroid(sf::st_geometry(aset)), island)) > 0

  # The counts that motivate the restriction are saved rather than quoted from a
  # terminal session, because the manuscript reports them.
  restriction <- as.data.frame(table(
    landmass = ifelse(on_island, "Vancouver Island", "Elsewhere"),
    agent = aset$PEST_SPECIES_CODE,
    lidar_year = aset$lidar_year), stringsAsFactors = FALSE)
  restriction <- restriction[restriction$Freq > 0, ]
  names(restriction)[names(restriction) == "Freq"] <- "n"
  write.csv(restriction, restr_path, row.names = FALSE)

  aset <- aset[on_island, ]
  if (file.exists(set_path)) invisible(file.remove(set_path))
  sf::st_write(sf::st_transform(aset, 4326), set_path, quiet = TRUE)
})


