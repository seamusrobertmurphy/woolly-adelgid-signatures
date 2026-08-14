#!/usr/bin/env python3
"""Emit the 721 screen-pass records as ordered reading batches for stage 3.

Order follows the task's priority: RQ3 first, then RQ2, RQ4, RQ1. A record retrieved
by more than one query is read once, under its highest-priority question, and its full
question set is printed so the reader can assign it to all of them.

Abstracts resolved by `10-review-fetch-abstracts.py` are merged in.
Written 2026-08-14.
"""

import json
import os
import re

import pandas as pd

ROOT = "/Volumes/PortableSSD/Github/woolly-adelgid-signatures"
OUTDIR = os.environ.get("BATCHDIR", os.path.join(ROOT, "02.inputs", "derived", "review-batches"))
CACHE = os.path.join(ROOT, "02.inputs", "derived", "review-abstract-cache.jsonl")

QMAP = {"Q1a": "RQ1", "Q1b": "RQ1", "Q2": "RQ2", "Q3a": "RQ3", "Q3b": "RQ3", "Q4": "RQ4"}
# citation-chased records inherit the question their seed was chosen to serve
SEEDMAP = {
    "Campbell 2023": "RQ1",
    "Franklin 1995": "RQ1",
    "Oeser 2017": "RQ2",
    "Morin-Bernard 2023": "RQ2",
    "Tanase 2018": "RQ3",
}
PRIORITY = ["RQ3", "RQ2", "RQ4", "RQ1"]


def questions(q):
    out = set()
    for tok in str(q).split(";"):
        tok = tok.strip()
        if tok in QMAP:
            out.add(QMAP[tok])
        elif tok in SEEDMAP:
            out.add(SEEDMAP[tok])
    return out or {"RQ2"}


def main():
    os.makedirs(OUTDIR, exist_ok=True)
    d = pd.read_csv(os.path.join(ROOT, "02.inputs", "derived", "review-screened.csv"))
    p = d[d.decision == "screen-pass"].copy().reset_index(drop=True)

    resolved = {}
    if os.path.exists(CACHE):
        with open(CACHE) as fh:
            for line in fh:
                line = line.strip()
                if line:
                    r = json.loads(line)
                    if r.get("abstract"):
                        resolved[r["key"]] = r["abstract"]

    def abstract_of(row):
        if isinstance(row.abstract, str) and row.abstract.strip():
            return row.abstract
        for key in (row.doi, row.s2_id):
            if isinstance(key, str) and key in resolved:
                return "[resolved] " + resolved[key]
        return "[NO ABSTRACT AVAILABLE]"

    p["qs"] = p["queries"].map(questions)
    p["primary"] = p["qs"].map(lambda s: min(s, key=PRIORITY.index))
    p["abs2"] = p.apply(abstract_of, axis=1)
    p["ord"] = p["primary"].map(PRIORITY.index)
    p = p.sort_values(["ord", "year"], ascending=[True, False]).reset_index(drop=True)
    p["rid"] = ["R%04d" % (i + 1) for i in range(len(p))]

    p[["rid", "primary", "queries", "routes", "year", "title", "venue", "doi", "s2_id", "citations"]].to_csv(
        os.path.join(OUTDIR, "index.csv"), index=False
    )

    size = 45
    for start in range(0, len(p), size):
        chunk = p.iloc[start : start + size]
        lines = []
        for _, r in chunk.iterrows():
            a = re.sub(r"\s+", " ", str(r.abs2)).strip()
            if len(a) > 900:
                a = a[:900] + " ...[truncated]"
            lines.append(
                f"### {r.rid} [{'/'.join(sorted(r.qs))}] {r.year if pd.notna(r.year) else 'n.d.'} | "
                f"{r.title}\nvenue: {r.venue} | doi: {r.doi} | cites: {r.citations} | via: {r.queries}\n{a}\n"
            )
        n = start // size + 1
        with open(os.path.join(OUTDIR, f"batch-{n:02d}.md"), "w") as fh:
            fh.write("\n".join(lines))
    print(f"{len(p)} records, {(len(p) - 1) // size + 1} batches, in {OUTDIR}")
    print(p["primary"].value_counts())


if __name__ == "__main__":
    main()
