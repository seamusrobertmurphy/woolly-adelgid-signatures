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

if (!file.exists(bm_path) || !file.exists(hs_path)) local({
  library(rnaturalearth)
  library(elevatr)

  clip <- function(x) {
    x <- sf::st_make_valid(sf::st_transform(x, 4326))
    suppressWarnings(sf::st_crop(x, DATA_FRAME))
  }

  land <- ne_download(scale = 10, type = "land", category = "physical",
                      returnclass = "sf")
  states <- ne_states(country = c("Canada", "United States of America"),
                      returnclass = "sf")
  # The global rivers layer resolves only one river inside this frame, which is
  # useless for orientation. The North America supplement resolves 32.
  rivers <- ne_download(scale = 10, type = "rivers_north_america",
                        category = "physical", returnclass = "sf")
  # Several lake polygons carry self-intersecting rings. s2 rejects them
  # outright, so validity is repaired in planar mode.
  lakes <- tryCatch({
    old <- sf::sf_use_s2(FALSE); on.exit(sf::sf_use_s2(old), add = TRUE)
    ne_download(scale = 10, type = "lakes_north_america",
                category = "physical", returnclass = "sf")
  }, error = function(e) NULL)

  layers <- list(
    land = clip(land["featurecla"]),
    rivers = clip(rivers["name"]),
    # The view rectangle, saved so the figures set their limits from it rather
    # than from the bounding box of the land, which is deliberately wider.
    frame = sf::st_sf(name = "Map frame",
                      geometry = sf::st_as_sfc(sf::st_bbox(FRAME, crs = 4326))))

  # Only the shared land border is kept. Drawing the full provincial outline
  # would retrace the coastline in a second style, which is confusing at this
  # extent; the international boundary is the only administrative line inside
  # this frame.
  bc <- states[states$name == "British Columbia", ]
  us <- states[states$admin == "United States of America", ]
  border <- tryCatch({
    old <- sf::sf_use_s2(FALSE); on.exit(sf::sf_use_s2(old), add = TRUE)
    b <- sf::st_intersection(
      sf::st_boundary(sf::st_make_valid(sf::st_union(bc))),
      sf::st_buffer(sf::st_boundary(sf::st_make_valid(sf::st_union(us))), 0.02))
    sf::st_sf(name = "International boundary", geometry = sf::st_geometry(b))
  }, error = function(e) NULL)
  if (!is.null(border)) layers$admin <- clip(border)
  if (!is.null(lakes)) {
    old <- sf::sf_use_s2(FALSE); layers$lakes <- clip(lakes["name"])
    sf::sf_use_s2(old)
  }

  if (file.exists(bm_path)) file.remove(bm_path)
  for (nm in names(layers))
    sf::st_write(sf::st_transform(layers[[nm]], BC_ALBERS), bm_path,
                 layer = nm, quiet = TRUE, append = FALSE)

  # Place labels that orient a reader unfamiliar with the coast. Coordinates are
  # from the BC Geographical Names Office listings, entered by hand because the
  # Natural Earth populated-places layer omits the smaller island communities.
  places <- sf::st_as_sf(data.frame(
    name = c("Comox", "Campbell River", "Port Alberni", "Nanaimo",
             "Victoria", "Vancouver", "Tofino", "Port Hardy"),
    lon = c(-124.928, -125.247, -124.805, -123.936,
            -123.365, -123.121, -125.906, -127.418),
    lat = c(49.673, 50.024, 49.234, 49.166,
            48.428, 49.283, 49.153, 50.720)),
    coords = c("lon", "lat"), crs = 4326)
  sf::st_write(sf::st_transform(places, BC_ALBERS), bm_path, layer = "places",
               quiet = TRUE, append = FALSE)

  # Hillshade, so the reader sees the mountain spine rather than a flat outline.
  # AWS Terrain Tiles via elevatr. Zoom 7 is about 1 km ground resolution, ample
  # at this extent and small enough to commit.
  frame_sf <- sf::st_as_sf(sf::st_as_sfc(sf::st_bbox(DATA_FRAME, crs = 4326)))
  dem <- elevatr::get_elev_raster(frame_sf, z = 7, clip = "bbox",
                                  verbose = FALSE)
  dem <- terra::project(terra::rast(dem), paste0("EPSG:", BC_ALBERS))
  # Terrain tiles return zero or small positive values over water rather than
  # negative ones, so an elevation threshold does not separate sea from shore.
  # Masking by the coastline polygon does.
  dem <- terra::mask(dem, terra::vect(sf::st_geometry(
    sf::st_transform(layers$land, BC_ALBERS))))
  hs <- terra::shade(terra::terrain(dem, "slope", unit = "radians"),
                     terra::terrain(dem, "aspect", unit = "radians"),
                     angle = 40, direction = 315)
  terra::writeRaster(hs, hs_path, overwrite = TRUE,
                     gdal = c("COMPRESS=DEFLATE", "PREDICTOR=2"))
})


