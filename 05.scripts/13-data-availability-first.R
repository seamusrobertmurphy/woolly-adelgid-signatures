# Locate the study by data availability, not by preference.
#
# Per Seamus, 2026-08-14: data availability dictates where the study is located.
# Earlier scripts asked "here are the polygons, do they have lidar", which is the
# wrong order and produced a design that required flying lidar that does not
# exist. This script asks the question the other way round: where do all three
# requirements already coexist?
#
# The design needs both classes, not just the adelgid. A region with adelgid
# polygons under lidar but no bark beetle polygons under the same lidar cannot
# support a two-class attribution test at all.
#
# Requirements per candidate region:
#   1. adelgid polygons with lidar coverage
#   2. bark beetle polygons with lidar coverage, on the same host
#   3. label-to-acquisition offset small enough that structure matches the label
#
# Outputs 02.inputs/derived/availability-regions.csv, one row per candidate
# region ranked by what it can actually supply.
#
# Usage: Rscript 05.scripts/13-data-availability-first.R

suppressMessages({
  library(sf)
})

root <- normalizePath(".")
derived <- file.path(root, "02.inputs", "derived")
BC_ALBERS <- 3005
MAX_OFFSET <- 3          # years between survey and lidar acquisition
GRID <- 25000            # 25 km analysis cells

vi <- st_transform(st_make_valid(
  st_read(file.path(derived, "vi-fir-agents.geojson"), quiet = TRUE)), BC_ALBERS)
tiles <- st_transform(st_make_valid(
  st_read(file.path(derived, "lidar-tiles.geojson"), quiet = TRUE)), BC_ALBERS)

# Attach lidar to every survey polygon, both classes.
hit <- st_intersects(vi, tiles)
vi$lidar_tiles <- lengths(hit)
vi$nearest_year <- vapply(seq_len(nrow(vi)), function(k) {
  if (!vi$lidar_tiles[k]) return(NA_integer_)
  ys <- tiles$year[hit[[k]]]
  ys <- ys[!is.na(ys)]
  if (!length(ys)) return(NA_integer_)
  ys[which.min(abs(ys - vi$CAPTURE_YEAR[k]))]
}, integer(1))
vi$offset <- abs(vi$nearest_year - vi$CAPTURE_YEAR)

usable <- vi[!is.na(vi$offset) & vi$offset <= MAX_OFFSET, ]
message(nrow(usable), " polygons have lidar within ", MAX_OFFSET,
        " years of the survey")

# Grid the coast and count what each cell can supply.
cells <- st_make_grid(usable, cellsize = GRID)
cells <- st_sf(cell = seq_along(cells), geometry = cells)
ix <- st_intersects(cells, usable)

sev_rank <- c(T = 1, L = 2, M = 3, S = 4, V = 5)
rows <- lapply(seq_len(nrow(cells)), function(k) {
  sub <- usable[ix[[k]], ]
  if (!nrow(sub)) return(NULL)
  iab <- sub[sub$PEST_SPECIES_CODE == "IAB", ]
  ibb <- sub[sub$PEST_SPECIES_CODE == "IBB", ]
  # Shared host is what makes the comparison an attribution test.
  iab_ba <- iab[iab$TREE_SPECIES_CODE %in% "BA", ]
  ibb_ba <- ibb[ibb$TREE_SPECIES_CODE %in% "BA", ]
  ctr <- st_coordinates(st_centroid(st_transform(cells[k, ], 4326)))
  data.frame(
    cell = k,
    lon = round(ctr[1, 1], 3), lat = round(ctr[1, 2], 3),
    iab_n = nrow(iab), ibb_n = nrow(ibb),
    iab_ba = nrow(iab_ba), ibb_ba = nrow(ibb_ba),
    iab_best_sev = if (nrow(iab)) names(which.max(
      sev_rank[iab$PEST_SEVERITY_CODE])) else NA_character_,
    iab_mod_plus = sum(iab$PEST_SEVERITY_CODE %in% c("M", "S", "V")),
    iab_ha = round(sum(iab$AREA_HA)),
    yrs = paste(range(sub$CAPTURE_YEAR), collapse = "-"),
    med_offset = median(sub$offset)
  )
})
tab <- do.call(rbind, rows)

# A cell is only a candidate if it can supply both classes on the shared host.
tab$viable <- tab$iab_ba > 0 & tab$ibb_ba > 0
tab <- tab[order(-tab$viable, -(tab$iab_ba + tab$ibb_ba), -tab$iab_mod_plus), ]
write.csv(tab, file.path(derived, "availability-regions.csv"), row.names = FALSE)

cat("\ncells containing usable polygons:      ", nrow(tab), "\n")
cat("cells with BOTH classes on Pacific silver fir: ", sum(tab$viable), "\n\n")
v <- tab[tab$viable, ]
if (nrow(v)) {
  cat("VIABLE REGIONS, ranked by sample size\n")
  cat(sprintf("%8s %8s %6s %6s %6s %6s %10s %12s\n",
              "lon", "lat", "IAB", "IBB", "IAB_BA", "IBB_BA", "best_sev", "years"))
  for (i in seq_len(min(nrow(v), 12))) {
    cat(sprintf("%8.3f %8.3f %6d %6d %6d %6d %10s %12s\n",
                v$lon[i], v$lat[i], v$iab_n[i], v$ibb_n[i],
                v$iab_ba[i], v$ibb_ba[i], v$iab_best_sev[i], v$yrs[i]))
  }
}
cat("\nwrote", file.path(derived, "availability-regions.csv"), "\n")
