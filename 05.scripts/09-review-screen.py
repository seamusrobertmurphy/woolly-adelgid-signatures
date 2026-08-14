#!/usr/bin/env python3
"""Screen the retrieved records against the protocol's criteria.

Protocol: docs/science-superpowers/prior-work/2026-08-13-review-protocol.md

Applies only the mechanical criteria, and says so per record. A criterion is
mechanical when it can be decided from the presence or absence of vocabulary,
for example whether a record concerns a forest at all. Criteria requiring
judgement, for example whether a paper genuinely attributes damage to an agent
rather than merely detecting it, are left to manual reading of the survivors and
are recorded separately.

The point of separating them is that a reader can see which decisions a script
made and which a person made, rather than being asked to trust a single opaque
"included" flag.

Exclusion reasons are those fixed in the protocol: not-forest, no-agent,
no-sensing, off-topic, not-research.

Writes 02.inputs/derived/review-screened.csv with a decision and reason per
record, and prints the counts needed for a PRISMA-style flow diagram.

Usage:
    python3 05.scripts/09-review-screen.py
"""

import csv
import re
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "02.inputs" / "derived"

FOREST = re.compile(
    r"forest|woodland|silvicultur|conifer|tree\b|trees\b|stand\b|canopy|"
    r"spruce|fir\b|firs\b|pine|hemlock|larch|douglas|abies|picea|pinus|tsuga",
    re.I)
AGENT = re.compile(
    r"insect|beetle|adelgid|adelges|defoliat|pest\b|pests\b|infestat|outbreak|"
    r"herbivor|disturbance|dieback|decline|mortality|damage|windthrow|"
    r"pathogen|disease", re.I)
SENSING = re.compile(
    r"remote sensing|remotely sensed|satellite|landsat|sentinel|modis|spot\b|"
    r"lidar|laser scan|radar|\bsar\b|backscatter|interferometr|polarimetr|"
    r"hyperspectral|multispectral|imagery|photogramm|\buav\b|drone|"
    r"unmanned aerial|spectroscop|reflectance|spectral|aerial photo|"
    r"aerial survey|aerial detection|sketch map", re.I)

# Vocabulary that signals the record was retrieved by term collision rather than
# by topic. "SAR" in particular collides with structure-activity relationship,
# sarcoma and severe acute respiratory, and "stand" with non-forestry senses.
COLLISION = re.compile(
    r"structure.activity relationship|sarcoma|severe acute respiratory|"
    r"sars-cov|synthetic aperture radar altimet|myocardial|carcinoma|"
    r"in vitro|patients|clinical trial|randomised|randomized controlled|"
    r"nanoparticle|catalyst|photovoltaic|semiconductor|blockchain|"
    r"cryptocurren|natural language processing|large language model", re.I)

NOT_RESEARCH = re.compile(
    r"^(editorial|correction|erratum|retraction|corrigendum|preface|"
    r"introduction to the special|book review|in memoriam|obituary)\b", re.I)

# Question 4 concerns survey validation and does not require a remote sensing
# modality, so the no-sensing rule is not applied to records retrieved only by
# that query.
Q4_ONLY = re.compile(r"^Q4$")


def main() -> None:
    src = OUT / "review-records.csv"
    rows = list(csv.DictReader(open(src)))
    if not rows:
        print("no records to screen", file=sys.stderr)
        sys.exit(1)

    out, reasons = [], Counter()
    for r in rows:
        text = f"{r['title']} {r['abstract']}"
        decision, reason = "screen-pass", ""

        if NOT_RESEARCH.search(r["title"] or ""):
            decision, reason = "excluded", "not-research"
        elif not FOREST.search(text):
            decision, reason = "excluded", "not-forest"
        elif COLLISION.search(text):
            decision, reason = "excluded", "off-topic"
        elif not AGENT.search(text):
            decision, reason = "excluded", "no-agent"
        elif not SENSING.search(text) and not Q4_ONLY.match(r["queries"]):
            decision, reason = "excluded", "no-sensing"

        # A record with no abstract cannot be screened on content. It is carried
        # forward rather than excluded, and flagged, because excluding it would
        # silently drop older work that predates abstract indexing.
        needs_manual = not (r["abstract"] or "").strip()

        r = dict(r)
        r["decision"] = decision
        r["reason"] = reason
        r["no_abstract"] = needs_manual
        out.append(r)
        reasons[reason or "passed"] += 1

    fields = list(rows[0].keys()) + ["decision", "reason", "no_abstract"]
    with open(OUT / "review-screened.csv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=fields, extrasaction="ignore")
        w.writeheader()
        w.writerows(out)

    passed = [r for r in out if r["decision"] == "screen-pass"]
    print("SCREENING, mechanical criteria")
    print(f"  records identified                {len(rows):5d}")
    for k in ["not-research", "not-forest", "off-topic", "no-agent",
              "no-sensing"]:
        print(f"    excluded, {k:<14} {reasons[k]:5d}")
    print(f"  passed to manual reading          {len(passed):5d}")
    print(f"    of which lacking an abstract    "
          f"{sum(1 for r in passed if r['no_abstract']):5d}")

    print("\n  passed, by question that retrieved them")
    for q in ["Q1a", "Q1b", "Q2", "Q3a", "Q3b", "Q4"]:
        n = sum(1 for r in passed if q in r["queries"].split(";"))
        print(f"    {q:4} {n:5d}")
    print("  passed, by route")
    for route in ["search", "backward", "forward"]:
        n = sum(1 for r in passed if route in r["routes"].split(";"))
        print(f"    {route:9} {n:5d}")
    print("\nwrote", OUT / "review-screened.csv")


if __name__ == "__main__":
    main()
