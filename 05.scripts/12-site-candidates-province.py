#!/usr/bin/env python3
"""Find every balsam woolly adelgid polygon in British Columbia that has lidar.

Supersedes the Vancouver Island and Comox-distance filter of
05.scripts/10-field-site-candidates.R. Per Seamus, 2026-08-14: data availability
of lidar and of moderate or severe severity dictates the study's scope and
location, not proximity to Comox. Vancouver Island is preferred; the mainland is
acceptable if the island cannot supply the sample.

Coverage is queried per polygon envelope rather than over one large rectangle,
because the province-wide adelgid record spans from the coast to the Kootenays
and a single envelope would pull far more tile geometry than the machine should
hold.

Writes 02.inputs/derived/site-candidates-province.csv, one row per adelgid
polygon with its lidar tile count, acquisition years and the offset between the
survey year and the nearest acquisition.

Usage:
    python3 05.scripts/12-site-candidates-province.py
"""

import csv
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
DERIVED = ROOT / "02.inputs" / "derived"
TILE_LAYER = ("https://services6.arcgis.com/ubm4tcTYICKBpist/ArcGIS/rest/"
              "services/LiDAR_BC_S3_Public/FeatureServer/4/query")
PAUSE = 0.25

SEV = {"T": "Trace", "L": "Light", "M": "Moderate", "S": "Severe",
       "V": "Very severe"}
HOST = {"B": "True fir unspecified", "BA": "Pacific silver fir",
        "BG": "Grand fir", "BL": "Subalpine fir"}


def get(url: str, tries: int = 4):
    delay = 2.0
    for _ in range(tries):
        try:
            req = urllib.request.Request(
                url, headers={"User-Agent": "woolly-adelgid-signatures/0.1"})
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.loads(r.read().decode())
        except Exception:
            time.sleep(delay)
            delay *= 2
    return None


def tiles_over(bbox):
    """Tile count and acquisition years intersecting one polygon envelope."""
    geom = {"xmin": bbox[0], "ymin": bbox[1], "xmax": bbox[2], "ymax": bbox[3],
            "spatialReference": {"wkid": 4326}}
    base = {"geometry": json.dumps(geom), "geometryType": "esriGeometryEnvelope",
            "inSR": "4326", "spatialRel": "esriSpatialRelIntersects",
            "where": "1=1", "f": "json"}
    cnt = get(TILE_LAYER + "?" + urllib.parse.urlencode(
        {**base, "returnCountOnly": "true"}))
    n = (cnt or {}).get("count", 0)
    if not n:
        return 0, []
    d = get(TILE_LAYER + "?" + urllib.parse.urlencode(
        {**base, "outFields": "year", "returnGeometry": "false",
         "resultRecordCount": 1000}))
    years = sorted({f["attributes"].get("year")
                    for f in (d or {}).get("features", [])
                    if f["attributes"].get("year")})
    return n, years


def ring_bbox(coords, acc):
    for c in coords:
        if isinstance(c[0], (int, float)):
            acc[0] = min(acc[0], c[0]); acc[1] = min(acc[1], c[1])
            acc[2] = max(acc[2], c[0]); acc[3] = max(acc[3], c[1])
        else:
            ring_bbox(c, acc)
    return acc


def main() -> None:
    src = DERIVED / "adelgid-iab-polygons.geojson"
    gj = json.loads(src.read_text())
    feats = gj["features"]
    print(f"{len(feats)} balsam woolly adelgid polygons province-wide")

    out = []
    for i, f in enumerate(feats, 1):
        p = f["properties"]
        bb = ring_bbox(f["geometry"]["coordinates"],
                       [180.0, 90.0, -180.0, -90.0])
        n, years = tiles_over(bb)
        yr = p.get("CAPTURE_YEAR")
        near = min(years, key=lambda y: abs(y - yr)) if years and yr else None
        out.append({
            "capture_year": yr,
            "severity": SEV.get(p.get("PEST_SEVERITY_CODE"),
                                p.get("PEST_SEVERITY_CODE")),
            "severity_code": p.get("PEST_SEVERITY_CODE"),
            "host": HOST.get(p.get("TREE_SPECIES_CODE"),
                             p.get("TREE_SPECIES_CODE") or "not recorded"),
            "host_code": p.get("TREE_SPECIES_CODE") or "",
            "area_ha": round(p.get("AREA_HA") or 0, 1),
            "lidar_tiles": n,
            "lidar_years": ";".join(str(y) for y in years),
            "nearest_lidar_year": near if near else "",
            "year_offset": abs(near - yr) if near and yr else "",
            "lon": round((bb[0] + bb[2]) / 2, 5),
            "lat": round((bb[1] + bb[3]) / 2, 5),
            "on_vancouver_island": bb[2] < -123.2 and bb[3] < 51.2,
        })
        if i % 25 == 0:
            print(f"  {i}/{len(feats)}", file=sys.stderr)
        time.sleep(PAUSE)

    out.sort(key=lambda r: (-r["lidar_tiles"], r["severity_code"]))
    path = DERIVED / "site-candidates-province.csv"
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out[0]))
        w.writeheader()
        w.writerows(out)

    ms = [r for r in out if r["severity_code"] in ("M", "S", "V")]
    ms_lidar = [r for r in ms if r["lidar_tiles"] > 0]
    print(f"\nwith lidar:                 {sum(1 for r in out if r['lidar_tiles'] > 0)} of {len(out)}")
    print(f"moderate or worse:          {len(ms)}")
    print(f"moderate or worse + lidar:  {len(ms_lidar)}")
    print(f"  of those, on the island:  {sum(1 for r in ms_lidar if r['on_vancouver_island'])}")
    print("wrote", path)


if __name__ == "__main__":
    main()
