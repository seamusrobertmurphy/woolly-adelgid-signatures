# Input data manifest

Nothing retrieved yet. Every dataset entering `02.inputs/` is recorded here on the day it
is downloaded, by `05.scripts/00_download_inputs.sh`, with integrity hashes appended to
`SHA256SUMS.txt` and verified by `05.scripts/01_verify_inputs.R`. Raw data are gitignored;
this manifest and the download script are the reproducible record.

The licence column carries what was read from the source on the date given, quoted where
the wording matters. A dataset whose licence page has not been opened is recorded as
unread, never as public domain by assumption. Service metadata counts as the source: a
licence sitting in an image service's own metadata is binding even when the endpoint is
open, and missing that text once already produced a wrong entry in the sibling project.

No outcome analysis is run on any file here until the pre-registration is frozen.

## Downloaded

| Folder | Dataset | Source | Licence | Notes |
|---|---|---|---|---|
| pending | pending | pending | pending | pending |

## Derived

Intermediate products built by manuscript chunks or saved scripts, each regenerable from
the raw inputs and gitignored unless it is a small CSV the manuscript cites. Record what
builds it, what it is built from, its approximate size, and whether it rebuilds
automatically when its source is newer.

- pending

## Streaming or on-demand

Sources used without a local copy: web services, cloud archives, and anything whose
licence forbids bulk download. Record the endpoint, the terms read from the live page,
and the date read.

- pending
