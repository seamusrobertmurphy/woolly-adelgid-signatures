# Build the analysis set: the polygons the study can actually use.
#
# Decision, Seamus 2026-08-14: the study proceeds as a structural study, located
# by data availability. Existing public lidar cannot support a moderate-and-above
# severity floor anywhere in British Columbia at any useful temporal tolerance
# (zero qualifying polygons at 1, 3, 5 and 10 year offsets; one at 20). The
# study therefore accepts a low-severity sample in exchange for the structural
# arm, and states that restriction rather than working around it.
#
# Inclusion, all five conditions:
#   1. damage agent is IAB or IBB
#   2. host is Pacific silver fir (BA), so host is held constant and the
#      comparison is attribution rather than host discrimination
#   3. the polygon falls within LidarBC point cloud coverage
#   4. the nearest lidar acquisition is within MAX_OFFSET years of the survey
#   5. the polygon centroid lies on Vancouver Island
#
# Condition 5 added by Seamus on 2026-08-14. Without it the sample carried 39
# mainland polygons of which 37 were bark beetle, against 48 adelgid and 36 bark
# beetle on the island, so landmass predicted the agent 37 times in 39. Lidar
# acquisition was nearly collinear with it: 38 of the 39 mainland polygons came
# from the single 2020 campaign and 65 of the 84 island polygons from 2019, and
# every structural metric in the plan responds to which campaign flew it.
# Spatial blocking prevents leakage across folds but does not stop a model
# learning region in place of damage, so region is neutralised by restriction,
# the same instrument that neutralises host. Nine polygons on smaller islands
# are dropped with the mainland, since they add two further lidar campaigns.
#
# Outputs 02.inputs/derived/analysis-set.geojson and a summary the manuscript
# reads. Nothing downstream should filter these polygons again: this file is the
# sample, and its size is the study's sample size.
#
# Usage: Rscript 05.scripts/14-build-analysis-set.R

suppressMessages({
  library(sf)
})

root <- normalizePath(".")
derived <- file.path(root, "02.inputs", "derived")
BC_ALBERS <- 3005
MAX_OFFSET <- 5
# A point in Strathcona Park, well inland on Vancouver Island, used to pick the
# island out of the Natural Earth land layer by containment rather than by area,
# so the selection cannot silently attach to a different landmass.
VI_SEED <- c(-125.60, 49.60)

vi <- st_transform(st_make_valid(
  st_read(file.path(derived, "vi-fir-agents.geojson"), quiet = TRUE)), BC_ALBERS)
tiles <- st_transform(st_make_valid(
  st_read(file.path(derived, "lidar-tiles.geojson"), quiet = TRUE)), BC_ALBERS)

vi <- vi[vi$TREE_SPECIES_CODE %in% "BA", ]
message(nrow(vi), " polygons on Pacific silver fir before lidar screening")

hit <- st_intersects(vi, tiles)
vi$lidar_tiles <- lengths(hit)
vi$lidar_year <- vapply(seq_len(nrow(vi)), function(k) {
  if (!vi$lidar_tiles[k]) return(NA_integer_)
  ys <- tiles$year[hit[[k]]]
  ys <- ys[!is.na(ys)]
  if (!length(ys)) return(NA_integer_)
  ys[which.min(abs(ys - vi$CAPTURE_YEAR[k]))]
}, integer(1))
vi$year_offset <- abs(vi$lidar_year - vi$CAPTURE_YEAR)

keep <- !is.na(vi$year_offset) & vi$year_offset <= MAX_OFFSET
aset <- vi[keep, ]
message(nrow(aset), " polygons under lidar within ", MAX_OFFSET,
        " years, before the landmass restriction")

land <- st_transform(st_make_valid(
  st_read(file.path(derived, "basemap.gpkg"), "land", quiet = TRUE)), BC_ALBERS)
seed <- st_transform(st_sfc(st_point(VI_SEED), crs = 4326), BC_ALBERS)
island <- land[lengths(st_intersects(land, seed)) > 0, ]
stopifnot(nrow(island) == 1)

on_island <- lengths(st_intersects(st_centroid(st_geometry(aset)), island)) > 0
message(sum(!on_island), " polygons off Vancouver Island, dropped")

# The restriction is a design choice and the manuscript states why, so the counts
# that motivate it are saved rather than quoted from a terminal session.
restriction <- as.data.frame(table(
  landmass = ifelse(on_island, "Vancouver Island", "Elsewhere"),
  agent = aset$PEST_SPECIES_CODE,
  lidar_year = aset$lidar_year), stringsAsFactors = FALSE)
restriction <- restriction[restriction$Freq > 0, ]
names(restriction)[names(restriction) == "Freq"] <- "n"
write.csv(restriction, file.path(derived, "analysis-set-restriction.csv"),
          row.names = FALSE)

aset <- aset[on_island, ]

path <- file.path(derived, "analysis-set.geojson")
if (file.exists(path)) invisible(file.remove(path))
st_write(st_transform(aset, 4326), path, quiet = TRUE)

cat("\nANALYSIS SET\n")
cat("  polygons:              ", nrow(aset), "\n")
cat("  by agent:\n")
print(table(aset$PEST_SPECIES_CODE))
cat("  by severity:\n")
print(table(aset$PEST_SPECIES_CODE, aset$PEST_SEVERITY_CODE))
cat("  survey years:          ", paste(range(aset$CAPTURE_YEAR), collapse = "-"), "\n")
cat("  lidar years:           ",
    paste(sort(unique(aset$lidar_year)), collapse = ", "), "\n")
cat("  label-to-lidar offset: median ", median(aset$year_offset),
    ", max ", max(aset$year_offset), "\n", sep = "")
cat("  area (ha):             median ", round(median(aset$AREA_HA), 1),
    ", total ", round(sum(aset$AREA_HA)), "\n", sep = "")
n_iab <- sum(aset$PEST_SPECIES_CODE == "IAB")
n_ibb <- sum(aset$PEST_SPECIES_CODE == "IBB")
cat("  class imbalance:        ",
    round(max(n_iab, n_ibb) / min(n_iab, n_ibb), 1), " to 1 in favour of ",
    if (n_iab >= n_ibb) "adelgid\n" else "bark beetle\n", sep = "")

bb <- st_bbox(st_transform(aset, 4326))
cat("  extent: ", sprintf("%.2f to %.2f W, %.2f to %.2f N\n",
                          -bb["xmin"], -bb["xmax"], bb["ymin"], bb["ymax"]))
cat("\nwrote", path, "\n")
