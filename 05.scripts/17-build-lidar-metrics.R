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

tile_map_path <- file.path(derived, "lidar-tile-map.csv")
tile_need_path <- file.path(derived, "lidar-tiles-needed.csv")
lidar_dir <- file.path(inputs, "lidar")
FETCH_JOBS <- 4L

if (!file.exists(tile_need_path)) local({
  a <- sf::st_read(file.path(derived, "analysis-set.geojson"), quiet = TRUE)
  n_all <- nrow(a)
  keep <- data.frame(poly_id = sprintf("P%03d", seq_len(n_all)),
                     lidar_year = a$lidar_year, stringsAsFactors = FALSE)
  g4 <- sf::st_transform(sf::st_geometry(a), 4326)
  bb <- as.numeric(sf::st_bbox(g4))

  acc <- list(); off <- 0L
  repeat {
    u <- lidar_url(PC_LAYER, bb,
                   outFields = "maptile,year,density,filename,s3Url,projection",
                   returnGeometry = "true", outSR = "4326", f = "geojson",
                   resultOffset = off, resultRecordCount = PAGE)
    ch <- try(sf::st_read(u, quiet = TRUE), silent = TRUE)
    if (inherits(ch, "try-error") || nrow(ch) == 0L) break
    acc[[length(acc) + 1L]] <- ch
    if (nrow(ch) < PAGE) break
    off <- off + PAGE
  }
  idx <- do.call(rbind, acc)

  hits <- sf::st_intersects(sf::st_sf(geometry = g4), idx)
  rows <- lapply(seq_len(n_all), function(i) {
    k <- hits[[i]]
    k <- k[idx$year[k] == keep$lidar_year[i]]
    if (!length(k)) return(NULL)
    data.frame(poly_id = keep$poly_id[i], maptile = idx$maptile[k],
               year = idx$year[k], density = idx$density[k],
               projection = idx$projection[k], filename = idx$filename[k],
               s3Url = idx$s3Url[k], stringsAsFactors = FALSE)
  })
  if (!all(vapply(rows, Negate(is.null), TRUE)))
    stop("no matching-year tile for some polygons")

  # A polygon spanning a tile boundary must have its clouds merged before any
  # metric is computed, so the polygon-to-tile map is kept, not just the tiles.
  map <- do.call(rbind, rows)
  tiles <- unique(map[, c("maptile", "year", "density", "projection",
                          "filename", "s3Url")])
  tiles$path <- file.path(lidar_dir, tiles$year, tiles$filename)

  remote_size <- function(url) {
    h <- try(system2("curl", c("-sIL", "--max-time", "60", shQuote(url)),
                     stdout = TRUE, stderr = FALSE), silent = TRUE)
    if (inherits(h, "try-error")) return(NA_real_)
    l <- grep("^[Cc]ontent-[Ll]ength:", h, value = TRUE)
    if (!length(l)) return(NA_real_)
    as.numeric(sub("^[^:]*:\\s*", "", tail(l, 1)))
  }
  tiles$bytes <- vapply(tiles$s3Url, remote_size, numeric(1))
  stopifnot(!anyNA(tiles$bytes))

  have <- file.exists(tiles$path)
  local_sz <- ifelse(have, file.size(tiles$path), NA_real_)
  todo <- which(!(have & !is.na(local_sz) & local_sz == tiles$bytes))

  if (length(todo)) {
    for (y in unique(tiles$year))
      dir.create(file.path(lidar_dir, y), recursive = TRUE,
                 showWarnings = FALSE)
    # curl resumes with -C -, so an interrupted run costs only the partial file.
    # Parallelism is capped because the link saturates near four streams and the
    # object store is a shared public resource.
    ch <- split(todo, ceiling(seq_along(todo) / FETCH_JOBS))
    for (k in ch) {
      system(paste(c(sprintf(
        "curl -sSL -C - --retry 5 --retry-delay 5 -o %s %s &",
        shQuote(tiles$path[k]), shQuote(tiles$s3Url[k])), "wait"),
        collapse = "\n"))
    }
  }

  fsz <- ifelse(file.exists(tiles$path), file.size(tiles$path), NA_real_)
  bad <- which(is.na(fsz) | fsz != tiles$bytes)
  if (length(bad)) stop(length(bad), " tiles incomplete, rerun to resume")

  write.csv(map, tile_map_path, row.names = FALSE)
  write.csv(tiles[, c("maptile", "year", "density", "projection", "filename",
                      "bytes")], tile_need_path, row.names = FALSE)
})


