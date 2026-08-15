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

avail_path <- file.path(derived, "availability-regions.csv")
if (!file.exists(avail_path)) local({
  MAX_OFFSET <- 3          # years between survey and lidar acquisition
  GRID <- 25000            # 25 km analysis cells

  v <- sf::st_transform(sf::st_make_valid(sf::st_read(
    file.path(derived, "vi-fir-agents.geojson"), quiet = TRUE)), BC_ALBERS)
  tl <- sf::st_transform(sf::st_make_valid(sf::st_read(
    file.path(derived, "lidar-tiles.geojson"), quiet = TRUE)), BC_ALBERS)

  hit <- sf::st_intersects(v, tl)
  v$lidar_tiles <- lengths(hit)
  v$nearest_year <- vapply(seq_len(nrow(v)), function(k) {
    if (!v$lidar_tiles[k]) return(NA_integer_)
    ys <- tl$year[hit[[k]]]; ys <- ys[!is.na(ys)]
    if (!length(ys)) return(NA_integer_)
    ys[which.min(abs(ys - v$CAPTURE_YEAR[k]))]
  }, integer(1))
  v$offset <- abs(v$nearest_year - v$CAPTURE_YEAR)
  usable <- v[!is.na(v$offset) & v$offset <= MAX_OFFSET, ]

  cells <- sf::st_make_grid(usable, cellsize = GRID)
  cells <- sf::st_sf(cell = seq_along(cells), geometry = cells)
  ix <- sf::st_intersects(cells, usable)
  sev_rank <- c(T = 1, L = 2, M = 3, S = 4, V = 5)

  rows <- lapply(seq_len(nrow(cells)), function(k) {
    sub <- usable[ix[[k]], ]
    if (!nrow(sub)) return(NULL)
    a <- sub[sub$PEST_SPECIES_CODE == "IAB", ]
    b <- sub[sub$PEST_SPECIES_CODE == "IBB", ]
    ctr <- sf::st_coordinates(sf::st_centroid(sf::st_transform(cells[k, ], 4326)))
    data.frame(
      cell = k, lon = round(ctr[1, 1], 3), lat = round(ctr[1, 2], 3),
      iab_n = nrow(a), ibb_n = nrow(b),
      # Shared host is what makes the comparison an attribution test.
      iab_ba = sum(a$TREE_SPECIES_CODE %in% "BA"),
      ibb_ba = sum(b$TREE_SPECIES_CODE %in% "BA"),
      iab_best_sev = if (nrow(a)) names(which.max(
        sev_rank[a$PEST_SEVERITY_CODE])) else NA_character_,
      iab_mod_plus = sum(a$PEST_SEVERITY_CODE %in% c("M", "S", "V")),
      iab_ha = round(sum(a$AREA_HA)),
      yrs = paste(range(sub$CAPTURE_YEAR), collapse = "-"),
      med_offset = median(sub$offset))
  })
  tab <- do.call(rbind, rows)
  tab$viable <- tab$iab_ba > 0 & tab$ibb_ba > 0
  tab <- tab[order(-tab$viable, -(tab$iab_ba + tab$ibb_ba), -tab$iab_mod_plus), ]
  write.csv(tab, avail_path, row.names = FALSE)
})


