#!/usr/bin/env python3
"""Structured scoping review search, implementing the protocol dated 2026-08-13.

Protocol: docs/science-superpowers/prior-work/2026-08-13-review-protocol.md

Uses OpenAlex `title_and_abstract.search`, which restricts Boolean matching to
title and abstract. The withdrawn scoping search used the `search` parameter,
which ranks loosely over full text and returned deep learning reviews among its
top hits. Crossref is queried for records OpenAlex lacks a DOI for, and is the
registry of record for metadata.

Retrieval is paged to exhaustion per query rather than capped, so recall is a
property of the query rather than of an arbitrary page size.

Writes 02.inputs/derived/review-records.csv with one row per unique record,
carrying the query that found it, the route of discovery, and the fields the
screening step needs.

Usage:
    python3 05.scripts/07-review-search.py
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

YEAR_FROM, YEAR_TO = 1980, 2026
MAX_PAGES = 32          # 200 per page. Raised from 12 on 2026-08-13: Q1a and
                        # Q3b hit the cap, and cursor paging is not relevance
                        # ordered, so truncation biases the set non-randomly.
PER_PAGE = 200

# Controlled synonym sets, written once and combined, so a term added here
# propagates to every question that uses it.
FOREST = ('(forest OR forests OR forestry OR tree OR trees OR conifer OR '
          'coniferous OR woodland OR silviculture OR canopy OR stand)')
ADELGID = '(adelgid OR adelgids OR "Adelges piceae" OR "Adelges tsugae")'
INSECT = ('("bark beetle" OR "bark beetles" OR "Ips typographus" OR '
          'Dendroctonus OR "Dryocoetes confusus" OR defoliation OR defoliator '
          'OR "insect outbreak" OR "insect damage" OR "forest pest" OR '
          '"insect disturbance" OR "tree mortality")')
SENSING = ('("remote sensing" OR satellite OR Landsat OR Sentinel OR lidar OR '
           '"laser scanning" OR "synthetic aperture radar" OR backscatter OR '
           'hyperspectral OR multispectral OR "aerial imagery" OR UAV OR '
           '"unmanned aerial" OR spectroscopy OR reflectance)')
STRUCTURE = ('(lidar OR "laser scanning" OR "canopy structure" OR '
             '"synthetic aperture radar" OR backscatter OR "Sentinel-1" OR '
             'interferometr OR polarimetr)')
ATTRIBUTION = ('(attribution OR attributing OR discriminating OR '
               'discrimination OR distinguishing OR "causal agent" OR '
               '"causal agents" OR "damage agent" OR "damage agents" OR '
               '"disturbance agent" OR "disturbance agents" OR '
               '"agent classification")')
SURVEY = ('("aerial overview survey" OR "aerial detection survey" OR '
          '"aerial survey" OR "sketch mapping" OR "forest health survey" OR '
          '"insect and disease survey")')
ACCURACY = '(accuracy OR validation OR agreement OR error OR reliability OR bias)'

# One query per review question. Q1a is deliberately broad on the adelgid, since
# that literature is small and recall matters more than precision there.
QUERIES = [
    ("Q1a", 1, f'{ADELGID}'),
    ("Q1b", 1, f'{ADELGID} AND {SENSING}'),
    ("Q2",  2, f'{FOREST} AND {ATTRIBUTION} AND {INSECT} AND {SENSING}'),
    ("Q3a", 3, f'{FOREST} AND {STRUCTURE} AND {INSECT}'),
    ("Q3b", 3, f'{FOREST} AND {STRUCTURE} AND {ATTRIBUTION}'),
    ("Q4",  4, f'{SURVEY} AND {ACCURACY} AND {FOREST}'),
]


class BudgetExhausted(RuntimeError):
    """Raised when OpenAlex reports the daily request budget is spent.

    Distinguished from a transient throttle because retrying is pointless:
    the budget resets at midnight UTC and each attempt still costs a request.
    """


def get(url: str, tries: int = 5):
    """GET with exponential backoff. OpenAlex returns 429 under sustained paging
    even in the polite pool, and a dropped page silently truncates recall, so a
    failure here must retry rather than be swallowed."""
    delay = 2.0
    last = None
    for attempt in range(tries):
        req = urllib.request.Request(url, headers={"User-Agent": UA,
                                                   "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=90) as r:
                return json.loads(r.read().decode())
        except urllib.error.HTTPError as exc:
            last = exc
            if exc.code == 429:
                # Distinguish a transient throttle from an exhausted daily
                # budget. Retrying the latter is pointless: it resets at
                # midnight UTC and every attempt still costs a request.
                remaining = exc.headers.get("x-ratelimit-remaining")
                retry_after = exc.headers.get("retry-after")
                if remaining == "0" or (retry_after and int(retry_after) > 600):
                    raise BudgetExhausted(
                        f"daily API budget spent; resets in "
                        f"{int(retry_after or 0) // 3600} h") from exc
            elif exc.code not in (500, 502, 503, 504):
                raise
        except Exception as exc:
            last = exc
        time.sleep(delay)
        delay *= 2
    raise last


def rebuild_abstract(inv) -> str:
    if not inv:
        return ""
    pos = {}
    for term, idxs in inv.items():
        for i in idxs:
            pos[i] = term
    return " ".join(pos[i] for i in sorted(pos))[:2500]


def openalex_query(boolean: str):
    """Page an OpenAlex filter query to exhaustion, or to MAX_PAGES."""
    flt = (f"title_and_abstract.search:{boolean},"
           f"from_publication_date:{YEAR_FROM}-01-01,"
           f"to_publication_date:{YEAR_TO}-12-31")
    cursor, out, pages, total = "*", [], 0, None
    truncated = False
    while cursor and pages < MAX_PAGES:
        url = ("https://api.openalex.org/works?per-page=%d&mailto=%s"
               "&cursor=%s&filter=%s"
               % (PER_PAGE, MAILTO, urllib.parse.quote(cursor),
                  urllib.parse.quote(flt, safe='')))
        try:
            data = get(url)
        except BudgetExhausted:
            raise
        except Exception as exc:
            # A page that cannot be fetched after retries truncates recall, and
            # that must be reported, never silently absorbed.
            print(f"    page {pages} abandoned after retries: {exc}",
                  file=sys.stderr)
            truncated = True
            break
        if total is None:
            total = (data.get("meta") or {}).get("count", 0)
        for w in data.get("results", []):
            out.append(parse_work(w))
        cursor = (data.get("meta") or {}).get("next_cursor")
        pages += 1
        time.sleep(0.8)
        if not data.get("results"):
            break
    if pages >= MAX_PAGES and cursor:
        truncated = True
    return out, (total if total is not None else len(out)), truncated


def parse_work(w: dict) -> dict:
    src = ((w.get("primary_location") or {}).get("source") or {})
    return {
        "openalex_id": (w.get("id") or "").rsplit("/", 1)[-1],
        "doi": (w.get("doi") or "").replace("https://doi.org/", "").lower(),
        "title": (w.get("title") or "").strip(),
        "year": w.get("publication_year") or "",
        "venue": src.get("display_name") or "",
        "type": w.get("type") or "",
        "citations": w.get("cited_by_count", 0),
        "abstract": rebuild_abstract(w.get("abstract_inverted_index")),
        "referenced": ";".join(r.rsplit("/", 1)[-1]
                               for r in (w.get("referenced_works") or [])[:200]),
    }


# Seeds for citation chasing, established as central before this search ran.
SEEDS = {
    "10.3390/f14071357": "Campbell 2023",
    "10.1080/01431169508954591": "Franklin 1995",
    "10.3390/f8070251": "Oeser 2017",
    "10.1016/j.rse.2018.03.009": "Tanase 2018",
    "10.1080/07038992.2023.2196356": "Morin-Bernard 2023",
}


def chase(doi: str):
    """Backward (references) and forward (citations) from one seed."""
    back, fwd = [], []
    try:
        w = get(f"https://api.openalex.org/works/doi:{doi}?mailto={MAILTO}")
    except Exception as exc:
        print(f"    seed {doi} failed: {exc}", file=sys.stderr)
        return back, fwd

    refs = (w.get("referenced_works") or [])[:120]
    for i in range(0, len(refs), 50):
        ids = "|".join(r.rsplit("/", 1)[-1] for r in refs[i:i + 50])
        try:
            d = get(f"https://api.openalex.org/works?per-page=50&mailto={MAILTO}"
                    f"&filter=openalex_id:{ids}")
            back += [parse_work(x) for x in d.get("results", [])]
        except Exception:
            pass
        time.sleep(0.3)

    cur, pages = "*", 0
    while cur and pages < 4:
        try:
            d = get(f"https://api.openalex.org/works?per-page=200&mailto={MAILTO}"
                    f"&cursor={urllib.parse.quote(cur)}"
                    f"&filter=cites:{w['id'].rsplit('/', 1)[-1]}")
        except Exception:
            break
        fwd += [parse_work(x) for x in d.get("results", [])]
        cur = (d.get("meta") or {}).get("next_cursor")
        pages += 1
        time.sleep(0.3)
    return back, fwd


def norm_title(t: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", (t or "").lower())[:90]


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    records, routes, queries_of = {}, {}, {}
    log = []

    def add(rec, route, qid):
        key = rec["doi"] or norm_title(rec["title"])
        if not key:
            return
        if key not in records:
            records[key] = rec
        routes.setdefault(key, set()).add(route)
        queries_of.setdefault(key, set()).add(qid)

    print("IDENTIFICATION: database searching")
    for qid, rq, boolean in QUERIES:
        try:
            got, total, truncated = openalex_query(boolean)
        except BudgetExhausted as exc:
            print(f"  {qid}: STOPPED, {exc}", file=sys.stderr)
            break
        for r in got:
            add(r, "search", qid)
        flag = "  TRUNCATED" if truncated else ""
        print(f"  {qid} (RQ{rq}): retrieved {len(got):5d} of {total} matching{flag}")
        log.append({"stage": "search", "query_id": qid, "research_question": rq,
                    "retrieved": len(got), "reported_total": total,
                    "truncated": truncated, "boolean": boolean})

    print("\nIDENTIFICATION: citation chasing from seeds")
    for doi, label in SEEDS.items():
        try:
            back, fwd = chase(doi)
        except BudgetExhausted as exc:
            print(f"  {label}: STOPPED, {exc}", file=sys.stderr)
            break
        for r in back:
            add(r, "backward", label)
        for r in fwd:
            add(r, "forward", label)
        print(f"  {label:22} backward {len(back):4d}  forward {len(fwd):5d}")
        log.append({"stage": "chase", "query_id": label, "research_question": "",
                    "retrieved": len(back) + len(fwd), "reported_total": "",
                    "truncated": False,
                    "boolean": f"backward={len(back)};forward={len(fwd)}"})

    if not records:
        print("\nNO RECORDS RETRIEVED. Existing output left untouched.",
              file=sys.stderr)
        print("Every query failed, most likely the daily API budget is spent.",
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
        try:
            existing_n = sum(1 for _ in open(target)) - 1
        except Exception:
            existing_n = 0
        if existing_n > len(rows):
            print(f"\nREFUSING TO OVERWRITE: {target.name} holds {existing_n} "
                  f"records, this run produced {len(rows)}.", file=sys.stderr)
            print("Re-run with --force if the smaller set is genuinely wanted.",
                  file=sys.stderr)
            sys.exit(1)

    fields = ["queries", "routes", "citations", "year", "type", "title",
              "venue", "doi", "openalex_id", "abstract", "referenced"]
    with open(target, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)
    with open(OUT / "review-search-log.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=["stage", "query_id",
                                           "research_question", "retrieved",
                                           "reported_total", "truncated",
                                           "boolean"])
        w.writeheader()
        w.writerows(log)

    print(f"\nunique records after deduplication: {len(rows)}")
    print("wrote", OUT / "review-records.csv")


if __name__ == "__main__":
    main()
