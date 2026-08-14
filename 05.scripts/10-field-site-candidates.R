# Identify candidate field sites: adelgid polygons on Pacific silver fir that are
# covered by lidar and reachable from Comox.
#
# The site-planning question is not where the adelgid polygons are, nor where the
# lidar is, but where the two coincide, because a plot without lidar cannot serve
# the structural arm of the study. Acquisition year matters too: a polygon mapped
# in 2019 and flown in 2024 carries a five-year offset between label and structure.
#
# Inputs:  02.inputs/derived/vi-fir-agents.geojson   (survey polygons)
#          02.inputs/derived/lidar-tiles.geojson     (LidarBC point cloud index)
# Outputs: 02.inputs/derived/field-site-candidates.csv
#          02.inputs/derived/lidar-coverage-dissolved.gpkg  (for mapping)
#
# Usage: Rscript 05.scripts/10-field-site-candidates.R

suppressMessages({
  library(sf)
})

root <- normalizePath(".")
derived <- file.path(root, "02.inputs", "derived")
BC_ALBERS <- 3005

vi <- st_read(file.path(derived, "vi-fir-agents.geojson"), quiet = TRUE)
tiles <- st_read(file.path(derived, "lidar-tiles.geojson"), quiet = TRUE)

vi <- st_transform(st_make_valid(vi), BC_ALBERS)
tiles <- st_transform(st_make_valid(tiles), BC_ALBERS)

# Comox, the base for field access. Distances are straight line, not road, and
# are a first filter rather than a travel estimate.
comox <- st_transform(
  st_sfc(st_point(c(-124.928, 49.673)), crs = 4326), BC_ALBERS)

# The target class: adelgid on Pacific silver fir, the shared host.
target <- vi[vi$PEST_SPECIES_CODE == "IAB" & vi$TREE_SPECIES_CODE == "BA", ]
message(nrow(target), " adelgid polygons on Pacific silver fir")

# Which polygons have lidar, and from which acquisitions.
hit <- st_intersects(target, tiles)
target$lidar_tiles <- lengths(hit)
target$lidar_years <- vapply(hit, function(i) {
  if (!length(i)) return(NA_character_)
  paste(sort(unique(tiles$year[i])), collapse = ";")
}, character(1))
target$km_from_comox <- round(
  as.numeric(st_distance(st_centroid(target), comox)) / 1000, 1)

# Offset between the survey year and the nearest lidar acquisition, which bounds
# how well structure can be matched to label.
target$nearest_lidar_year <- vapply(seq_len(nrow(target)), function(k) {
  ys <- suppressWarnings(as.integer(strsplit(target$lidar_years[k], ";")[[1]]))
  if (!length(ys) || all(is.na(ys))) return(NA_integer_)
  ys[which.min(abs(ys - target$CAPTURE_YEAR[k]))]
}, integer(1))
target$year_offset <- abs(target$nearest_lidar_year - target$CAPTURE_YEAR)

cent <- st_coordinates(st_centroid(st_transform(target, 4326)))
out <- data.frame(
  capture_year = target$CAPTURE_YEAR,
  severity = target$PEST_SEVERITY_CODE,
  area_ha = round(target$AREA_HA, 1),
  lidar_tiles = target$lidar_tiles,
  lidar_years = target$lidar_years,
  nearest_lidar_year = target$nearest_lidar_year,
  year_offset = target$year_offset,
  km_from_comox = target$km_from_comox,
  lon = round(cent[, 1], 5),
  lat = round(cent[, 2], 5)
)
out <- out[order(out$km_from_comox), ]
write.csv(out, file.path(derived, "field-site-candidates.csv"), row.names = FALSE)

cat("\nlidar coverage of the target class\n")
cat("  polygons with lidar:      ", sum(out$lidar_tiles > 0), "of", nrow(out), "\n")
cat("  within 50 km of Comox:    ", sum(out$km_from_comox <= 50), "\n")
cat("  within 50 km and lidar:   ",
    sum(out$km_from_comox <= 50 & out$lidar_tiles > 0), "\n")
cat("  moderate or severe:       ", sum(out$severity %in% c("M", "S")), "\n")
cat("  moderate/severe + lidar:  ",
    sum(out$severity %in% c("M", "S") & out$lidar_tiles > 0), "\n")
cat("\n  label-to-lidar year offset (years), where both exist\n")
print(summary(out$year_offset))

# Dissolve tiles by acquisition year so the map draws a coverage envelope rather
# than 18,840 individual squares.
diss <- aggregate(tiles["year"], by = list(year = tiles$year),
                  FUN = function(x) x[1], do_union = TRUE)
path <- file.path(derived, "lidar-coverage-dissolved.gpkg")
if (file.exists(path)) file.remove(path)
st_write(diss[, "year"], path, layer = "lidar_year", quiet = TRUE)
cat("\nwrote", path, "\n")

# Settlements for field access planning on the island. The Natural Earth
# populated-places layer omits most of these, so coordinates are entered by hand
# from the BC Geographical Names Office listings. Road access to the west and
# north of the island runs through a small number of these communities, so they
# are the practical reference points for reaching a polygon.
access <- st_as_sf(
  data.frame(
    name = c("Comox", "Courtenay", "Cumberland", "Campbell River", "Sayward",
             "Woss", "Port McNeill", "Port Hardy", "Gold River", "Tahsis",
             "Zeballos", "Port Alberni", "Ucluelet", "Tofino", "Nanaimo",
             "Powell River"),
    lon = c(-124.928, -124.993, -125.031, -125.247, -125.958,
            -126.601, -127.083, -127.418, -126.052, -126.661,
            -126.849, -124.805, -125.546, -125.906, -123.936,
            -124.524),
    lat = c(49.673, 49.687, 49.618, 50.024, 50.379,
            50.211, 50.588, 50.720, 49.777, 49.918,
            49.977, 49.234, 48.941, 49.153, 49.166,
            49.835)
  ),
  coords = c("lon", "lat"), crs = 4326
)
st_write(st_transform(access, BC_ALBERS),
         file.path(derived, "field-access-places.gpkg"),
         layer = "places", quiet = TRUE, append = FALSE)
cat("wrote field-access-places.gpkg,", nrow(access), "settlements\n")
