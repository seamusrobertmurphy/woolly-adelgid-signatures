# Every forest health damage agent recorded on and around Vancouver Island from
# 2020 onward, against the lidar tiles that overlap them.
#
# The parent study looked at two agents on one host. This map looks at all of
# them, over the years that matter for a study intended to reach the field in
# 2026, so that the choice of agent can be made from what is there rather than
# from what was looked at first.
#
# The 769 MB survey archive is never read into memory: the selection happens in
# GDAL through sf::gdal_utils, which drives the same routine ogr2ogr does, and
# only the extract reaches R.
#
# Every layer is clipped to the map frame, so nothing is drawn outside the
# rectangle the graticule labels describe.
#
# Usage: Rscript 05.scripts/24-vancouver-island-agents.R

suppressMessages({
  library(sf)
})

root <- normalizePath(".")
derived <- file.path(root, "02.inputs", "derived")
figs <- file.path(root, "03.outputs", "figures")
tables <- file.path(root, "03.outputs", "tables")
dir.create(figs, showWarnings = FALSE, recursive = TRUE)
BC_ALBERS <- 3005

GDB <- file.path(root, "02.inputs", "survey", "pest_infestation_poly.gdb")
FIRST_YEAR <- 2020
# The frame is the map. Everything is clipped to it and the graticule labels
# describe exactly this rectangle.
FRAME <- c(xmin = -128.9, ymin = 48.3, xmax = -123.2, ymax = 51.2)

out_geo <- file.path(derived, "vi-agents-2020plus.geojson")
if (!file.exists(out_geo)) {
  stopifnot(dir.exists(GDB))
  message("selecting from the archive in GDAL")
  sf::gdal_utils(
    util = "vectortranslate", source = GDB, destination = out_geo,
    options = c("-f", "GeoJSON", "-t_srs", "EPSG:4326",
                "-spat", as.character(FRAME["xmin"]), as.character(FRAME["ymin"]),
                as.character(FRAME["xmax"]), as.character(FRAME["ymax"]),
                "-spat_srs", "EPSG:4326",
                # -spat_srs cannot be combined with -sql, so the column and row
                # selection use -select and -where instead, which GDAL accepts
                # alongside a reprojected spatial filter.
                "-select",
                "CAPTURE_YEAR,PEST_SPECIES_CODE,PEST_SEVERITY_CODE,TREE_SPECIES_CODE,AREA_HA",
                "-where", paste0("CAPTURE_YEAR >= ", FIRST_YEAR),
                "pest_infestation_poly"))
}
pol <- sf::st_read(out_geo, quiet = TRUE)
message(nrow(pol), " polygons, ", FIRST_YEAR, " onward, in the frame")

# Agent names, from the current survey layer which carries them, so the legend
# is readable without a code lookup the reader does not have.
# The archive carries damage agent codes and no names at all, so names come
# from the current survey layer, which carries both. A code the current year
# does not contain stays a code rather than being guessed: IAB is the one
# exception, established against the survey standards earlier in this project.
nm <- read.csv(file.path(derived, "agent-names.csv"), stringsAsFactors = FALSE)
nm <- rbind(nm, data.frame(PEST_SPECIES_CODE = "IAB",
                           PEST_SPECIES_COMMON_NAME = "Balsam Woolly Adelgid",
                           PEST_SPECIES_LATIN_NAME = "Adelges piceae"))
pol$agent <- nm$PEST_SPECIES_COMMON_NAME[match(pol$PEST_SPECIES_CODE,
                                               nm$PEST_SPECIES_CODE)]
unnamed <- is.na(pol$agent) | !nzchar(pol$agent)
pol$agent[unnamed] <- paste0("Code ", pol$PEST_SPECIES_CODE[unnamed])

tiles <- sf::st_read(file.path(derived, "lidar-tiles.geojson"), quiet = TRUE)
bm <- file.path(derived, "basemap.gpkg")
land <- sf::st_read(bm, "land", quiet = TRUE)
places <- sf::st_read(bm, "places", quiet = TRUE)

# ------------------------------------------------------------------ clipping
# One frame, in projected coordinates, and every layer cropped to it. Drawing a
# layer wider than the frame and relying on the device to clip leaves geometry
# hanging outside the axes when the aspect ratio expands the shorter side.
fr_ll <- sf::st_as_sfc(sf::st_bbox(FRAME, crs = 4326))
fr <- sf::st_transform(fr_ll, BC_ALBERS)
frb <- sf::st_bbox(fr)
clip <- function(x) {
  x <- sf::st_transform(sf::st_make_valid(x), BC_ALBERS)
  suppressWarnings(sf::st_intersection(x, fr))
}
pol_c <- clip(pol)
til_c <- clip(tiles)
lnd_c <- clip(land)
plc <- sf::st_transform(places, BC_ALBERS)
plc <- plc[lengths(sf::st_intersects(plc, fr)) > 0, ]
# Comox is not a field base for this work and carries no cartographic role.
plc <- plc[plc$name != "Comox", ]

top <- sort(table(pol_c$agent), decreasing = TRUE)
keep <- names(top)[seq_len(min(7, length(top)))]
cols <- c("#d7301f", "#fc8d59", "#8c510a", "#1a9850", "#4575b4", "#762a83",
          "#e7298a")

png(file.path(figs, "fig-vi-agents-1.png"), width = 2400, height = 2300,
    res = 300)
op <- par(mar = c(3.2, 3.8, 1.4, 0.6), xaxs = "i", yaxs = "i")
plot(NA, xlim = frb[c("xmin", "xmax")], ylim = frb[c("ymin", "ymax")],
     asp = 1, xlab = "", ylab = "", axes = FALSE)
usr <- par("usr")
rect(usr[1], usr[3], usr[2], usr[4], col = "#dce7ef", border = NA)
plot(sf::st_geometry(lnd_c), col = "white", border = "grey55", lwd = 0.5,
     add = TRUE)
# Lidar tiles under the damage, shaded by acquisition year.
yr <- til_c$year
pal <- grDevices::colorRampPalette(c("#d9f0d3", "#4a7a4a"))(
  length(unique(stats::na.omit(yr))))
ord <- sort(unique(stats::na.omit(yr)))
plot(sf::st_geometry(til_c), col = pal[match(yr, ord)], border = NA, add = TRUE)

other <- !(pol_c$agent %in% keep)
if (any(other))
  plot(sf::st_geometry(pol_c[other, ]), col = "grey45", border = NA, add = TRUE)
for (i in seq_along(keep))
  plot(sf::st_geometry(pol_c[pol_c$agent == keep[i], ]), col = cols[i],
       border = NA, add = TRUE)

pxy <- sf::st_coordinates(plc)
points(pxy, pch = 22, bg = "white", col = "grey15", cex = 0.75, lwd = 0.6)
# A label near the eastern edge is thrown left so it stays inside the frame
# rather than being cut by it.
near_edge <- pxy[, 1] > frb["xmin"] + 0.86 * (frb["xmax"] - frb["xmin"])
text(pxy[, 1], pxy[, 2], plc$name, pos = ifelse(near_edge, 2, 4),
     offset = 0.32, cex = 0.5, col = "grey10")

# Graticule labels in degrees, describing exactly the frame that was clipped to.
xt <- pretty(frb[c("xmin", "xmax")], 5); yt <- pretty(frb[c("ymin", "ymax")], 5)
xt <- xt[xt > frb["xmin"] & xt < frb["xmax"]]
yt <- yt[yt > frb["ymin"] & yt < frb["ymax"]]
xd <- sf::sf_project(paste0("EPSG:", BC_ALBERS), "EPSG:4326",
                     cbind(xt, rep(frb["ymin"], length(xt))))[, 1]
yd <- sf::sf_project(paste0("EPSG:", BC_ALBERS), "EPSG:4326",
                     cbind(rep(frb["xmin"], length(yt)), yt))[, 2]
axis(1, at = xt, labels = sprintf("%.1f°W", abs(xd)), cex.axis = 0.65,
     tcl = -0.25, mgp = c(2, 0.4, 0))
axis(2, at = yt, labels = sprintf("%.1f°N", yd), cex.axis = 0.65,
     tcl = -0.25, mgp = c(2, 0.5, 0), las = 1)
box(col = "grey35")

legend("topright", bty = "n", cex = 0.6, pch = 22, pt.cex = 1.1, col = NA,
       pt.bg = c(cols[seq_along(keep)], "grey45", pal[length(pal)]),
       legend = c(paste0(keep, " (", as.integer(top[keep]), ")"),
                  paste0("Other agents (", sum(other), ")"),
                  "Lidar tile"))
mtext(paste0("Forest health damage agents, ", FIRST_YEAR, " to ",
             max(pol_c$CAPTURE_YEAR), ", with lidar tile coverage"),
      3, line = 0.2, cex = 0.85)
par(op)
invisible(dev.off())

tb <- as.data.frame(top)
names(tb) <- c("agent", "polygons")
write.csv(tb, file.path(tables, "vi-agents-2020plus.csv"), row.names = FALSE)

cat("\nVANCOUVER ISLAND AND COAST, ", FIRST_YEAR, " ONWARD\n", sep = "")
cat("  polygons in frame: ", nrow(pol_c), "\n", sep = "")
cat("  agents:            ", length(unique(pol_c$agent)), "\n", sep = "")
cat("  survey years:      ",
    paste(range(pol_c$CAPTURE_YEAR), collapse = " to "), "\n", sep = "")
cat("  lidar tiles drawn: ", nrow(til_c), "\n\n", sep = "")
print(utils::head(tb, 12), row.names = FALSE)
cat("\nwrote ", file.path(figs, "fig-vi-agents-1.png"), "\n", sep = "")
