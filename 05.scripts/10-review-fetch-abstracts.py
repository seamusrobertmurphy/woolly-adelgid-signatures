#!/usr/bin/env python3
"""Resolve identity of screen-pass records lacking an abstract.

Stage 3 of the review protocol requires the abstract to be read in full. 133 of the
721 screen-pass records carry no abstract in the Semantic Scholar bulk-search payload.
This script queries Semantic Scholar by DOI, then Crossref, and caches every response
to a JSONL file so an interrupted run resumes rather than restarts.

OpenAlex is not queried: it returned HTTP 429 throughout the session.
Written 2026-08-14.
"""

import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = "/Volumes/PortableSSD/Github/woolly-adelgid-signatures"
CACHE = os.path.join(ROOT, "02.inputs", "derived", "review-abstract-cache.jsonl")
UA = "woolly-adelgid-signatures/1.0 (mailto:seamusrobertmurphy@gmail.com)"


def get(url, tries=4):
    """GET with exponential backoff. Returns parsed JSON or None."""
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            if exc.code in (404, 400):
                return None
            time.sleep(2 ** attempt + 1)
        except Exception:
            time.sleep(2 ** attempt + 1)
    return None


def invert(inv):
    """Reconstruct text from an inverted index, as Crossref and OpenAlex sometimes give."""
    if not inv:
        return ""
    pos = {}
    for word, idxs in inv.items():
        for i in idxs:
            pos[i] = word
    return " ".join(pos[k] for k in sorted(pos))


def load_cache():
    seen = {}
    if os.path.exists(CACHE):
        with open(CACHE) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    rec = json.loads(line)
                except json.JSONDecodeError:
                    continue
                seen[rec["key"]] = rec
    return seen


def main():
    import pandas as pd

    screened = pd.read_csv(os.path.join(ROOT, "02.inputs", "derived", "review-screened.csv"))
    todo = screened[(screened.decision == "screen-pass") & (screened.no_abstract == True)]
    cache = load_cache()
    print(f"{len(todo)} records need resolving, {len(cache)} already cached", flush=True)

    with open(CACHE, "a") as out:
        for _, row in todo.iterrows():
            key = str(row.doi) if isinstance(row.doi, str) and row.doi else str(row.s2_id)
            if key in cache:
                continue
            rec = {
                "key": key,
                "doi": row.doi if isinstance(row.doi, str) else "",
                "s2_id": row.s2_id if isinstance(row.s2_id, str) else "",
                "title": row.title,
                "abstract": "",
                "source": "unresolved",
                "type": "",
            }

            if rec["doi"]:
                url = (
                    "https://api.semanticscholar.org/graph/v1/paper/DOI:"
                    + urllib.parse.quote(rec["doi"])
                    + "?fields=title,abstract,year,venue,publicationTypes,tldr"
                )
                js = get(url)
                if js:
                    if js.get("abstract"):
                        rec["abstract"] = js["abstract"]
                        rec["source"] = "s2"
                    if js.get("publicationTypes"):
                        rec["type"] = ";".join(js["publicationTypes"])
                    if not rec["abstract"] and js.get("tldr"):
                        rec["abstract"] = "TLDR: " + js["tldr"].get("text", "")
                        rec["source"] = "s2-tldr"
                time.sleep(1.2)

            if not rec["abstract"] and rec["doi"]:
                url = "https://api.crossref.org/works/" + urllib.parse.quote(rec["doi"])
                js = get(url)
                if js and js.get("message"):
                    msg = js["message"]
                    abstract = msg.get("abstract", "")
                    if abstract:
                        import re

                        abstract = re.sub(r"<[^>]+>", " ", abstract)
                        abstract = re.sub(r"\s+", " ", abstract).strip()
                        rec["abstract"] = abstract
                        rec["source"] = "crossref"
                    if not rec["type"]:
                        rec["type"] = msg.get("type", "")
                    rec["container"] = (msg.get("container-title") or [""])[0]
                    rec["subtitle"] = " ".join(msg.get("subtitle") or [])
                time.sleep(0.6)

            if not rec["abstract"] and rec["s2_id"]:
                url = (
                    "https://api.semanticscholar.org/graph/v1/paper/"
                    + rec["s2_id"]
                    + "?fields=title,abstract,year,venue,publicationTypes,tldr"
                )
                js = get(url)
                if js:
                    if js.get("abstract"):
                        rec["abstract"] = js["abstract"]
                        rec["source"] = "s2-id"
                    elif js.get("tldr"):
                        rec["abstract"] = "TLDR: " + js["tldr"].get("text", "")
                        rec["source"] = "s2-id-tldr"
                    if js.get("publicationTypes") and not rec["type"]:
                        rec["type"] = ";".join(js["publicationTypes"])
                time.sleep(1.2)

            out.write(json.dumps(rec) + "\n")
            out.flush()
            print(f"{rec['source']:14s} {str(rec['title'])[:70]}", flush=True)


if __name__ == "__main__":
    sys.exit(main())
