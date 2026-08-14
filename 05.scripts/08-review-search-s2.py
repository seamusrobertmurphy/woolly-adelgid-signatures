#!/usr/bin/env python3
"""Scoping review search on Semantic Scholar, implementing the 2026-08-13 protocol.

Protocol: docs/science-superpowers/prior-work/2026-08-13-review-protocol.md

Deviation, recorded 2026-08-13: OpenAlex was the planned primary database. Its
free tier is metered at 1000 requests per day and was exhausted by paging two
overly broad queries to exhaustion. Semantic Scholar's bulk search endpoint is
substituted. It is a better fit regardless: it accepts Boolean syntax, matches
on title and abstract, and returns complete result sets of a few hundred rather
than OpenAlex's several thousand fuzzy expansions. On the same adelgid concept
OpenAlex reported 5387 matches where Semantic Scholar reports 46.

Google Scholar was considered and rejected. It has no public API, its terms
prohibit automated access, and scraping it would make the search irreproducible.

Boolean syntax on the bulk endpoint: `+` is AND, `|` is OR, `-` is NOT, double
quotes delimit phrases. Crossref is queried afterwards to confirm metadata for
records carrying a DOI.

Writes 02.inputs/derived/review-records.csv and review-search-log.csv.

Usage:
    python3 05.scripts/08-review-search-s2.py
"""

import csv
import json
import re
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "02.inputs" / "derived"
MAILTO = "seamusrobertmurphy@gmail.com"
UA = f"woolly-adelgid-signatures/0.1 (mailto:{MAILTO})"

BULK = "https://api.semanticscholar.org/graph/v1/paper/search/bulk"
FIELDS = ("title,year,abstract,citationCount,externalIds,venue,"
          "publicationTypes,referenceCount")
PAUSE = 4.0          # unauthenticated shared pool; pace deliberately
YEAR_FROM, YEAR_TO = 1980, 2026

FOREST = '(forest | forests | forestry | tree | trees | conifer | coniferous | woodland | canopy)'
ADELGID = '(adelgid | adelgids | "Adelges piceae" | "Adelges tsugae")'
INSECT = ('("bark beetle" | "bark beetles" | "Ips typographus" | Dendroctonus | '
          '"Dryocoetes confusus" | defoliation | defoliator | "insect outbreak" | '
          '"insect damage" | "forest pest" | "tree mortality")')
SENSING = ('("remote sensing" | satellite | Landsat | Sentinel | lidar | '
           '"laser scanning" | "synthetic aperture radar" | backscatter | '
           'hyperspectral | multispectral | "aerial imagery" | UAV | '
           '"unmanned aerial" | spectroscopy | reflectance)')
STRUCTURE = ('(lidar | "laser scanning" | "canopy structure" | '
             '"synthetic aperture radar" | backscatter | "Sentinel-1" | '
             'interferometry | polarimetry)')
ATTRIBUTION = ('(attribution | attributing | discriminating | discrimination | '
               'distinguishing | "causal agent" | "causal agents" | '
               '"damage agent" | "damage agents" | "disturbance agent" | '
               '"disturbance agents" | "agent classification")')
SURVEY = ('("aerial overview survey" | "aerial detection survey" | '
          '"aerial survey" | "sketch mapping" | "forest health survey" | '
          '"insect and disease survey")')
ACCURACY = '(accuracy | validation | agreement | error | reliability)'

QUERIES = [
    ("Q1a", 1, f'{ADELGID} + {FOREST}'),
    ("Q1b", 1, f'{ADELGID} + {SENSING}'),
    ("Q2",  2, f'{FOREST} + {ATTRIBUTION} + {INSECT} + {SENSING}'),
    ("Q3a", 3, f'{FOREST} + {STRUCTURE} + {INSECT}'),
    ("Q3b", 3, f'{FOREST} + {STRUCTURE} + {ATTRIBUTION}'),
    ("Q4",  4, f'{SURVEY} + {ACCURACY} + {FOREST}'),
]

SEEDS = {
    "10.3390/f14071357": "Campbell 2023",
    "10.1080/01431169508954591": "Franklin 1995",
    "10.3390/f8070251": "Oeser 2017",
    "10.1016/j.rse.2018.03.009": "Tanase 2018",
    "10.1080/07038992.2023.2196356": "Morin-Bernard 2023",
}


def get(url: str, tries: int = 5):
    delay, last = 5.0, None
    for _ in range(tries):
        req = urllib.request.Request(url, headers={"User-Agent": UA,
                                                   "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.loads(r.read().decode())
        except Exception as exc:
            last = exc
            time.sleep(delay)
            delay *= 1.8
    raise last


def parse(p: dict) -> dict:
    ext = p.get("externalIds") or {}
    return {
        "s2_id": p.get("paperId", ""),
        "doi": (ext.get("DOI") or "").lower(),
        "title": (p.get("title") or "").strip(),
        "year": p.get("year") or "",
        "venue": p.get("venue") or "",
        "type": ";".join(p.get("publicationTypes") or []),
        "citations": p.get("citationCount", 0),
        "abstract": (p.get("abstract") or "")[:2500],
    }


def bulk(query: str):
    """Page the bulk endpoint by continuation token to exhaustion."""
    out, token, pages, total = [], None, 0, None
    while pages < 20:
        params = {"query": query, "fields": FIELDS,
                  "year": f"{YEAR_FROM}-{YEAR_TO}"}
        if token:
            params["token"] = token
        d = get(BULK + "?" + urllib.parse.urlencode(params))
        if total is None:
            total = d.get("total", 0)
        out += [parse(p) for p in (d.get("data") or [])]
        token = d.get("token")
        pages += 1
        time.sleep(PAUSE)
        if not token:
            break
    return out, total, bool(token)


def chase(doi: str):
    """Backward and forward citation chasing from one seed."""
    back, fwd = [], []
    for direction, store in (("references", back), ("citations", fwd)):
        off = 0
        while off < 600:
            url = (f"https://api.semanticscholar.org/graph/v1/paper/DOI:{doi}/"
                   f"{direction}?fields={FIELDS}&limit=100&offset={off}")
            try:
                d = get(url)
            except Exception as exc:
                print(f"    {direction} stopped at offset {off}: {exc}",
                      file=sys.stderr)
                break
            data = d.get("data") or []
            key = "citedPaper" if direction == "references" else "citingPaper"
            store += [parse(x[key]) for x in data if x.get(key)]
            if len(data) < 100:
                break
            off += 100
            time.sleep(PAUSE)
        time.sleep(PAUSE)
    return back, fwd


def norm_title(t: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (t or "").lower())[:90]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    records, routes, queries_of, log = {}, {}, {}, []

    def add(rec, route, qid):
        key = rec["doi"] or norm_title(rec["title"])
        if not key:
            return
        records.setdefault(key, rec)
        routes.setdefault(key, set()).add(route)
        queries_of.setdefault(key, set()).add(qid)

    print("IDENTIFICATION: database searching (Semantic Scholar bulk)")
    for qid, rq, q in QUERIES:
        try:
            got, total, truncated = bulk(q)
        except Exception as exc:
            print(f"  {qid}: FAILED {exc}", file=sys.stderr)
            log.append({"stage": "search", "query_id": qid,
                        "research_question": rq, "retrieved": 0,
                        "reported_total": "", "truncated": True, "query": q})
            continue
        for r in got:
            add(r, "search", qid)
        flag = "   TRUNCATED" if truncated else ""
        print(f"  {qid} (RQ{rq}): {len(got):5d} of {total} matching{flag}")
        log.append({"stage": "search", "query_id": qid, "research_question": rq,
                    "retrieved": len(got), "reported_total": total,
                    "truncated": truncated, "query": q})

    print("\nIDENTIFICATION: citation chasing from seeds")
    for doi, label in SEEDS.items():
        back, fwd = chase(doi)
        for r in back:
            add(r, "backward", label)
        for r in fwd:
            add(r, "forward", label)
        print(f"  {label:22} backward {len(back):4d}  forward {len(fwd):5d}")
        log.append({"stage": "chase", "query_id": label, "research_question": "",
                    "retrieved": len(back) + len(fwd), "reported_total": "",
                    "truncated": False,
                    "query": f"backward={len(back)};forward={len(fwd)}"})

    if not records:
        print("\nNO RECORDS RETRIEVED. Existing output left untouched.",
              file=sys.stderr)
        sys.exit(1)

    rows = []
    for key, r in records.items():
        r = dict(r)
        r["routes"] = ";".join(sorted(routes[key]))
        r["queries"] = ";".join(sorted(queries_of[key]))
        rows.append(r)
    rows.sort(key=lambda r: -(r["citations"] or 0))

    target = OUT / "review-records.csv"
    if target.exists() and "--force" not in sys.argv:
        existing = max(sum(1 for _ in open(target)) - 1, 0)
        if existing > len(rows):
            print(f"\nREFUSING TO OVERWRITE: {target.name} holds {existing} "
                  f"records, this run produced {len(rows)}.", file=sys.stderr)
            sys.exit(1)

    fields = ["queries", "routes", "citations", "year", "type", "title",
              "venue", "doi", "s2_id", "abstract"]
    with open(target, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    with open(OUT / "review-search-log.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["stage", "query_id",
                                           "research_question", "retrieved",
                                           "reported_total", "truncated",
                                           "query"])
        w.writeheader()
        w.writerows(log)

    print(f"\nunique records after deduplication: {len(rows)}")
    print("wrote", target)


if __name__ == "__main__":
    main()
