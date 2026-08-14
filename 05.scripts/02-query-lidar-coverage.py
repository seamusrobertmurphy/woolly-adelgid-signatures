#!/usr/bin/env python3
"""Query LidarBC point cloud tile coverage over the study envelope.

Source:    LidarBC Open LiDAR Data Portal, ArcGIS FeatureServer
           services6.arcgis.com/ubm4tcTYICKBpist/ArcGIS/rest/services/LiDAR_BC_S3_Public
Custodian: GeoBC (which does operate the lidar programme, unlike the pest survey).
Licence:   NOT YET READ from the source. Recorded as unread, not as permissive.
Retrieved: 2026-08-13

Writes a small derived CSV summarising tile counts and acquisition years so the
manuscript can state coverage from saved output rather than from an assertion.
Point clouds themselves are not downloaded here: the index carries direct S3 URLs
and the tiles stay on the external drive when they are eventually pulled.

Note the service caps a single response at 1000 records, so counts are requested
with returnCountOnly rather than by paging, and a count at the cap is reported as
a lower bound.

Usage:
    python3 05.scripts/02-query-lidar-coverage.py
"""

import csv
import json
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "02.inputs" / "derived"

SERVICE = ("https://services6.arcgis.com/ubm4tcTYICKBpist/ArcGIS/rest/services/"
           "LiDAR_BC_S3_Public/FeatureServer")
POINT_CLOUD_LAYER = 4

# Two envelopes: the full study area used by the analysis, and the Comox Valley
# window where Seamus can reach field sites on the ground.
ENVELOPES = {
    "study area": (-128.5, 48.3, -123.0, 51.0),
    "Comox field window": (-125.3, 49.4, -124.5, 49.9),
}


def query(layer: int, env: tuple, **params) -> dict:
    geom = {"xmin": env[0], "ymin": env[1], "xmax": env[2], "ymax": env[3],
            "spatialReference": {"wkid": 4326}}
    q = {
        "where": "1=1",
        "geometry": json.dumps(geom),
        "geometryType": "esriGeometryEnvelope",
        "inSR": "4326",
        "spatialRel": "esriSpatialRelIntersects",
        "f": "json",
    }
    q.update(params)
    url = f"{SERVICE}/{layer}/query?" + urllib.parse.urlencode(q)
    with urllib.request.urlopen(url, timeout=120) as resp:
        return json.loads(resp.read().decode())


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []

    for name, env in ENVELOPES.items():
        count = query(POINT_CLOUD_LAYER, env, returnCountOnly="true").get("count", 0)

        # A sample of tiles gives the acquisition years and nominal density without
        # paging the whole index.
        sample = query(POINT_CLOUD_LAYER, env,
                       outFields="year,density,projection,classes",
                       returnGeometry="false", resultRecordCount=1000)
        feats = [f["attributes"] for f in sample.get("features", [])]
        years = sorted({f.get("year") for f in feats if f.get("year")})
        dens = sorted({f.get("density") for f in feats if f.get("density")})
        classes = sorted({f.get("classes") for f in feats if f.get("classes")})

        rows.append({
            "envelope": name,
            "tiles": count,
            # The count is exact (returnCountOnly), but the attribute summaries
            # below come from a sample capped at 1000 records by the service. For
            # any envelope with more tiles than that, the year and class lists are
            # what the sample happened to contain and are NOT the full range.
            "attrs_from_full_index": count <= 1000,
            "acquisition_years_sampled": ";".join(str(y) for y in years),
            "density_pts_m2": ";".join(str(d) for d in dens),
            "point_classes": ";".join(classes),
        })
        print(f"{name}: {count} tiles, years {years}, density {dens}")

    path = OUT / "lidar-coverage.csv"
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print("wrote", path)


if __name__ == "__main__":
    main()
