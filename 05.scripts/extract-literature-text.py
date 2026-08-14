#!/usr/bin/env python3
"""Extract the text layer of every PDF in 04.references/literature/ to plain text.

Literature protocol, CLAUDE.md: extract the text layer first, and render pages as
images only when the text layer fails or layout matters, because image reads
silently mangle numerals. This script is the "text layer first" step. It reports
characters per page so a failed or scanned text layer is visible rather than
assumed, and it skips macOS AppleDouble sidecars.

Output goes to a scratch directory, not to the repository: extracted text is a
derivative of a copyrighted PDF and PDFs stay out of git.

Usage:
    python3 05.scripts/extract-literature-text.py <outdir>
"""

import sys
from pathlib import Path

import pypdf

LIT = Path(__file__).resolve().parent.parent / "04.references" / "literature"

# Below this many characters per page the text layer is unusable and the PDF is
# scanned images. Flagged, never silently accepted.
MIN_CHARS_PER_PAGE = 100


def main(outdir: Path) -> None:
    outdir.mkdir(parents=True, exist_ok=True)
    pdfs = sorted(p for p in LIT.glob("*.pdf") if not p.name.startswith("._"))
    print(f"{len(pdfs)} PDFs in {LIT}")

    for pdf in pdfs:
        try:
            reader = pypdf.PdfReader(str(pdf))
            pages = [(p.extract_text() or "") for p in reader.pages]
        except Exception as exc:  # a corrupt or encrypted PDF must be visible
            print(f"FAIL  {pdf.name}: {exc}")
            continue

        text = "\n\f".join(pages)
        per_page = len(text) / max(len(pages), 1)
        flag = "SCANNED?" if per_page < MIN_CHARS_PER_PAGE else "ok"
        out = outdir / (pdf.stem + ".txt")
        out.write_text(text)
        print(f"{flag:9s} {len(pages):3d}p {per_page:7.0f} ch/p  {pdf.name}")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
