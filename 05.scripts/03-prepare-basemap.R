# Prepare basemap layers for the study area figure.
#
# Source:    Natural Earth, 1:10m physical and cultural vectors, via rnaturalearth.
# Licence:   Natural Earth is public domain. https://www.naturalearthdata.com/about/terms-of-use/
# Retrieved: 2026-08-13
#
# Downloads once, clips to the study envelope, reprojects to NAD83 / BC Albers
# (EPSG:3005) and writes small GeoPackage layers the manuscript reads at render
# time. Reprojecting here rather than in the manuscript means the scale bar is
# drawn in projected metres and is metrically correct.
#
# Usage: Rscript 05.scripts/03-prepare-basemap.R

suppressMessages({
  library(sf)
  library(rnaturalearth)
})

# Run from the repository root.
root <- normalizePath(".")
stopifnot(dir.exists(file.path(root, "02.inputs")))
out <- file.path(root, "02.inputs", "derived")
dir.create(out, showWarnings = FALSE, recursive = TRUE)

BC_ALBERS <- 3005
# Map frame, slightly wider than the analysis envelope so the island sits inside
# a margin rather than against the neatline.
FRAME <- c(xmin = -129.2, ymin = 48.0, xmax = -122.3, ymax = 51.4)

clip <- function(x) {
  x <- sf::st_make_valid(sf::st_transform(x, 4326))
  suppressWarnings(sf::st_crop(x, FRAME))
}

message("downloading Natural Earth layers")
land     <- ne_download(scale = 10, type = "land", category = "physical",
                        returnclass = "sf")
states   <- ne_states(country = c("Canada", "United States of America"),
                      returnclass = "sf")
# The global rivers_lake_centerlines layer resolves only one river inside this
# frame, which is useless for orientation on Vancouver Island. The North America
# supplement resolves 32 and is used instead.
rivers   <- ne_download(scale = 10, type = "rivers_north_america",
                        category = "physical", returnclass = "sf")
# Several lake polygons in the North America supplement carry self-intersecting
# rings. s2 rejects them outright, so validity is repaired in planar mode.
lakes <- tryCatch({
  old <- sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old), add = TRUE)
  ne_download(scale = 10, type = "lakes_north_america", category = "physical",
              returnclass = "sf")
}, error = function(e) {
  message("lakes unavailable: ", conditionMessage(e))
  NULL
})

layers <- list(
  land   = clip(land["featurecla"]),
  rivers = clip(rivers["name"])
)

# Administrative boundary. Drawing the full outline of each province or state
# would retrace the entire coastline in a second style, which is cartographically
# confusing at this extent, so only the shared land border is kept: the segment
# where the British Columbia polygon meets a United States polygon. That is the
# international boundary through the Strait of Juan de Fuca and along the 49th
# parallel, which is the only administrative line inside this frame.
bc <- states[states$name == "British Columbia", ]
us <- states[states$admin == "United States of America", ]
border <- tryCatch({
  old <- sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(old), add = TRUE)
  b <- sf::st_intersection(
    sf::st_boundary(sf::st_make_valid(sf::st_union(bc))),
    sf::st_buffer(sf::st_boundary(sf::st_make_valid(sf::st_union(us))), 0.02)
  )
  sf::st_sf(name = "International boundary", geometry = sf::st_geometry(b))
}, error = function(e) {
  message("border derivation failed: ", conditionMessage(e))
  NULL
})
if (!is.null(border)) layers$admin <- clip(border)
if (!is.null(lakes)) {
  old <- sf::sf_use_s2(FALSE)
  layers$lakes <- clip(lakes["name"])
  sf::sf_use_s2(old)
}

path <- file.path(out, "basemap.gpkg")
if (file.exists(path)) file.remove(path)
for (nm in names(layers)) {
  g <- sf::st_transform(layers[[nm]], BC_ALBERS)
  sf::st_write(g, path, layer = nm, quiet = TRUE, append = FALSE)
  message(sprintf("%-7s %4d features", nm, nrow(g)))
}

# Place labels that orient a reader unfamiliar with the coast. Coordinates are
# from the BC Geographical Names Office listings, entered by hand because the
# Natural Earth populated-places layer omits the smaller island communities.
places <- sf::st_as_sf(
  data.frame(
    name = c("Comox", "Campbell River", "Port Alberni", "Nanaimo",
             "Victoria", "Vancouver", "Tofino", "Port Hardy"),
    lon  = c(-124.928, -125.247, -124.805, -123.936,
             -123.365, -123.121, -125.906, -127.418),
    lat  = c(49.673, 50.024, 49.234, 49.166,
             48.428, 49.283, 49.153, 50.720)
  ),
  coords = c("lon", "lat"), crs = 4326
)
sf::st_write(sf::st_transform(places, BC_ALBERS), path, layer = "places",
             quiet = TRUE, append = FALSE)
message(sprintf("%-7s %4d features", "places", nrow(places)))
message("wrote ", path)

# Hillshade, so the reader sees the mountain spine of the island rather than a
# flat outline. Source: AWS Terrain Tiles via elevatr, which repackages SRTM and
# other public elevation products. Zoom 7 is about 1 km ground resolution, ample
# for a figure at this extent and small enough to commit.
suppressMessages(library(terra))
suppressMessages(library(elevatr))

frame_sf <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(FRAME, crs = 4326)))
dem <- elevatr::get_elev_raster(frame_sf, z = 7, clip = "bbox", verbose = FALSE)
dem <- terra::project(terra::rast(dem), paste0("EPSG:", BC_ALBERS))

# Mask to land. Terrain tiles return zero or small positive values over water
# rather than negative ones, so an elevation threshold does not separate sea from
# shore. Masking by the coastline polygon does, and it keeps the ocean a flat
# colour instead of a field of grey noise.
land_mask <- sf::st_transform(layers$land, BC_ALBERS)
dem <- terra::mask(dem, terra::vect(sf::st_geometry(land_mask)))

slope <- terra::terrain(dem, "slope", unit = "radians")
aspect <- terra::terrain(dem, "aspect", unit = "radians")
hs <- terra::shade(slope, aspect, angle = 40, direction = 315)

terra::writeRaster(hs, file.path(out, "hillshade.tif"), overwrite = TRUE,
                   gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2"))
message(sprintf("%-7s %d x %d cells", "hillshade",
                terra::nrow(hs), terra::ncol(hs)))
