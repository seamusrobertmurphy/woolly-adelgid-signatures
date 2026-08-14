# 04.references, source manifest

Every source in this folder is recorded here: what it is, where it came from, whether it
is peer-reviewed, and whether it has been read. PDFs are not committed to git; this
manifest is how a fresh clone knows what to retrieve. Verify each bibliographic record
against CrossRef before it enters `references.bib`, and take the entry from the registry
rather than from memory.

A claim attributed to a source is quoted from the source, checked against it, and cited
with the page, figure or section where it sits. Paraphrase attributed as wording has cost
this library several drafts before it was caught.

## Verification method

All eleven PDFs were text-extracted with `05.scripts/extract-literature-text.py` on
2026-08-13; every one has a usable text layer, so no page was read as an image. Titles
were matched against CrossRef with `05.scripts/verify-references-crossref.py`. **That
automated match was wrong for four of the eleven**, which is why the script reports a
similarity score and refuses anything below 0.60 rather than writing silently. Each DOI
in `references.bib` was then re-confirmed individually against `api.crossref.org`. The
failures are recorded below rather than quietly corrected, because the failure mode
matters: a title-similarity match will happily return a different paper by different
authors on a related subject.

## literature/

Eleven PDFs. Seven are in `references.bib`; four are not, and the reason is given.

| File | Identity | Verified | Status |
|---|---|---|---|
| MacQuarrie et al 2025 | The Canadian Entomologist 157:e11, `10.4039/tce.2025.2`. Peer-reviewed, open access CC BY-NC-ND. | CrossRef, DOI read from the PDF itself | **Read in full.** Load-bearing. Source of the finding that *A. tsugae* "exists at low densities in forests and rarely kills trees" in western North America, and of the British Columbia distribution. Auto-match returned an unrelated dissertation on gypsy moth at score 0.61; DOI taken from the PDF instead. |
| Campbell et al 2023 | Forests 14(7):1357, `10.3390/f14071357`. Peer-reviewed, CC BY. | CrossRef, score 1.00 | **Read: abstract and introduction.** Primary methodological exemplar. Source of the R² figures for spectral, terrain-climate and combined models. Methods and results sections not yet read in full. |
| Jones et al 2015 | Forest Ecology and Management 358:222-229, `10.1016/j.foreco.2015.09.013`. Peer-reviewed. | CrossRef, score 0.95 | **Read: abstract and introduction.** Second exemplar. Also a structural precedent for the named venue, being published in it. |
| Cornelsen et al 2024 | Canadian Journal of Forest Research 54(12):1458-1470, `10.1139/cjfr-2023-0275`. Peer-reviewed. | CrossRef, score 1.00 | **Not yet read.** Third named exemplar. Climate-scenario distribution modelling for the eastern adelgid. |
| Bright et al 2020 | Remote Sensing 12(10):1655, `10.3390/rs12101655`. Peer-reviewed, CC BY. | CrossRef, score 1.00 | **Not yet read.** Cited in the manuscript only for the general claim that Landsat time series map insect disturbance regionally. Read before that citation carries any more weight. |
| Cavender-Bares et al 2020 | *Remote Sensing of Plant Biodiversity*, Springer, `10.1007/978-3-030-33157-3`. Edited volume, 594 pp, open access. | CrossRef, DOI read from the PDF front matter | **Not yet read.** Auto-match returned a 2019 *Remote Sensing of Environment* article of similar title at score 0.86; that is a different work. Corrected by hand. Not currently cited. |
| Bost 2018 | **The PDF is an MSc thesis**, Humboldt State University, 28-year Landsat series. | Not verified as the thesis; no DOI located for it | **CAUTION, and not yet read.** The `Bost_2019` entry in `references.bib` is the *later and different* Landscape Ecology article (34:2599-2614, `10.1007/s10980-019-00907-7`, 30-year series). Do not cite that entry for a claim read in the thesis without confirming the claim survives into the published paper. |
| Senf 2016 | PhD dissertation. Contains constituent chapter DOIs, none of which is the thesis itself. | Rejected by the guard at score 0.54 | **Not in `references.bib`. Not yet read.** Needs hand entry as `@phdthesis`, flagged. Directly relevant: remote sensing of insect disturbance in British Columbia. |
| Muise 2020 | **Undergraduate honours thesis**, Environmental Science, Dalhousie University. | Rejected by the guard at score 0.41 | **Not in `references.bib`. Not yet read.** Grey literature and not peer-reviewed. Cite only with that status stated, if at all. |
| Sickle et al 2001, Parts I and II | History of forest insect investigations in British Columbia. Provenance not established. | Both auto-matched a 1914 monograph, `10.5962/bhl.title.18455`. Wrong. | **Not in `references.bib`. Not yet read.** No DOI located. Needs hand entry once the actual publication is identified. |

## reports/

Empty as a directory, but two agency sources are already load-bearing in the manuscript
and the framing document and must be filed here before either is submitted anywhere.

| Source | Identity | Verified | Status |
|---|---|---|---|
| BC Ministry of Forests, 2025 | *2025 Summary of Forest Health Conditions in British Columbia*, 102 pp. Retrieved 2026-08-13. | Text-extracted and searched directly | **Read: methods section and Coast Area tables.** Source of the digitising rule and of the finding that no adelgid appears in any 2025 Coast Area damage table. Not yet filed as a PDF in this folder. |
| Canadian Food Inspection Agency | Scientific fact sheet, *Adelges tsugae*. Retrieved 2026-08-13. | Quoted from the live page | **Read.** Source of the statement that damage to western hemlock in British Columbia "has been minor". Web page, not a PDF; capture it before citing in a submission. |

## standards/

| Source | Identity | Verified | Status |
|---|---|---|---|
| BC Ministry of Forests | *Forest Health Aerial Overview Survey Standards for British Columbia*, 46 pp. Cover states it is "The B.C. Ministry of Forests adaptation of the Canadian Forest Service's FHN Report 97-1". Retrieved 2026-08-13 from `www2.gov.bc.ca/assets/gov/environment/natural-resource-stewardship/nr-laws-policy/risc/aerial.pdf`. | Text-extracted with pypdf and searched directly; provenance header read from the cover | **Read: code list, host and timing table, severity definitions.** Confirms "IAB Balsam Woolly Adelgid" under "IA APHIDS" and "IBB Western balsam bark beetle" under "IB BARK BEETLES". Confirms IAB hosts as sub-alpine true firs, amabilis fir and grand fir. Contains **no** entry for hemlock woolly adelgid or *Adelges tsugae*. Source of the mortality severity classes. Not yet filed as a PDF in this folder. |

**Edition caveat.** The retrieved document carries a 2000 date. A 2019 edition is
referenced from the survey methods page but returned HTTP 404 on 2026-08-13. Codes are
therefore confirmed as of the 2000 edition, and the possibility that a later revision
changed them is open. This matters because the whole target class rests on the code
assignment; the independent check is that the hosts listed against IAB in the standards
match the host codes actually present in the archive extract.

## Venue

**Forest Ecology and Management** was named by Seamus on 2026-08-13. Its guide for
authors has **not** been read: ScienceDirect returned HTTP 403 to an automated fetch on
that date. No word limit, article type, abstract length, reference style or declaration
wording appears anywhere in this repository, and none may be written until the live guide
is read and its retrieval date recorded here.
