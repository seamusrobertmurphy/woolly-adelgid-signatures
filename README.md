# woolly-adelgid-signatures

[Title pending, fixed at the framing gate.]

## Abstract

[Pending. Mirrors the abstract in `01.manuscript/manuscript.qmd`, which is the single
source of truth; this file is a rendered summary of it and never diverges from it.]

## Status

Repository skeleton only, created 2026-08-13 from the structure and conventions of
`deep-learn-alaska-spruce-beetle`. Not framed, not surveyed, not designed, not
pre-registered, no data. The manuscript template renders but contains only placeholders.

## Figures

[Pending. Each figure listed here with its full caption, and linked to the committed PNG
in `03.outputs/figures/`.]

## Tables

Tables render live in `01.manuscript/manuscript.qmd` at uniform width; results tables
carry their final structure with every cell marked pending until the pre-registered
analysis executes.

1. Input datasets, their roles, and access terms.
2. Unit tests of the evaluation metrics.
3. Primary pre-registered test. Pending.

## Reproduction

The manuscript is executable: every number and figure is computed at render time from
`01.manuscript/manuscript.qmd`. Render with `quarto render manuscript.qmd --to html` from
inside `01.manuscript/`. Inputs are retrieved by `05.scripts/00_download_inputs.sh` and
verified against checksums by `05.scripts/01_verify_inputs.R`; provenance and licence for
every input are recorded in `02.inputs/README.md`.
