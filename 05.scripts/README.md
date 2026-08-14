# 05.scripts

Pre-processing and analysis code that the manuscript reads. Scripts are numbered in the
order they run, and the number is stable once assigned; a step inserted later takes a
letter suffix (`04a_`) rather than renumbering what follows.

Saving a script here does not by itself let its numbers into the manuscript. The rule is
that the manuscript reads the script's saved output, or the code lives in a manuscript
chunk. Code in a chunk is the default; this folder is for work too heavy, too slow or too
remote to run at render time, such as bulk downloads, cloud training and GPU inference.

Naming, following the sibling project:

| Prefix | Stage |
|---|---|
| `00_` | Retrieval of raw inputs |
| `01_` | Integrity verification against checksums |
| `02_` | Compositing or assembly of predictors |
| `03_` | Sample and fold construction, the split lock |
| `04_` | Label production |
| `05_` | Quality control and adjudication |
| `06_` | Feature and response tables |
| `07_` | Model training |
| `08_` | Baseline model |
| `09_` | Evaluation, writing results to `03.outputs/` |

The split lock at `03_` is the point after which no outcome value may be joined to a
predictor. Commit it before any label or outcome work begins.
