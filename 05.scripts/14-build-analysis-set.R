# Build the analysis set: the polygons the study can actually use.
#
# Decision, Seamus 2026-08-14: the study proceeds as a structural study, located
# by data availability. Existing public lidar cannot support a moderate-and-above
# severity floor anywhere in British Columbia at any useful temporal tolerance
# (zero qualifying polygons at 1, 3, 5 and 10 year offsets; one at 20). The
# study therefore accepts a low-severity sample in exchange for the structural
# arm, and states that restriction rather than working around it.
#
# Inclusion, all four conditions:
#   1. damage agent is IAB or IBB
#   2. host is Pacific silver fir (BA), so host is held constant and the
#      comparison is attribution rather than host discrimination
#   3. the polygon falls within LidarBC point cloud coverage
#   4. the nearest lidar acquisition is within MAX_OFFSET years of the survey
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

path <- file.path(derived, "analysis-set.geojson")
if (file.exists(path)) file.remove(path)
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
cat("  class imbalance:        ",
    round(sum(aset$PEST_SPECIES_CODE == "IBB") /
          sum(aset$PEST_SPECIES_CODE == "IAB"), 1), "to 1\n")

bb <- st_bbox(st_transform(aset, 4326))
cat("  extent: ", sprintf("%.2f to %.2f W, %.2f to %.2f N\n",
                          -bb["xmin"], -bb["xmax"], bb["ymin"], bb["ymax"]))
cat("\nwrote", path, "\n")
