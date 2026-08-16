# Every forest health damage agent recorded on and around Vancouver Island from
# 2020 onward, against the lidar tiles that overlap them.
#
# No agent is filed under "other". The twelve most abundant are drawn and named
# individually and every remaining agent is drawn in the colour of its class, so
# a reader choosing an agent can see all of them. The complete count for all
# agents, diseases included, is written to
# 03.outputs/tables/vi-agents-2020plus.csv.
#
# Codes are resolved from two authoritative sources rather than guessed: the
# current survey service, which names the codes it contains, and the Forest
# Health Aerial Overview Survey Standards, which carries the full list. Codes
# are hierarchical, one letter for a category, two for a group, three for a
# species, so a two-letter record is a surveyor who did not identify to species
# and is labelled as such rather than dropped.
#
# The 769 MB survey archive is never read into memory: selection happens in GDAL
# through sf::gdal_utils and only the extract reaches R.
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
dir.create(tables, showWarnings = FALSE, recursive = TRUE)
BC_ALBERS <- 3005

GDB <- file.path(root, "02.inputs", "survey", "pest_infestation_poly.gdb")
FIRST_YEAR <- 2020
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
                "-select",
                "CAPTURE_YEAR,PEST_SPECIES_CODE,PEST_SEVERITY_CODE,TREE_SPECIES_CODE,AREA_HA",
                "-where", paste0("CAPTURE_YEAR >= ", FIRST_YEAR),
                "pest_infestation_poly"))
}
pol <- sf::st_read(out_geo, quiet = TRUE)

lk <- read.csv(file.path(derived, "agent-lookup.csv"), stringsAsFactors = FALSE)
pol$agent <- lk$agent[match(pol$PEST_SPECIES_CODE, lk$code)]
pol$agent_class <- lk$agent_class[match(pol$PEST_SPECIES_CODE, lk$code)]
stopifnot(!anyNA(pol$agent))

tiles <- sf::st_read(file.path(derived, "lidar-tiles.geojson"), quiet = TRUE)
bm <- file.path(derived, "basemap.gpkg")
land <- sf::st_read(bm, "land", quiet = TRUE)
places <- sf::st_read(bm, "places", quiet = TRUE)

fr <- sf::st_transform(sf::st_as_sfc(sf::st_bbox(FRAME, crs = 4326)), BC_ALBERS)
frb <- sf::st_bbox(fr)

png(file.path(figs, "fig-vi-agents-1.png"), width = 2600, height = 2400,
    res = 300)
op <- par(mar = c(3.4, 4.0, 1.6, 0.8), xaxs = "i", yaxs = "i")
plot(NA, xlim = frb[c("xmin", "xmax")], ylim = frb[c("ymin", "ymax")],
     asp = 1, xlab = "", ylab = "", axes = FALSE)

# Clip to the region actually drawn, not to the frame requested. A fixed aspect
# ratio expands the shorter axis, so cropping to xlim and ylim stops the coast
# short of the neatline and opens a band of sea between the land and the frame.
# par("usr") is only known once the device is open, which is why the clip
# happens after the plot is set up rather than before it.
usr <- par("usr")
draw_box <- sf::st_sfc(sf::st_polygon(list(rbind(
  c(usr[1], usr[3]), c(usr[2], usr[3]), c(usr[2], usr[4]),
  c(usr[1], usr[4]), c(usr[1], usr[3])))), crs = BC_ALBERS)
clip <- function(x) suppressWarnings(
  sf::st_intersection(sf::st_make_valid(sf::st_transform(x, BC_ALBERS)),
                      draw_box))
pol_c <- clip(pol)
til_c <- clip(tiles)
lnd_c <- clip(land)
plc <- sf::st_transform(places, BC_ALBERS)
plc <- plc[lengths(sf::st_intersects(plc, draw_box)) > 0 & plc$name != "Comox", ]

top <- sort(table(pol_c$agent), decreasing = TRUE)
named <- names(top)[seq_len(min(12, length(top)))]
acols <- c("#e31a1c", "#ff7f00", "#6a3d9a", "#33a02c", "#1f78b4", "#b15928",
           "#fb9a99", "#cab2d6", "#a6cee3", "#b2df8a", "#fdbf6f", "#f781bf")
class_cols <- c(`Bark beetle` = "#99000d", Defoliator = "#8c510a",
                Disease = "#54278f", Abiotic = "#08519c",
                `Sap feeder` = "#006d2c", Animal = "#525252")

rect(usr[1], usr[3], usr[2], usr[4], col = "#dce7ef", border = NA)
plot(sf::st_geometry(lnd_c), col = "white", border = "grey55", lwd = 0.5,
     add = TRUE)
yr <- til_c$year
ord <- sort(unique(stats::na.omit(yr)))
pal <- grDevices::colorRampPalette(c("#dff0d8", "#5a8a50"))(length(ord))
plot(sf::st_geometry(til_c), col = pal[match(yr, ord)], border = NA, add = TRUE)

# Unnamed agents first in their class colour, then the twelve named over them.
rest <- !(pol_c$agent %in% named)
for (cl in names(class_cols)) {
  k <- rest & pol_c$agent_class == cl
  if (any(k)) plot(sf::st_geometry(pol_c[k, ]), col = class_cols[[cl]],
                   border = NA, add = TRUE)
}
for (i in seq_along(named))
  plot(sf::st_geometry(pol_c[pol_c$agent == named[i], ]), col = acols[i],
       border = NA, add = TRUE)

pxy <- sf::st_coordinates(plc)
points(pxy, pch = 22, bg = "white", col = "grey15", cex = 0.75, lwd = 0.6)
near_edge <- pxy[, 1] > usr[1] + 0.86 * (usr[2] - usr[1])
text(pxy[, 1], pxy[, 2], plc$name, pos = ifelse(near_edge, 2, 4),
     offset = 0.32, cex = 0.5, col = "grey10")

xt <- pretty(usr[1:2], 5); yt <- pretty(usr[3:4], 5)
xt <- xt[xt > usr[1] & xt < usr[2]]; yt <- yt[yt > usr[3] & yt < usr[4]]
xd <- sf::sf_project(paste0("EPSG:", BC_ALBERS), "EPSG:4326",
                     cbind(xt, rep(usr[3], length(xt))))[, 1]
yd <- sf::sf_project(paste0("EPSG:", BC_ALBERS), "EPSG:4326",
                     cbind(rep(usr[1], length(yt)), yt))[, 2]
axis(1, at = xt, labels = sprintf("%.1f°W", abs(xd)), cex.axis = 0.65,
     tcl = -0.25, mgp = c(2, 0.4, 0))
axis(2, at = yt, labels = sprintf("%.1f°N", yd), cex.axis = 0.65,
     tcl = -0.25, mgp = c(2, 0.5, 0), las = 1)
box(col = "grey25")

# Representative fraction from the printed size of the plot region, computed
# rather than asserted: ground width over map width, both in metres.
rf <- signif((usr[2] - usr[1]) / (par("pin")[1] * 0.0254), 2)
bar_km <- 50
bx0 <- usr[1] + 0.045 * (usr[2] - usr[1])
by0 <- usr[3] + 0.060 * (usr[4] - usr[3])
bh <- 0.010 * (usr[4] - usr[3])
for (i in 0:1)
  rect(bx0 + i * bar_km * 1000, by0, bx0 + (i + 1) * bar_km * 1000, by0 + bh,
       col = c("black", "white")[i + 1], border = "black", lwd = 0.7)
text(c(bx0, bx0 + bar_km * 1000, bx0 + 2 * bar_km * 1000), by0 + bh * 2.2,
     c("0", bar_km, paste(2 * bar_km, "km")), cex = 0.5, col = "grey10")
text(bx0, by0 - bh * 1.7,
     paste0("Scale 1:", format(rf, big.mark = ",", scientific = FALSE)),
     pos = 4, offset = 0, cex = 0.5, col = "grey10")

nx <- usr[1] + 0.045 * (usr[2] - usr[1])
ny <- usr[3] + 0.140 * (usr[4] - usr[3])
ah <- 0.045 * (usr[4] - usr[3])
polygon(c(nx, nx - ah * 0.28, nx, nx + ah * 0.28),
        c(ny + ah, ny, ny + ah * 0.28, ny), col = "black", border = "black")
text(nx, ny + ah * 1.24, "N", cex = 0.62, font = 2)

rest_by_class <- sort(table(pol_c$agent_class[rest]), decreasing = TRUE)
legend("topright", inset = 0.010, bg = "white", box.col = "grey55",
       box.lwd = 0.7, cex = 0.55, pch = 22, pt.cex = 1.1, col = "grey30",
       pt.bg = acols[seq_along(named)],
       legend = paste0(named, " (", as.integer(top[named]), ")"))
legend("bottomright", inset = 0.010, bg = "white", box.col = "grey55",
       box.lwd = 0.7, cex = 0.55, pch = 22, pt.cex = 1.1, col = "grey30",
       pt.bg = c(class_cols[names(rest_by_class)], pal[length(pal)]),
       legend = c(paste0(names(rest_by_class), " (",
                         as.integer(rest_by_class), ")"), "Lidar tile"))
mtext(paste0("Forest health damage agents, ", FIRST_YEAR, " to ",
             max(pol_c$CAPTURE_YEAR), ", with lidar tile coverage"),
      3, line = 0.3, cex = 0.85)
par(op)
invisible(dev.off())

# The complete inventory. Every agent, no lump.
sev <- table(pol$PEST_SPECIES_CODE, pol$PEST_SEVERITY_CODE)
tb <- data.frame(code = rownames(sev), stringsAsFactors = FALSE)
tb$agent <- lk$agent[match(tb$code, lk$code)]
tb$class <- lk$agent_class[match(tb$code, lk$code)]
tb$polygons <- as.integer(rowSums(sev))
tb$mod_plus <- as.integer(rowSums(
  sev[, intersect(c("M", "S", "V"), colnames(sev)), drop = FALSE]))
tb$area_ha <- round(as.numeric(tapply(pol$AREA_HA, pol$PEST_SPECIES_CODE,
                                      sum)[tb$code]))
tb <- tb[order(-tb$polygons), ]
write.csv(tb, file.path(tables, "vi-agents-2020plus.csv"), row.names = FALSE)

cat("\nVANCOUVER ISLAND AND COAST, ", FIRST_YEAR, " to ",
    max(pol$CAPTURE_YEAR), "\n", sep = "")
cat("  polygons: ", nrow(pol), "   agents: ", nrow(tb),
    "   lidar tiles drawn: ", nrow(til_c), "\n\n", sep = "")
print(tb, row.names = FALSE)
cat("\nwrote ", file.path(figs, "fig-vi-agents-1.png"), "\n", sep = "")
