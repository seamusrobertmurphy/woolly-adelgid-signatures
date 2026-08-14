#!/usr/bin/env python3
"""Compute the PRISMA-style counts and per-question tallies for the stage 3 review.

Every count reported in the prior-work survey is produced here, so that a reader can
re-run it rather than take it on trust. Written 2026-08-14.
"""

import os
from collections import Counter

import pandas as pd

ROOT = "/Volumes/PortableSSD/Github/woolly-adelgid-signatures"
D = os.path.join(ROOT, "02.inputs", "derived")


def main():
    records = pd.read_csv(os.path.join(D, "review-records.csv"))
    screened = pd.read_csv(os.path.join(D, "review-screened.csv"))
    decisions = pd.read_csv(os.path.join(D, "review-stage3-decisions.csv"))
    included = pd.read_csv(os.path.join(D, "review-included.csv"))
    log = pd.read_csv(os.path.join(D, "review-search-log.csv"))

    print("== IDENTIFICATION ==")
    print("raw hits summed over queries:", int(log["n"].sum()) if "n" in log.columns else "n column absent")
    print("unique records after dedup:", len(records))

    print("\n== SCREENING, stage 2, mechanical ==")
    print(screened["decision"].value_counts().to_string())
    print(screened["reason"].value_counts(dropna=False).to_string())

    print("\n== ELIGIBILITY, stage 3, by reading ==")
    print(decisions["decision"].value_counts().to_string())
    print(decisions[decisions.decision == "exclude"]["reason"].value_counts().to_string())

    print("\n== INCLUSION ==")
    print("rows in review-included.csv:", len(included))
    print("unique dois (excluding 'none'):", included[included.doi != "none"]["doi"].nunique())

    rq = Counter()
    for s in included["research_question"].fillna(""):
        for tok in str(s).split(";"):
            tok = tok.strip()
            if tok:
                rq[tok] += 1
    print("\nincluded records per question (a record may serve more than one):")
    for k in sorted(rq):
        print(f"  {k}: {rq[k]}")

    print("\n== SCREEN-PASS POOL PER QUESTION (query-code based) ==")
    p = screened[screened.decision == "screen-pass"]
    for k, pat in [("RQ1", "Q1"), ("RQ2", "Q2"), ("RQ3", "Q3"), ("RQ4", "Q4")]:
        print(f"  {k}: {int(p['queries'].str.contains(pat).sum())}")
    print("  retrieved by citation chasing only (no Q code):",
          int((~p["queries"].str.contains("Q")).sum()))

    print("\n== ABSTRACT AVAILABILITY ==")
    print("screen-pass records with no abstract in the search payload:",
          int(p["no_abstract"].sum()))
    cache = os.path.join(D, "review-abstract-cache.jsonl")
    if os.path.exists(cache):
        import json

        rows = [json.loads(l) for l in open(cache) if l.strip()]
        print("identity-resolution attempts made:", len(rows))
        print("of which an abstract or TLDR was recovered:",
              sum(1 for r in rows if r.get("abstract")))

    print("\n== REPORTING QUALITY WITHIN THE INCLUDED SET ==")
    for col in ["support", "validation_design", "class_balance_reported", "accuracy_value"]:
        vals = included[col].fillna("not stated").astype(str)
        unstated = vals.str.lower().str.startswith(("not stated", "not extracted", "not retrievable", "no", "not applicable")).sum()
        print(f"  {col}: {len(included) - unstated} of {len(included)} report something specific")

    print("\n== STAGE 2 SCREENING FALSE-NEGATIVE DIAGNOSTIC ==")
    ex = screened[screened.decision == "excluded"]
    noab = ex[ex.no_abstract == True]
    print("excluded records carrying no abstract:", len(noab))
    nf = noab[noab.reason == "not-forest"]
    print("of which excluded as not-forest:", len(nf))
    kw = (r"(?i)forest|tree|stand|canopy|conifer|spruce|pine|fir|beetle|defoliat|woodland"
          r"|silvicult|bark|insect|adelgid|budworm|larch|birch|oak")
    hit = nf[nf.title.astype(str).str.contains(kw, regex=True, na=False)]
    print("of which the title carries a forest or agent term, and so need re-screening:", len(hit))
    print("Senf et al. 2015 is one of them; it refutes the two-insect novelty claim.")



if __name__ == "__main__":
    main()
