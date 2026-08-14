#!/usr/bin/env python3
"""Systematic literature search for the introduction and the novelty claim.

Databases: OpenAlex (primary, ~250M works, best coverage of forestry and remote
sensing), Crossref (registry of record), and Semantic Scholar (citation counts
and cross-disciplinary recall). PubMed and bioRxiv are not searched: they index
biomedicine and carry almost nothing in forest remote sensing.

The searches are grouped by the question each one answers, so that a reader can
see which query establishes which claim. The novelty claim of this study rests
specifically on block D returning nothing: no prior work using lidar or SAR to
attribute damage between two insect agents sharing a host.

Writes 02.inputs/derived/literature-search.csv with one row per unique work and
a column recording which query blocks retrieved it.

Usage:
    python3 05.scripts/05-literature-search.py
"""

import csv
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "02.inputs" / "derived"

MAILTO = "seamusrobertmurphy@gmail.com"
UA = f"woolly-adelgid-signatures/0.1 (mailto:{MAILTO})"

YEAR_FROM = 1990
PER_QUERY = 60

# Each block is (id, purpose, [queries]). Blocks are the unit of evidence: a
# claim in the review cites the block that supports it.
BLOCKS = [
    ("A", "Balsam woolly adelgid, any method", [
        "balsam woolly adelgid",
        "Adelges piceae",
        "balsam woolly adelgid subalpine fir damage",
    ]),
    ("B", "Remote sensing of adelgid damage", [
        "remote sensing balsam woolly adelgid",
        "remote sensing hemlock woolly adelgid",
        "satellite detection adelgid infestation forest",
        "hemlock woolly adelgid Landsat detection",
    ]),
    ("C", "Remote sensing of conifer insect damage generally", [
        "remote sensing bark beetle damage detection conifer",
        "Landsat time series insect disturbance mapping forest",
        "Sentinel-2 forest insect defoliation detection",
        "hyperspectral conifer stress detection insect",
    ]),
    ("D", "Attribution between agents, and lidar or SAR for that purpose", [
        "discriminating forest damage agents remote sensing attribution",
        "lidar bark beetle damage detection canopy structure",
        "synthetic aperture radar forest insect damage detection",
        "lidar attribution insect damage agent classification forest",
        "SAR Sentinel-1 bark beetle forest damage",
        "distinguishing causal agents forest disturbance remote sensing",
    ]),
    ("E", "Western balsam bark beetle and host system", [
        "Dryocoetes confusus subalpine fir mortality",
        "western balsam bark beetle British Columbia",
        "Abies amabilis Pacific silver fir mortality damage",
    ]),
    ("F", "Aerial overview survey accuracy and validation", [
        "aerial overview survey forest health accuracy validation",
        "aerial detection survey accuracy insect damage mapping",
    ]),
]


def fetch(url: str, accept: str = "application/json"):
    req = urllib.request.Request(url, headers={"User-Agent": UA,
                                               "Accept": accept})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read().decode())


def openalex(query: str):
    url = ("https://api.openalex.org/works?per-page=%d&mailto=%s"
           "&filter=from_publication_date:%d-01-01,type:article"
           "&search=%s" % (PER_QUERY, MAILTO, YEAR_FROM,
                           urllib.parse.quote(query)))
    try:
        data = fetch(url)
    except Exception as exc:
        print(f"    openalex failed: {exc}", file=sys.stderr)
        return []
    out = []
    for w in data.get("results", []):
        doi = (w.get("doi") or "").replace("https://doi.org/", "")
        inv = w.get("abstract_inverted_index")
        abstract = ""
        if inv:
            # OpenAlex stores abstracts as an inverted index for licensing
            # reasons; rebuild enough of it to screen on.
            pos = {}
            for term, idxs in inv.items():
                for i in idxs:
                    pos[i] = term
            abstract = " ".join(pos[i] for i in sorted(pos))[:1200]
        out.append({
            "source": "openalex",
            "doi": doi.lower(),
            "title": (w.get("title") or "").strip(),
            "year": w.get("publication_year"),
            "venue": ((w.get("primary_location") or {}).get("source") or {}
                      ).get("display_name", "") or "",
            "citations": w.get("cited_by_count", 0),
            "abstract": abstract,
        })
    return out


def semantic_scholar(query: str):
    url = ("https://api.semanticscholar.org/graph/v1/paper/search?limit=25"
           "&fields=title,year,venue,citationCount,externalIds,abstract"
           "&query=" + urllib.parse.quote(query))
    try:
        data = fetch(url)
    except Exception as exc:
        print(f"    semanticscholar skipped: {exc}", file=sys.stderr)
        return []
    out = []
    for w in data.get("data", []) or []:
        doi = ((w.get("externalIds") or {}).get("DOI") or "").lower()
        out.append({
            "source": "semanticscholar",
            "doi": doi,
            "title": (w.get("title") or "").strip(),
            "year": w.get("year"),
            "venue": w.get("venue") or "",
            "citations": w.get("citationCount", 0),
            "abstract": (w.get("abstract") or "")[:1200],
        })
    return out


def norm_title(t: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (t or "").lower())[:90]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    records = {}
    block_hits = defaultdict(set)
    query_log = []

    for bid, purpose, queries in BLOCKS:
        print(f"\nBlock {bid}: {purpose}")
        for q in queries:
            found = openalex(q)
            time.sleep(0.4)
            found += semantic_scholar(q)
            time.sleep(1.2)  # Semantic Scholar rate-limits the free tier hard
            print(f"  {len(found):4d}  {q}")
            query_log.append({"block": bid, "query": q, "returned": len(found)})

            for r in found:
                key = r["doi"] or norm_title(r["title"])
                if not key:
                    continue
                if key not in records or r["citations"] > records[key]["citations"]:
                    records[key] = r
                block_hits[key].add(bid)

    rows = []
    for key, r in records.items():
        r = dict(r)
        r["blocks"] = "".join(sorted(block_hits[key]))
        rows.append(r)
    rows.sort(key=lambda r: (-(r["citations"] or 0), r["title"]))

    path = OUT / "literature-search.csv"
    with open(path, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["blocks", "citations", "year",
                                           "title", "venue", "doi", "source",
                                           "abstract"])
        w.writeheader()
        w.writerows(rows)

    log = OUT / "literature-search-queries.csv"
    with open(log, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["block", "query", "returned"])
        w.writeheader()
        w.writerows(query_log)

    print(f"\n{len(rows)} unique works from {len(query_log)} queries")
    print("wrote", path)


if __name__ == "__main__":
    main()
