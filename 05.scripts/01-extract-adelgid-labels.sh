#!/bin/bash
# Extract balsam woolly adelgid (IAB) polygons from the BC aerial overview survey
# archive into a small GeoJSON the manuscript can read.
#
# Source:    Pest Infestation Polygons, BC Data Catalogue, record 450b67bb-02d5-4526-8bc0-ac7924125a1e
# Licence:   Open Government Licence - British Columbia
# Custodian: BC Ministry of Forests (point of contact Babita Bains). Not GeoBC.
# Retrieved: 2026-08-13
#
# The delivered file geodatabase carries codes only, no common or latin names, so
# IAB is resolved from the Forest Health Aerial Overview Survey Standards, not from
# the delivery. That code assignment is UNVERIFIED against a primary source at the
# time of writing: the 2019 standards PDF returned 404 and the methods page lists no
# codes. Treat the species label as provisional until the standards document is read.
#
# The full archive is 908 MB unzipped and 1,172,716 polygons, so it is never read
# into memory. ogr2ogr does the selection and the reprojection, and only the IAB
# records reach R. The archive itself stays out of the repository.
#
# Usage: 05.scripts/01-extract-adelgid-labels.sh <path-to-pest_infestation_poly.gdb>

set -euo pipefail

GDB="${1:?usage: 01-extract-adelgid-labels.sh <path-to-pest_infestation_poly.gdb>}"
OUT="$(cd "$(dirname "$0")/.." && pwd)/02.inputs/derived"
mkdir -p "$OUT"

# 1. Province-wide balsam woolly adelgid, for the extent and time-series figure.
# WGS84 so the file is readable without a projection library. Attributes kept are
# the ones needed to judge label quality: severity, host, survey method, year.
ogr2ogr -f GeoJSON "$OUT/adelgid-iab-polygons.geojson" "$GDB" \
  -t_srs EPSG:4326 \
  -where "PEST_SPECIES_CODE = 'IAB'" \
  -select CAPTURE_YEAR,PEST_SEVERITY_CODE,PEST_CAPTURE_METHOD_CODE,TREE_SPECIES_CODE,AREA_HA \
  pest_infestation_poly

# 2. The two agents that share a true-fir host on Vancouver Island. IAB is the
# target class and IBB, western balsam bark beetle, is the confusable class: both
# are mapped on Pacific silver fir (BA) in the same survey, so separating them is
# an attribution problem, not a detection problem. The envelope is a rectangle
# around Vancouver Island and therefore also catches part of the adjacent
# mainland coast; the manuscript clips to a coastline before any modelling and
# reports both counts.
ogr2ogr -f GeoJSON "$OUT/vi-fir-agents.geojson" "$GDB" \
  -t_srs EPSG:4326 \
  -spat -128.5 48.3 -123.0 51.0 -spat_srs EPSG:4326 \
  -where "PEST_SPECIES_CODE IN ('IAB','IBB') AND TREE_SPECIES_CODE IN ('B','BA','BG','BL')" \
  -select CAPTURE_YEAR,PEST_SPECIES_CODE,PEST_SEVERITY_CODE,TREE_SPECIES_CODE,AREA_HA \
  pest_infestation_poly

for f in adelgid-iab-polygons vi-fir-agents; do
  echo "wrote $OUT/$f.geojson"
done
