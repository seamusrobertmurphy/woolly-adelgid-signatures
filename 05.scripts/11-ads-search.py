#!/usr/bin/env python3
"""NASA ADS search strand for the scoping review.

Protocol: docs/science-superpowers/prior-work/2026-08-13-review-protocol.md
Access:   tasks/TASK-REQUEST-2026-08-14-ads-api-access.md

Why ADS is added to a review already running on Semantic Scholar and Crossref:
it supports cited-reference search through citations(doi:...) and
references(doi:...), which is the Web of Science capability neither of the other
two provides, and this project has no Web of Science subscription. Forward
citation chasing from Senf et al. (2015) is the single most valuable query here,
because that paper is the closest published work to this study's claim and
anything that supersedes it will cite it.

Scope caveat, to be stated in any methods description: ADS was not among the 28
systems evaluated by Gusenbauer and Haddaway (2020), so it carries no published
warrant as a principal search system for evidence synthesis. What is claimed here
is only that it passed the specific criteria tested directly on 2026-08-14:
Boolean set identities reconciled exactly for abs:"bark beetle" against
abs:"lidar" (3028 + 95623 - 34 = 98617 observed for OR; 3028 - 34 = 2994 observed
for NOT), ordered phrase search behaved (abs:"bark beetle" 3028 against
abs:"beetle bark" 8), and no intended content token collapsed to zero.

ADS indexes geophysics, atmospheric science and remote sensing well. It does not
index Canadian Forest Service or provincial technical reports, so the grey
literature that carries British Columbia survey methods will not appear here.

The token is read from ~/.ads/dev_key at point of use, never written to a file in
this tree, never printed, and never sent anywhere but api.adsabs.harvard.edu.

Usage:
    python3 05.scripts/11-ads-search.py
"""

import csv
import json
import sys
import time
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "02.inputs" / "derived"
KEY_PATH = Path.home() / ".ads" / "dev_key"
API = "https://api.adsabs.harvard.edu/v1/search/query"
FIELDS = "bibcode,doi,title,year,pub,abstract,citation_count"
PAUSE = 0.4

# Search strings. Every content token in these was tested individually on
# 2026-08-14 and returned a non-zero count, so none is silently collapsed.
QUERIES = [
    ("A1", 1, 'abs:"woolly adelgid" AND (abs:"remote sensing" OR abs:lidar OR '
              'abs:satellite OR abs:hyperspectral OR abs:radar)'),
    ("A2", 1, 'abs:"balsam woolly adelgid"'),
    ("A3", 2, '(abs:"disturbance agent" OR abs:"damage agent" OR '
              'abs:attribution OR abs:discrimination) AND abs:forest AND '
              '(abs:insect OR abs:beetle OR abs:defoliation)'),
    ("A4", 3, '(abs:lidar OR abs:"synthetic aperture radar" OR abs:backscatter '
              'OR abs:polarimetric) AND (abs:insect OR abs:beetle OR '
              'abs:defoliation OR abs:adelgid) AND abs:forest'),
    ("A5", 3, '(abs:lidar OR abs:"canopy structure") AND '
              '(abs:attribution OR abs:discrimination OR abs:"disturbance agent") '
              'AND abs:forest'),
    ("A6", 4, 'abs:"aerial detection survey" OR abs:"aerial overview survey" OR '
              '(abs:"forest health" AND abs:survey AND abs:accuracy)'),
]

# Cited-reference chasing. This is what ADS is here for. Anything that has
# superseded these will cite them.
SEEDS = {
    "10.1016/j.rse.2015.09.019": "Senf 2015, insect-vs-insect attribution",
    "10.3390/f14071357": "Campbell 2023, BWA severity mapping",
    "10.1002/ecs2.3156": "Atkins 2020, structural differentiation",
    "10.1016/j.foreco.2018.08.020": "Coleman 2018, survey accuracy",
}


def token() -> str:
    if not KEY_PATH.exists():
        sys.exit(f"no ADS token at {KEY_PATH}")
    return KEY_PATH.read_text().strip()


def search(q: str, rows: int = 2000):
    """Return (records, numFound). Paged; ADS caps rows per request at 2000."""
    tok = token()
    got, start, total = [], 0, None
    while True:
        url = API + "?" + urllib.parse.urlencode(
            {"q": q, "rows": min(rows, 2000), "start": start, "fl": FIELDS})
        req = urllib.request.Request(
            url, headers={"Authorization": f"Bearer {tok}",
                          "User-Agent": "woolly-adelgid-signatures/0.1"})
        with urllib.request.urlopen(req, timeout=90) as r:
            d = json.loads(r.read().decode())
        resp = d["response"]
        if total is None:
            total = resp["numFound"]
        got += resp["docs"]
        start += len(resp["docs"])
        time.sleep(PAUSE)
        if start >= total or not resp["docs"] or start >= 6000:
            break
    return got, total


def parse(d: dict, strand: str) -> dict:
    return {
        "strand": strand,
        "bibcode": d.get("bibcode", ""),
        "doi": (d.get("doi") or [""])[0].lower(),
        "year": d.get("year", ""),
        "title": (d.get("title") or [""])[0].strip(),
        "venue": d.get("pub", ""),
        "citations": d.get("citation_count", 0),
        "abstract": (d.get("abstract") or "")[:2500],
    }


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    records, log = {}, []

    def add(rec):
        key = rec["doi"] or rec["bibcode"]
        if key and key not in records:
            records[key] = rec

    print("ADS: topical strands")
    for qid, rq, q in QUERIES:
        try:
            docs, total = search(q)
        except Exception as exc:
            print(f"  {qid}: FAILED {exc}", file=sys.stderr)
            log.append({"strand": qid, "research_question": rq, "kind": "search",
                        "retrieved": 0, "total": "", "query": q})
            continue
        for d in docs:
            add(parse(d, qid))
        print(f"  {qid} (RQ{rq}): {len(docs):5d} of {total}")
        log.append({"strand": qid, "research_question": rq, "kind": "search",
                    "retrieved": len(docs), "total": total, "query": q})

    print("\nADS: cited-reference chasing")
    for doi, label in SEEDS.items():
        for kind in ("citations", "references"):
            q = f"{kind}(doi:{doi})"
            try:
                docs, total = search(q)
            except Exception as exc:
                print(f"  {label} {kind}: FAILED {exc}", file=sys.stderr)
                continue
            for d in docs:
                add(parse(d, f"{kind}:{label.split(',')[0]}"))
            print(f"  {label[:34]:36} {kind:11} {len(docs):5d} of {total}")
            log.append({"strand": label, "research_question": "", "kind": kind,
                        "retrieved": len(docs), "total": total, "query": q})

    rows = sorted(records.values(), key=lambda r: -(r["citations"] or 0))
    with open(OUT / "ads-records.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["strand", "citations", "year",
                                           "title", "venue", "doi", "bibcode",
                                           "abstract"], extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    with open(OUT / "ads-search-log.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["strand", "research_question", "kind",
                                           "retrieved", "total", "query"])
        w.writeheader()
        w.writerows(log)

    print(f"\nunique ADS records: {len(rows)}")
    print("wrote", OUT / "ads-records.csv")


if __name__ == "__main__":
    main()
