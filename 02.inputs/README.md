# Input data manifest

Every dataset entering `02.inputs/` is recorded here on the day it is downloaded, with
integrity hashes appended to `SHA256SUMS.txt` and verified by
`05.scripts/01_verify_inputs.R`. Raw data are gitignored; this manifest and the retrieval
code are the reproducible record. The lidar tiles were fetched by
`05.scripts/17-build-lidar-metrics.R --fetch` rather than by `00_download_inputs.sh`,
because the tile list is derived from the frozen analysis set and cannot be a static list.

The licence column carries what was read from the source on the date given, quoted where
the wording matters. A dataset whose licence page has not been opened is recorded as
unread, never as public domain by assumption. Service metadata counts as the source: a
licence sitting in an image service's own metadata is binding even when the endpoint is
open, and missing that text once already produced a wrong entry in the sibling project.

No outcome analysis is run on any file here until the pre-registration is frozen.

## Downloaded

| Folder | Dataset | Source | Licence | Notes |
|---|---|---|---|---|
| `lidar/<year>/` | LidarBC classified point clouds, 121 LAZ tiles, 78.7 GB | LidarBC Open LiDAR Data Portal, ArcGIS FeatureServer `LiDAR_BC_S3_Public` layer 4, files from `nrs.objectstore.gov.bc.ca`. Custodian GeoBC. Retrieved 2026-08-14 | Open Government Licence - British Columbia. Read from the BC Data Catalogue record `lidarbc-open-lidar-data-portal` on 2026-08-14, which states verbatim: "The data in the portal is released as Open Data under the **Open Government Licence – British Columbia** (OGL-BC)." Attribution required | The catalogue's own `license_title` field reads "Access Only", which governs the portal application and its map services, not the point clouds; the description quoted here governs the data. The companion record `lidar` carries OGL-BC directly. Tiles are 8 points per square metre, classes 1, 2, 7 and 12, so there is no vegetation class and canopy height is normalised against class 2 ground returns. Selected by intersection with the frozen analysis set **and** acquisition year, listed in `derived/lidar-tiles-needed.csv`, mapped to polygons in `derived/lidar-tile-map.csv` |

## Derived

Intermediate products built by manuscript chunks or saved scripts, each regenerable from
the raw inputs and gitignored unless it is a small CSV the manuscript cites. Record what
builds it, what it is built from, its approximate size, and whether it rebuilds
automatically when its source is newer.

- pending

## Streaming or on-demand

Sources used without a local copy: web services, cloud archives, and anything whose
licence forbids bulk download. Record the endpoint, the terms read from the live page,
and the date read.

- **Sentinel-2 L2A**, `COPERNICUS/S2_SR_HARMONIZED` through Google Earth Engine under
  project `murphys-deforisk`. No pixels are stored locally; only the polygon summaries in
  `derived/predictors-optical.csv` are kept. Licence **unread**, recorded as unread. Used
  2026-08-14 by `05.scripts/15-build-optical-predictors.R`.
- **Sentinel-1 GRD**, `COPERNICUS/S1_GRD` through the same project, likewise reduced to
  `derived/predictors-radar.csv`. Licence **unread**, recorded as unread. The Earth Engine
  catalogue page, read 2026-08-14, documents only thermal noise removal, radiometric
  calibration and Range Doppler terrain correction for this collection; it does not state
  that an orbit file is applied or that GRD border noise is removed. Used by
  `05.scripts/16-build-radar-predictors.R`.
- **Pest Infestation Polygons**, the 908 MB aerial overview survey archive. Never read
  into memory: selection happens in `ogr2ogr` and only the extracts reach R. Open
  Government Licence - British Columbia, custodian the BC Ministry of Forests.
