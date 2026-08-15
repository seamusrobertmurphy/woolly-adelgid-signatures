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

# Source:    LidarBC Open LiDAR Data Portal, ArcGIS FeatureServer
#            LiDAR_BC_S3_Public, layer 4, the point cloud index.
# Licence:   Open Government Licence - British Columbia.
# Custodian: GeoBC.
LIDAR_SERVICE <- paste0("https://services6.arcgis.com/ubm4tcTYICKBpist/ArcGIS/",
                        "rest/services/LiDAR_BC_S3_Public/FeatureServer")
PC_LAYER <- 4L
STUDY_ENV <- c(-128.5, 48.3, -123.0, 51.0)
PAGE <- 1000L

# One URL builder for every query this manuscript makes against the service.
lidar_url <- function(layer, env, ...) {
  gj <- sprintf(paste0('{"xmin":%f,"ymin":%f,"xmax":%f,"ymax":%f,',
                       '"spatialReference":{"wkid":4326}}'),
                env[1], env[2], env[3], env[4])
  p <- c(list(where = "1=1", geometry = gj,
              geometryType = "esriGeometryEnvelope", inSR = "4326",
              spatialRel = "esriSpatialRelIntersects", f = "json"), list(...))
  paste0(LIDAR_SERVICE, "/", layer, "/query?",
         paste(names(p), vapply(p, function(v)
           URLencode(as.character(v), reserved = TRUE), ""),
           sep = "=", collapse = "&"))
}

tiles_path <- file.path(derived, "lidar-tiles.geojson")
if (!file.exists(tiles_path)) local({
  acc <- list(); off <- 0L
  repeat {
    u <- lidar_url(PC_LAYER, STUDY_ENV, outFields = "year,density,maptile",
                   returnGeometry = "true", outSR = "4326", f = "geojson",
                   resultOffset = off, resultRecordCount = PAGE)
    ch <- try(sf::st_read(u, quiet = TRUE), silent = TRUE)
    if (inherits(ch, "try-error") || nrow(ch) == 0L) break
    acc[[length(acc) + 1L]] <- ch
    if (nrow(ch) < PAGE) break
    off <- off + PAGE
  }
  sf::st_write(do.call(rbind, acc), tiles_path, quiet = TRUE)
})


