# Province-wide availability map: where moderate or worse damage meets lidar.
#
# The parent study was located by data availability and so must its successors
# be, so this map exists to make the choice of agent visible rather than
# argued. It draws every moderate, severe or very severe damage polygon in the
# current survey year against the extent of public lidar acquisition, so that a
# reader can see which agents fall inside coverage and which do not.
#
# Lidar extent comes from layer 0 of the LidarBC FeatureServer, the project
# data extent, which carries 13 polygons province-wide with an acquisition year.
# That is the right layer for a map: the tile index carries 159,607 features and
# would render as a solid block at this scale while taking minutes to fetch.
#
# Usage: Rscript 05.scripts/22-availability-map.R

suppressMessages({
  library(sf)
  library(rnaturalearth)
})

root <- normalizePath(".")
derived <- file.path(root, "02.inputs", "derived")
figs <- file.path(root, "03.outputs", "figures")
dir.create(figs, showWarnings = FALSE, recursive = TRUE)
BC_ALBERS <- 3005

pol <- sf::st_read(file.path(derived, "moderate-plus-2025.geojson"), quiet = TRUE)
pol <- sf::st_transform(sf::st_make_valid(pol), BC_ALBERS)

ext_path <- file.path(derived, "lidar-project-extent.geojson")
if (!file.exists(ext_path)) {
  u <- paste0("https://services6.arcgis.com/ubm4tcTYICKBpist/ArcGIS/rest/",
              "services/LiDAR_BC_S3_Public/FeatureServer/0/query?",
              "where=1%3D1&outFields=YEAR_&returnGeometry=true&outSR=4326&f=geojson")
  sf::st_write(sf::st_read(u, quiet = TRUE), ext_path, quiet = TRUE)
}
lid <- sf::st_transform(sf::st_make_valid(
  sf::st_read(ext_path, quiet = TRUE)), BC_ALBERS)

prov <- ne_states(country = "Canada", returnclass = "sf")
bc <- sf::st_transform(sf::st_make_valid(prov[prov$name == "British Columbia", ]),
                       BC_ALBERS)

# The agents worth naming. Everything else is drawn in grey, because a legend of
# forty entries communicates nothing.
top <- sort(table(pol$PEST_SPECIES_CODE), decreasing = TRUE)
keep <- names(top)[seq_len(min(6, length(top)))]
labs <- vapply(keep, function(k)
  pol$PEST_SPECIES_COMMON_NAME[match(k, pol$PEST_SPECIES_CODE)], "")
cols <- c("#d7301f", "#fc8d59", "#8c510a", "#1a9850", "#4575b4", "#762a83")

png(file.path(figs, "fig-availability-1.png"), width = 2400, height = 2000,
    res = 300)
op <- par(mar = c(3.2, 3.6, 1.2, 0.6), xaxs = "i", yaxs = "i")
fr <- sf::st_bbox(bc)
plot(NA, xlim = fr[c("xmin", "xmax")], ylim = fr[c("ymin", "ymax")],
     asp = 1, xlab = "", ylab = "", axes = FALSE)
usr <- par("usr")
rect(usr[1], usr[3], usr[2], usr[4], col = "#eaf1f6", border = NA)
plot(sf::st_geometry(bc), col = "white", border = "grey55", lwd = 0.7,
     add = TRUE)

# Lidar first and underneath: it is the constraint, not the subject.
plot(sf::st_geometry(lid), col = "#b8d8b8", border = "#4a7a4a", lwd = 0.5,
     add = TRUE)

other <- !(pol$PEST_SPECIES_CODE %in% keep)
if (any(other))
  plot(sf::st_geometry(pol[other, ]), col = "grey60", border = NA, add = TRUE)
for (i in seq_along(keep)) {
  k <- pol$PEST_SPECIES_CODE == keep[i]
  plot(sf::st_geometry(pol[k, ]), col = cols[i], border = NA, add = TRUE)
}

box(col = "grey40")
axis(1, at = pretty(fr[c("xmin", "xmax")]),
     labels = sprintf("%.0f", pretty(fr[c("xmin", "xmax")]) / 1000),
     cex.axis = 0.7, tcl = -0.25, mgp = c(2, 0.4, 0))
axis(2, at = pretty(fr[c("ymin", "ymax")]),
     labels = sprintf("%.0f", pretty(fr[c("ymin", "ymax")]) / 1000),
     cex.axis = 0.7, tcl = -0.25, mgp = c(2, 0.5, 0), las = 1)
mtext("Easting (km, BC Albers)", 1, line = 1.9, cex = 0.8)
mtext("Northing (km)", 2, line = 2.4, cex = 0.8)

legend("topright", bty = "n", cex = 0.68, pt.cex = 1.1, pch = 22,
       col = NA, pt.bg = c("#b8d8b8", cols[seq_along(keep)], "grey60"),
       legend = c("LidarBC acquisition extent",
                  paste0(labs, " (", as.integer(top[keep]), ")"),
                  paste0("Other agents (",
                         sum(!(pol$PEST_SPECIES_CODE %in% keep)), ")")))
mtext(paste0("Moderate or worse damage, survey year ",
             paste(sort(unique(pol$CAPTURE_YEAR)), collapse = ", "),
             ", against public lidar coverage"), 3, line = 0.1, cex = 0.85)
par(op)
invisible(dev.off())

cat("wrote ", file.path(figs, "fig-availability-1.png"), "\n", sep = "")
cat("lidar project extents: ", nrow(lid), ", years ",
    paste(range(lid$YEAR_, na.rm = TRUE), collapse = " to "), "\n", sep = "")
cat("damage polygons drawn: ", nrow(pol), " across ",
    length(unique(pol$PEST_SPECIES_CODE)), " agents\n", sep = "")
