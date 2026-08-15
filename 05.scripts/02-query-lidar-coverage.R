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

# --- from chunk pipe-tiles, definitions this script depends on ---
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

cov_path <- file.path(derived, "lidar-coverage.csv")
if (!file.exists(cov_path)) local({
  envelopes <- list("study area" = STUDY_ENV,
                    "Comox field window" = c(-125.3, 49.4, -124.5, 49.9))
  rows <- lapply(names(envelopes), function(nm) {
    env <- envelopes[[nm]]
    n <- jsonlite::fromJSON(lidar_url(PC_LAYER, env, returnCountOnly = "true"),
                            simplifyVector = FALSE)$count
    s <- jsonlite::fromJSON(
      lidar_url(PC_LAYER, env, outFields = "year,density,projection,classes",
                returnGeometry = "false", resultRecordCount = 1000),
      simplifyVector = FALSE)
    at <- lapply(s$features, `[[`, "attributes")
    pull <- function(k) sort(unique(unlist(lapply(at, function(a) a[[k]]))))
    data.frame(envelope = nm, tiles = n,
               attrs_from_full_index = n <= 1000,
               acquisition_years_sampled = paste(pull("year"), collapse = ";"),
               density_pts_m2 = paste(pull("density"), collapse = ";"),
               point_classes = paste(pull("classes"), collapse = ";"),
               stringsAsFactors = FALSE)
  })
  write.csv(do.call(rbind, rows), cov_path, row.names = FALSE)
})


