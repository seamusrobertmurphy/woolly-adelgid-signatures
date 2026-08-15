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
# Caller arguments replace the defaults rather than being appended to them: the
# service answers a repeated parameter with HTTP 400, so a caller asking for
# f = "geojson" must overwrite f = "json" and not sit beside it.
lidar_url <- function(layer, env, ...) {
  gj <- sprintf(paste0('{"xmin":%f,"ymin":%f,"xmax":%f,"ymax":%f,',
                       '"spatialReference":{"wkid":4326}}'),
                env[1], env[2], env[3], env[4])
  p <- list(where = "1=1", geometry = gj,
            geometryType = "esriGeometryEnvelope", inSR = "4326",
            spatialRel = "esriSpatialRelIntersects", f = "json")
  extra <- list(...)
  p[names(extra)] <- extra
  paste0(LIDAR_SERVICE, "/", layer, "/query?",
         paste(names(p), vapply(p, function(v)
           URLencode(as.character(v), reserved = TRUE), ""),
           sep = "=", collapse = "&"))
}

tiles_path <- file.path(derived, "lidar-tiles.geojson")

cand_path <- file.path(derived, "site-candidates-province.csv")
if (!file.exists(cand_path)) local({
  sev <- c(T = "Trace", L = "Light", M = "Moderate", S = "Severe",
           V = "Very severe")
  host <- c(B = "True fir unspecified", BA = "Pacific silver fir",
            BG = "Grand fir", BL = "Subalpine fir")

  tiles_over <- function(bb) {
    n <- jsonlite::fromJSON(lidar_url(PC_LAYER, bb, returnCountOnly = "true"),
                            simplifyVector = FALSE)$count
    if (!length(n) || n == 0) return(list(n = 0L, years = integer(0)))
    d <- jsonlite::fromJSON(
      lidar_url(PC_LAYER, bb, outFields = "year", returnGeometry = "false",
                resultRecordCount = 1000), simplifyVector = FALSE)
    list(n = n, years = sort(unique(unlist(
      lapply(d$features, function(f) f$attributes$year)))))
  }

  src <- sf::st_read(file.path(derived, "adelgid-iab-polygons.geojson"),
                     quiet = TRUE)
  rows <- lapply(seq_len(nrow(src)), function(i) {
    bb <- as.numeric(sf::st_bbox(sf::st_geometry(src)[i]))
    tv <- tiles_over(bb)
    yr <- src$CAPTURE_YEAR[i]
    near <- if (length(tv$years) && !is.na(yr))
      tv$years[which.min(abs(tv$years - yr))] else NA_integer_
    Sys.sleep(0.25)
    data.frame(
      capture_year = yr,
      severity = unname(sev[src$PEST_SEVERITY_CODE[i]]),
      severity_code = src$PEST_SEVERITY_CODE[i],
      host = unname(host[src$TREE_SPECIES_CODE[i]]),
      host_code = ifelse(is.na(src$TREE_SPECIES_CODE[i]), "",
                         src$TREE_SPECIES_CODE[i]),
      area_ha = round(src$AREA_HA[i], 1),
      lidar_tiles = tv$n,
      lidar_years = paste(tv$years, collapse = ";"),
      nearest_lidar_year = if (is.na(near)) "" else near,
      year_offset = if (is.na(near)) "" else abs(near - yr),
      lon = round(mean(bb[c(1, 3)]), 5), lat = round(mean(bb[c(2, 4)]), 5),
      on_vancouver_island = bb[3] < -123.2 && bb[4] < 51.2,
      stringsAsFactors = FALSE)
  })
  out <- do.call(rbind, rows)
  out <- out[order(-out$lidar_tiles, out$severity_code), ]
  write.csv(out, cand_path, row.names = FALSE)
})


