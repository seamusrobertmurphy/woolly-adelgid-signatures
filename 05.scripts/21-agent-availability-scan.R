# Scope the two successor studies by data availability, not by preference.
#
# The parent study was located by asking where lidar, the survey record and a
# shared host coincide, and it ended with a null obtained on trace and light
# damage because that is the only severity public lidar reaches. The two
# successor designs need moderate or worse damage, so this script asks the same
# question again for every damage agent in the province rather than for one.
#
# Sources, each read live rather than from a cached extract:
#   Pest infestation polygons, DataBC WFS layer
#     WHSE_FOREST_VEGETATION.PEST_INFEST_CURRENT_POLY. Open Government Licence -
#     British Columbia. This layer carries the CURRENT survey year only, which
#     is 2025 as at 2026-08-16, so the multi-year record still requires the
#     908 MB archive from the BC Data Catalogue.
#   LidarBC point cloud index, ArcGIS FeatureServer, layer 4. OGL-BC.
#
# Writes:
#   03.outputs/tables/agent-availability.csv   one row per agent
#   02.inputs/derived/moderate-plus-2025.geojson  the polygons themselves
#
# Usage: Rscript 05.scripts/21-agent-availability-scan.R

suppressMessages({
  library(sf)
  library(jsonlite)
})

root <- normalizePath(".")
derived <- file.path(root, "02.inputs", "derived")
tables <- file.path(root, "03.outputs", "tables")
dir.create(tables, showWarnings = FALSE, recursive = TRUE)

WFS <- paste0("https://openmaps.gov.bc.ca/geo/pub/",
              "WHSE_FOREST_VEGETATION.PEST_INFEST_CURRENT_POLY/ows")
TYPE <- "pub:WHSE_FOREST_VEGETATION.PEST_INFEST_CURRENT_POLY"
LIDAR <- paste0("https://services6.arcgis.com/ubm4tcTYICKBpist/ArcGIS/rest/",
                "services/LiDAR_BC_S3_Public/FeatureServer/4/query")
BC_ALBERS <- 3005
PAGE <- 1000L
SEV_HIGH <- c("M", "S", "V")

out_poly <- file.path(derived, "moderate-plus-2025.geojson")

# ------------------------------------------------- moderate or worse polygons

if (!file.exists(out_poly)) {
  message("paging the survey layer for moderate or worse damage")
  acc <- list(); start <- 0L
  repeat {
    u <- paste0(WFS, "?service=WFS&version=2.0.0&request=GetFeature",
                "&typeName=", utils::URLencode(TYPE, reserved = TRUE),
                "&outputFormat=application/json",
                "&CQL_FILTER=",
                utils::URLencode("PEST_SEVERITY_CODE IN ('M','S','V')",
                                 reserved = TRUE),
                "&count=", PAGE, "&startIndex=", start)
    ch <- try(sf::st_read(u, quiet = TRUE), silent = TRUE)
    if (inherits(ch, "try-error") || nrow(ch) == 0L) break
    acc[[length(acc) + 1L]] <- ch
    message("  ", start + nrow(ch))
    if (nrow(ch) < PAGE) break
    start <- start + PAGE
  }
  pol <- do.call(rbind, acc)
  sf::st_write(pol, out_poly, quiet = TRUE)
} else {
  pol <- sf::st_read(out_poly, quiet = TRUE)
}
message(nrow(pol), " moderate or worse polygons, survey year ",
        paste(sort(unique(pol$CAPTURE_YEAR)), collapse = ", "))

# ------------------------------------------------------------- lidar coverage
# The index is a footprint layer and overstates coverage, which the parent study
# established the hard way. It is used here to rank candidates, and any design
# that follows must confirm coverage against the point clouds themselves.

lidar_url <- function(env, ...) {
  gj <- sprintf(paste0('{"xmin":%f,"ymin":%f,"xmax":%f,"ymax":%f,',
                       '"spatialReference":{"wkid":4326}}'),
                env[1], env[2], env[3], env[4])
  p <- list(where = "1=1", geometry = gj,
            geometryType = "esriGeometryEnvelope", inSR = "4326",
            spatialRel = "esriSpatialRelIntersects", f = "json")
  extra <- list(...); p[names(extra)] <- extra
  paste0(LIDAR, "?", paste(names(p), vapply(p, function(v)
    utils::URLencode(as.character(v), reserved = TRUE), ""),
    sep = "=", collapse = "&"))
}

# Coverage is asked per polygon rather than by paging the whole index. There
# are 159,607 tiles in the province and only the ones under a damage polygon
# matter, so one bounded query per polygon is far cheaper than fetching them all
# and intersecting locally.
cov_path <- file.path(derived, "moderate-plus-lidar.csv")
if (!file.exists(cov_path)) {
  message("querying lidar coverage for ", nrow(pol), " polygons")
  # The envelope is declared to the service as EPSG:4326, so the geometry must
  # be in 4326 before its bounding box is taken. The WFS delivers BC Albers, and
  # passing Albers metres as degrees returns zero matches for every polygon
  # without erroring, which is how this ran to completion and reported nothing.
  pol4326 <- sf::st_transform(pol, 4326)
  bb <- lapply(seq_len(nrow(pol4326)), function(i)
    as.numeric(sf::st_bbox(sf::st_geometry(pol4326)[i])))
  res <- vector("list", nrow(pol))
  for (i in seq_along(bb)) {
    u <- lidar_url(bb[[i]], outFields = "year", returnGeometry = "false",
                   resultRecordCount = 1000)
    d <- try(jsonlite::fromJSON(u, simplifyVector = FALSE), silent = TRUE)
    ys <- integer(0); n <- 0L
    if (!inherits(d, "try-error") && length(d$features)) {
      ys <- sort(unique(unlist(lapply(d$features, function(f) f$attributes$year))))
      n <- length(d$features)
    }
    res[[i]] <- data.frame(idx = i, lidar_tiles = n,
                           lidar_years = paste(ys, collapse = ";"),
                           lidar_year_max = if (length(ys)) max(ys) else NA_integer_,
                           stringsAsFactors = FALSE)
    if (i %% 250 == 0) { message("  ", i, " of ", nrow(pol)); flush.console() }
    Sys.sleep(0.05)
  }
  write.csv(do.call(rbind, res), cov_path, row.names = FALSE)
}
cov <- read.csv(cov_path, stringsAsFactors = FALSE)
message(sum(cov$lidar_tiles > 0), " of ", nrow(cov),
        " moderate-or-worse polygons intersect the lidar index")

# ------------------------------------------------------------ the inventory

pol_a <- sf::st_transform(sf::st_make_valid(pol), BC_ALBERS)
pol_a$lidar_tiles <- cov$lidar_tiles[match(seq_len(nrow(pol_a)), cov$idx)]
pol_a$lidar_years <- cov$lidar_years[match(seq_len(nrow(pol_a)), cov$idx)]
pol_a$lidar_year <- cov$lidar_year_max[match(seq_len(nrow(pol_a)), cov$idx)]

# Vancouver Island against the rest, since the parent study found landmass and
# lidar campaign nearly collinear with agent and neutralised it by restriction.
vi_box <- sf::st_as_sfc(sf::st_bbox(c(xmin = -128.7, ymin = 48.3,
                                      xmax = -123.2, ymax = 51.0),
                                    crs = 4326))
on_vi <- lengths(sf::st_intersects(
  sf::st_centroid(pol_a), sf::st_transform(vi_box, BC_ALBERS))) > 0
pol_a$region <- ifelse(on_vi, "Vancouver Island", "Mainland and other")

agg <- do.call(rbind, lapply(split(seq_len(nrow(pol_a)), pol_a$PEST_SPECIES_CODE),
  function(k) {
    d <- pol_a[k, ]
    data.frame(
      code = d$PEST_SPECIES_CODE[1],
      agent = d$PEST_SPECIES_COMMON_NAME[1],
      latin = d$PEST_SPECIES_LATIN_NAME[1],
      polygons = nrow(d),
      area_ha = round(sum(d$AREA_HA, na.rm = TRUE)),
      severe_plus = sum(d$PEST_SEVERITY_CODE %in% c("S", "V")),
      with_lidar = sum(d$lidar_tiles > 0),
      with_lidar_vi = sum(d$lidar_tiles > 0 & d$region == "Vancouver Island"),
      hosts = paste(sort(unique(stats::na.omit(d$TREE_SPECIES_CODE)))[1:3],
                    collapse = " "),
      stringsAsFactors = FALSE)
  }))
agg <- agg[order(-agg$with_lidar, -agg$polygons), ]
write.csv(agg, file.path(tables, "agent-availability.csv"), row.names = FALSE)
sf::st_write(sf::st_transform(pol_a, 4326), out_poly, delete_dsn = TRUE,
             quiet = TRUE)

cat("\nAGENT AVAILABILITY, moderate or worse damage, survey year ",
    paste(sort(unique(pol$CAPTURE_YEAR)), collapse = ", "), "\n", sep = "")
cat("  agents present:            ", nrow(agg), "\n")
cat("  polygons:                  ", sum(agg$polygons), "\n")
cat("  with any lidar coverage:   ", sum(agg$with_lidar), "\n")
cat("  on Vancouver Island:       ", sum(agg$with_lidar_vi), "\n\n")
print(utils::head(agg[, c("code", "agent", "polygons", "severe_plus",
                          "with_lidar", "with_lidar_vi", "hosts")], 15),
      row.names = FALSE)
cat("\nwrote ", file.path(tables, "agent-availability.csv"), "\n", sep = "")
