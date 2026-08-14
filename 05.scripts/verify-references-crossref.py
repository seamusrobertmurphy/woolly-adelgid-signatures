#!/usr/bin/env python3
"""Verify each literature PDF against CrossRef and emit BibTeX from the registry.

Literature protocol, CLAUDE.md: verify every bib entry via CrossRef before it
enters references.bib, and take the entry from the registry rather than from
memory. This script queries CrossRef by bibliographic title, prints the best
match with its similarity score so a wrong match is visible rather than silently
accepted, and fetches formal BibTeX by DOI content negotiation.

A match below MIN_SCORE is reported as UNVERIFIED and is not written. Hand
entry is then required, flagged as such in a comment, per the protocol.

Usage:
    python3 05.scripts/verify-references-crossref.py            # report only
    python3 05.scripts/verify-references-crossref.py --write    # also write .bib
"""

import re
import sys
import time
import urllib.parse
import urllib.request
from difflib import SequenceMatcher
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIT = ROOT / "04.references" / "literature"
BIB = ROOT / "04.references" / "references.bib"

# CrossRef asks for a contact address in the User-Agent so they can get in touch
# about badly behaved scripts. This is the polite pool.
MAILTO = "seamusrobertmurphy@gmail.com"
UA = f"woolly-adelgid-signatures/0.1 (mailto:{MAILTO})"

# Title similarity below which a CrossRef hit is not trusted as the same work.
MIN_SCORE = 0.60


def filename_to_title(stem: str) -> str:
    """Strip the 'Author YEAR ' prefix our filenames carry, leaving the title."""
    return re.sub(r"^.*?\b(19|20)\d{2}\s+", "", stem).strip()


def fetch(url: str, accept: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": accept})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return resp.read().decode("utf-8", errors="replace")


def query_crossref(title: str) -> dict | None:
    url = (
        "https://api.crossref.org/works?rows=3&select=DOI,title,author,"
        "container-title,issued,volume,page,type&query.bibliographic="
        + urllib.parse.quote(title)
    )
    import json

    items = json.loads(fetch(url, "application/json"))["message"]["items"]
    best, best_score = None, 0.0
    for it in items:
        cand = (it.get("title") or [""])[0]
        score = SequenceMatcher(None, title.lower(), cand.lower()).ratio()
        if score > best_score:
            best, best_score = it, score
    if best is None:
        return None
    best["_score"] = best_score
    return best


def main() -> None:
    write = "--write" in sys.argv
    pdfs = sorted(p for p in LIT.glob("*.pdf") if not p.name.startswith("._"))
    entries, unverified = [], []

    for pdf in pdfs:
        title = filename_to_title(pdf.stem)
        try:
            hit = query_crossref(title)
        except Exception as exc:
            print(f"ERROR      {pdf.stem[:60]}: {exc}")
            unverified.append(pdf.stem)
            continue
        time.sleep(0.5)  # courtesy to the public API

        if hit is None or hit["_score"] < MIN_SCORE:
            score = f"{hit['_score']:.2f}" if hit else "none"
            print(f"UNVERIFIED {score}  {pdf.stem[:60]}")
            unverified.append(pdf.stem)
            continue

        doi = hit["DOI"]
        journal = (hit.get("container-title") or ["?"])[0]
        year = hit.get("issued", {}).get("date-parts", [[None]])[0][0]
        print(f"ok   {hit['_score']:.2f}  {doi}")
        print(f"           {(hit.get('title') or [''])[0][:95]}")
        print(f"           {journal}, {year}, type={hit.get('type')}")

        if write:
            try:
                bib = fetch(f"https://doi.org/{doi}", "application/x-bibtex")
                entries.append(bib.strip())
            except Exception as exc:
                print(f"           BibTeX fetch failed: {exc}")
                unverified.append(pdf.stem)
            time.sleep(0.5)

    if write and entries:
        header = (
            "% references.bib\n"
            "% Every entry below was fetched from CrossRef by DOI content\n"
            "% negotiation using 05.scripts/verify-references-crossref.py.\n"
            "% Do not hand-edit an entry without noting why in a comment.\n"
            "% Zotero mints its own keys; reconcile before hand-writing any @keys.\n\n"
        )
        BIB.write_text(header + "\n\n".join(entries) + "\n")
        print(f"\nwrote {len(entries)} entries to {BIB}")

    if unverified:
        print("\nUNVERIFIED, need hand entry and a flag comment:")
        for u in unverified:
            print("  -", u)


if __name__ == "__main__":
    main()
