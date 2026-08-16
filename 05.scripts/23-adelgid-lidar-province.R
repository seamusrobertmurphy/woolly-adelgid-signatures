# Every balsam woolly adelgid polygon in the province against lidar coverage,
# with no temporal filter and no host or landmass restriction.
#
# The parent study restricted to Vancouver Island, to Pacific silver fir and to
# a five year label-to-acquisition offset, and those restrictions hid the fact
# that moderate and severe adelgid polygons do fall under lidar elsewhere. This
# script asks the unrestricted question so the answer is on the record.
#
# Coverage is asked of the tile index, which is a footprint layer and overstates
# what the point clouds hold: the parent study found 12 of 84 polygons the index
# claimed carried no returns at all. Anything selected from this table must be
# confirmed against the clouds before it is treated as data in hand.
#
# Writes:
#   03.outputs/tables/adelgid-lidar-province.csv
#   03.outputs/figures/fig-adelgid-province-1.png
#
# Usage: Rscript 05.scripts/23-adelgid-lidar-province.R

suppressMessages({
  library(sf)
  library(jsonlite)
  library(rnaturalearth)
})

root <- normalizePath(".")
derived <- file.path(root, "02.inputs", "derived")
tables <- file.path(root, "03.outputs", "tables")
figs <- file.path(root, "03.outputs", "figures")
dir.create(tables, showWarnings = FALSE, recursive = TRUE)
BC_ALBERS <- 3005
LIDAR <- paste0("https://services6.arcgis.com/ubm4tcTYICKBpist/ArcGIS/rest/",
                "services/LiDAR_BC_S3_Public/FeatureServer/4/query")

iab <- sf::st_read(file.path(derived, "adelgid-iab-polygons.geojson"),
                   quiet = TRUE)
# The extract is already in geographic coordinates, which is what the service
# envelope declares. Confirm rather than assume: an envelope built from
# projected metres and declared as degrees returns nothing without erroring.
stopifnot(sf::st_is_longlat(iab))

out_csv <- file.path(tables, "adelgid-lidar-province.csv")
if (!file.exists(out_csv)) {
  q <- function(bb) {
    gj <- sprintf(paste0('{"xmin":%f,"ymin":%f,"xmax":%f,"ymax":%f,',
                         '"spatialReference":{"wkid":4326}}'),
                  bb[1], bb[2], bb[3], bb[4])
    u <- paste0(LIDAR, "?where=1%3D1&geometry=", utils::URLencode(gj, reserved = TRUE),
                "&geometryType=esriGeometryEnvelope&inSR=4326",
                "&spatialRel=esriSpatialRelIntersects&outFields=year",
                "&returnGeometry=false&f=json&resultRecordCount=1000")
    d <- try(jsonlite::fromJSON(u, simplifyVector = FALSE), silent = TRUE)
    if (inherits(d, "try-error") || !length(d$features)) return(integer(0))
    sort(unique(unlist(lapply(d$features, function(f) f$attributes$year))))
  }
  ctr <- sf::st_coordinates(sf::st_centroid(sf::st_geometry(iab)))
  rows <- lapply(seq_len(nrow(iab)), function(k) {
    ys <- q(as.numeric(sf::st_bbox(sf::st_geometry(iab)[k])))
    data.frame(
      idx = k,
      capture_year = iab$CAPTURE_YEAR[k],
      severity = iab$PEST_SEVERITY_CODE[k],
      host = ifelse(is.na(iab$TREE_SPECIES_CODE[k]), "",
                    iab$TREE_SPECIES_CODE[k]),
      area_ha = round(iab$AREA_HA[k], 1),
      lon = round(ctr[k, 1], 4), lat = round(ctr[k, 2], 4),
      lidar_tiles = length(ys),
      lidar_years = paste(ys, collapse = ";"),
      min_offset = if (length(ys)) min(abs(ys - iab$CAPTURE_YEAR[k])) else NA_integer_,
      stringsAsFactors = FALSE)
  })
  d <- do.call(rbind, rows)
  # Vancouver Island against the mainland, by the same envelope the parent study
  # used for its landmass restriction.
  d$region <- ifelse(d$lon < -123.2 & d$lat < 51.0 & d$lat > 48.3,
                     "Vancouver Island and coast", "Mainland interior")
  write.csv(d, out_csv, row.names = FALSE)
} else {
  d <- read.csv(out_csv, stringsAsFactors = FALSE)
}

mod <- d[d$severity %in% c("M", "S", "V"), ]
cat("\nBALSAM WOOLLY ADELGID, PROVINCE-WIDE, ALL YEARS\n")
cat("  polygons:                      ", nrow(d), "\n")
cat("  moderate or worse:             ", nrow(mod), "\n")
cat("  moderate or worse with lidar:  ", sum(mod$lidar_tiles > 0), "\n\n")
cat("MODERATE OR WORSE FROM 2020 ONWARD\n")
recent <- mod[mod$capture_year >= 2020, ]
cat("  polygons:                      ", nrow(recent), "\n")
if (nrow(recent)) {
  print(recent[order(recent$capture_year, -recent$lidar_tiles),
               c("capture_year", "severity", "host", "area_ha", "lon", "lat",
                 "lidar_tiles", "lidar_years", "min_offset", "region")],
        row.names = FALSE)
}

# ------------------------------------------------------------------- the map

ext_path <- file.path(derived, "lidar-project-extent.geojson")
lid <- sf::st_transform(sf::st_make_valid(sf::st_read(ext_path, quiet = TRUE)),
                        BC_ALBERS)
bcp <- ne_states(country = "Canada", returnclass = "sf")
bc <- sf::st_transform(sf::st_make_valid(bcp[bcp$name == "British Columbia", ]),
                       BC_ALBERS)

pts <- sf::st_as_sf(d, coords = c("lon", "lat"), crs = 4326)
pts <- sf::st_transform(pts, BC_ALBERS)

# Colour carries the survey year, which is the axis the question is about.
brks <- c(1995, 2005, 2010, 2015, 2020, 2025)
labs <- c("1996-2005", "2006-2010", "2011-2015", "2016-2020", "2021-2024")
cols <- c("#2c7bb6", "#abd9e9", "#ffffbf", "#fdae61", "#d7191c")
pts$bin <- cut(pts$capture_year, breaks = brks, labels = labs)

png(file.path(figs, "fig-adelgid-province-1.png"), width = 2400, height = 2000,
    res = 300)
op <- par(mar = c(3.2, 3.6, 1.4, 0.6), xaxs = "i", yaxs = "i")
fr <- sf::st_bbox(bc)
plot(NA, xlim = fr[c("xmin", "xmax")], ylim = fr[c("ymin", "ymax")],
     asp = 1, xlab = "", ylab = "", axes = FALSE)
usr <- par("usr")
rect(usr[1], usr[3], usr[2], usr[4], col = "#eaf1f6", border = NA)
plot(sf::st_geometry(bc), col = "white", border = "grey55", lwd = 0.7, add = TRUE)
plot(sf::st_geometry(lid), col = "#c9e2c9", border = "#4a7a4a", lwd = 0.4,
     add = TRUE)

# Trace and light first and small, moderate and worse over the top and larger,
# because the question is about the severe end of the record.
low <- !(pts$severity %in% c("M", "S", "V"))
plot(sf::st_geometry(pts[low, ]), pch = 21, cex = 0.45,
     bg = adjustcolor(cols[as.integer(pts$bin[low])], alpha.f = 0.55),
     col = "grey35", lwd = 0.25, add = TRUE)
hi <- !low
plot(sf::st_geometry(pts[hi, ]), pch = 24, cex = 1.15,
     bg = cols[as.integer(pts$bin[hi])],
     col = ifelse(pts$lidar_tiles[hi] > 0, "black", "grey60"),
     lwd = ifelse(pts$lidar_tiles[hi] > 0, 1.3, 0.5), add = TRUE)

box(col = "grey40")
axis(1, at = pretty(fr[c("xmin", "xmax")]),
     labels = sprintf("%.0f", pretty(fr[c("xmin", "xmax")]) / 1000),
     cex.axis = 0.7, tcl = -0.25, mgp = c(2, 0.4, 0))
axis(2, at = pretty(fr[c("ymin", "ymax")]),
     labels = sprintf("%.0f", pretty(fr[c("ymin", "ymax")]) / 1000),
     cex.axis = 0.7, tcl = -0.25, mgp = c(2, 0.5, 0), las = 1)
mtext("Easting (km, BC Albers)", 1, line = 1.9, cex = 0.8)
mtext("Northing (km)", 2, line = 2.4, cex = 0.8)

legend("topright", bty = "n", cex = 0.62, title = "Survey year",
       pch = 22, pt.cex = 1.2, col = NA, pt.bg = cols, legend = labs)
legend("right", bty = "n", cex = 0.62, inset = c(0, 0.22),
       pch = c(24, 24, 21, 22), pt.cex = c(1.15, 1.15, 0.55, 1.2),
       pt.bg = c("grey85", "grey85", "grey85", "#c9e2c9"),
       col = c("black", "grey60", "grey35", "#4a7a4a"),
       pt.lwd = c(1.3, 0.5, 0.25, 1),
       legend = c("Moderate or worse, lidar", "Moderate or worse, no lidar",
                  "Trace or light", "Lidar acquisition extent"))
mtext(paste0("Balsam woolly adelgid, ", min(d$capture_year), " to ",
             max(d$capture_year), ", against public lidar coverage"),
      3, line = 0.2, cex = 0.85)
par(op)
invisible(dev.off())

cat("\nwrote ", out_csv, "\n", sep = "")
cat("wrote ", file.path(figs, "fig-adelgid-province-1.png"), "\n", sep = "")
