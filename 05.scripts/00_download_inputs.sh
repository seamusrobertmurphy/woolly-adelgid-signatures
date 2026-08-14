#!/bin/sh
# Download open input data into 02.inputs/. Idempotent: skips files already present.
# Provenance and licences: see 02.inputs/README.md. Run from the repo root.
#
# Add one numbered block per dataset, each carrying the archive identifier and the
# licence as read from the source. A dataset is not added here until its licence
# has been read; recording it as unknown is correct, guessing is not.
set -eu
IN=02.inputs

get () {
  # get <url> <dest>
  if [ -f "$2" ]; then echo "have $2"; else
    echo "fetching $2"
    curl -fL --retry 3 -o "$2" "$1"
  fi
}

# 1. <dataset name>, <archive and identifier>, <licence as read on YYYY-MM-DD>.
# mkdir -p "$IN/<folder>"
# get "<url>" "$IN/<folder>/<file>"

echo "done"; du -sh "$IN"/*/ 2>/dev/null || true

# Record hashes after a fresh download, from the repo root:
#   find 02.inputs -type f ! -name SHA256SUMS.txt -exec shasum -a 256 {} \; \
#     | sed 's| 02.inputs/| |' > 02.inputs/SHA256SUMS.txt
