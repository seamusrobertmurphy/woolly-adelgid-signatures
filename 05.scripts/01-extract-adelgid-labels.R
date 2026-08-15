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

# Source:    Pest Infestation Polygons, BC Data Catalogue, record
#            450b67bb-02d5-4526-8bc0-ac7924125a1e
# Licence:   Open Government Licence - British Columbia
# Custodian: BC Ministry of Forests. Not GeoBC.
#
# The delivered geodatabase carries codes only, no common or latin names, so IAB
# is resolved from the Forest Health Aerial Overview Survey Standards rather than
# from the delivery.
#
# NOTE ON TESTING. The archive is not on this machine, so this block has not been
# run end to end since it was translated from shell. The GDAL call and the layer
# and field names were checked against the committed extracts on 2026-08-14; the
# WHERE clauses were not re-executed. Set ADELGID_GDB to the archive to run it.
gdb <- Sys.getenv("ADELGID_GDB", unset = "")
iab_path <- file.path(derived, "adelgid-iab-polygons.geojson")
vi_path <- file.path(derived, "vi-fir-agents.geojson")

if (!file.exists(iab_path) || !file.exists(vi_path)) local({
  if (!nzchar(gdb) || !file.exists(gdb))
    stop("set ADELGID_GDB to the pest_infestation_poly.gdb archive")

  # 1. Province-wide balsam woolly adelgid, for the extent and time series.
  # WGS84 so the file is readable without a projection library. The attributes
  # kept are the ones needed to judge label quality.
  sf::gdal_utils(
    util = "vectortranslate", source = gdb, destination = iab_path,
    options = c("-f", "GeoJSON", "-t_srs", "EPSG:4326", "-sql",
                paste("SELECT CAPTURE_YEAR, PEST_SEVERITY_CODE,",
                      "PEST_CAPTURE_METHOD_CODE, TREE_SPECIES_CODE, AREA_HA",
                      "FROM pest_infestation_poly",
                      "WHERE PEST_SPECIES_CODE = 'IAB'")))

  # 2. The two agents that share a true-fir host around Vancouver Island. IAB is
  # the target class and IBB, western balsam bark beetle, the confusable one:
  # both are mapped on Pacific silver fir in the same survey, so separating them
  # is attribution, not detection. The envelope is a rectangle and therefore also
  # catches the adjacent mainland; the sample is restricted to the island later,
  # and both counts are reported.
  sf::gdal_utils(
    util = "vectortranslate", source = gdb, destination = vi_path,
    options = c("-f", "GeoJSON", "-t_srs", "EPSG:4326",
                "-spat", "-128.5", "48.3", "-123.0", "51.0",
                "-spat_srs", "EPSG:4326", "-sql",
                paste("SELECT CAPTURE_YEAR, PEST_SPECIES_CODE,",
                      "PEST_SEVERITY_CODE, TREE_SPECIES_CODE, AREA_HA",
                      "FROM pest_infestation_poly",
                      "WHERE PEST_SPECIES_CODE IN ('IAB','IBB')",
                      "AND TREE_SPECIES_CODE IN ('B','BA','BG','BL')")))
})


