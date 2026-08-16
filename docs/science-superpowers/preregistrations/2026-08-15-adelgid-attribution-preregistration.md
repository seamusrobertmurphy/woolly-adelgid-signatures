# Pre-registration: separating balsam woolly adelgid from bark beetle damage

**Frozen at commit:** the commit adding this file is the timestamp.
**Question doc:** `docs/science-superpowers/questions/2026-08-13-adelgid-attribution-vancouver-island.md`
**Analysis plan:** `docs/science-superpowers/plans/2026-08-14-adelgid-attribution-plan.md`

**Status of outcome data at freeze.** The agent label lives in
`02.inputs/derived/analysis-set.geojson` as `PEST_SPECIES_CODE` and has been read only to
count the sample: totals by agent, by severity, by survey year, by landmass and by whether
a polygon carries lidar returns. Those are inclusion counts and appear in the manuscript
as such. No predictor value from
`predictors-optical.csv`, `predictors-radar.csv` or `predictors-structural.csv` has been
joined to any label, crossed with any label, plotted against any label or summarised by
label. No model has been fitted. The three predictor blocks each assert, at the point of
writing, that their output carries no agent, severity or host column, and those assertions
run on every build.

## Hypotheses

- **H1-H0.** The multi-sensor model, spectral with structure and radar, achieves the same
  balanced accuracy as the spectral-only model at equal complexity on identical folds.
- **H1.** The multi-sensor model achieves higher balanced accuracy than the spectral-only
  model, because progressive top-down dieback and gout alter canopy geometry in a way that
  rapid whole-crown mortality does not, and because with host held constant the spectral
  baseline cannot fall back on host composition.
- **H2-H0.** Adding structure alone to the spectral baseline achieves the same balanced
  accuracy as the spectral baseline.
- **H2.** Adding structure alone improves on the spectral baseline.

## Primary analyses

- **Unit.** The aerial overview survey polygon, at its own support, eroded 20 m inward.
  No pixel-level or tree-level claim is made.
- **Outcome.** The two-class agent label, IAB balsam woolly adelgid against IBB western
  balsam bark beetle, as attributed by the surveyor. Positive class is IAB. The label is
  taken as delivered and is not adjudicated.
- **Predictors.** Three families, fixed here in full.
  - *Spectral*, 36 variables: bands B2, B3, B4, B5, B6, B7, B8, B8A, B11, B12 and indices
    NDVI, NDMI, NBR, NDRE1, GNDVI, MSI, SWIRR, EVI, each as a polygon mean and standard
    deviation.
  - *Radar*, 8 variables: terrain-flattened gamma0 in VV and VH and their temporal
    dispersion, each as a polygon mean and standard deviation.
  - *Structural*, 12 variables entering the model: zq25, zq50, zq75, zq95, the ratio of
    zq25 to zq95, canopy relief ratio, the proportion of returns above two thirds of the
    canopy top, rumple, canopy height model standard deviation, coefficient of variation
    of first returns, canopy cover above 2 m, gap fraction and the vertical complexity
    index. The canopy top `ztop` and the cell count are diagnostics and do not enter.
  - *Covariates in every model*, 2 variables: survey year and mean polygon slope. Terrain
    is carried because radiometric flattening leaves a residual association with steepness
    of -0.51, measured and reported.
- **Models.** Random forests, `ranger`, probability forests, following @Campbell_2023.
  Three nested sets: spectral plus covariates; spectral plus structure plus covariates;
  all three families plus covariates. Equal complexity across the three: 1000 trees,
  `mtry` fixed at the floor of the square root of the number of predictors in that set,
  minimum node size 5, no tuning at all. Fixing rather than tuning is deliberate on 61
  units, since a tuning loop inside 5 folds on 61 units estimates noise.
- **Baseline.** The spectral-only model, fitted on the same training folds.
- **Cross-validation.** Spatially blocked, constructed before any label is joined, by the
  chunk `pipe-blocks` in the manuscript, and written to
  `02.inputs/derived/spatial-blocks.csv`. Blocks are formed by k-medoids clustering of
  polygon centroids in BC Albers. Polygons whose eroded geometries intersect or lie within
  50 m of one another are forced into the same block before clustering is applied, because
  the survey digitises adjacent damage as separate records. Block count is set so that no
  fold holds fewer than two blocks. Folds are formed by assigning whole blocks to five
  folds, balanced on block size only, never on the label.
- **Test of each hypothesis.** The statistic is the difference in balanced accuracy
  between the model in question and the spectral baseline, paired by fold. The interval is
  the bias-corrected percentile bootstrap over folds with 10,000 draws, seed 20260815. Two
  sided at 95 percent.

## Predictions

H1 positive, and H2 positive and smaller. No planning magnitude is available: the prior
work survey found no study comparing these two agents on a shared host, so there is no
prior effect size to anchor on. This is stated rather than substituted with a guess, and
it is why the study reports an interval rather than a power claim.

## Decision rules

For each hypothesis, confirmed if and only if the paired difference is positive and its 95
percent interval excludes zero. Disconfirmed if the interval excludes zero in the negative
direction. **Inconclusive if the interval spans zero**, which is not a confirmation and is
not reported as a trend. A null is reported as a null in the abstract and the conclusions,
with no reframing towards a secondary finding.

## Sample size

61 polygons, 35 adelgid and 26 bark beetle, imbalance 1.35 to 1. Fixed by four inclusion
criteria applied in this order, each stated with its cost:

1. Agent IAB or IBB, host Pacific silver fir, lidar within 5 years, on Vancouver Island:
   84 polygons. Frozen 2026-08-14.
2. Polygon contains lidar returns, tested against the point clouds rather than the tile
   index: 72. Twelve polygons stand on ground the index claims and the delivered clouds do
   not occupy.
3. Achieved point density after thinning at least 4 points per square metre: 61. The
   threshold is set by the metric definitions, not by sample size: at 4 points per square
   metre 1.8 percent of 1 m cells are empty from pulse spacing alone under a Poisson
   process, so the rule that an empty cell marks an opening holds; at 2 the figure is 13.5
   percent and it does not.
4. No missing predictor value in any family: expected to remove none, since all three
   tables are complete over their polygons.

Five folds. Seed 20260815 everywhere. No extension, and no exclusion after outcomes are
seen.

## Multiplicity

The confirmatory family is the two tests, H1 and H2, against the same baseline. Holm
correction across the two. Everything else, including per-class sensitivity and
specificity, the confusion matrices, variable importance by family and the campaign
sensitivity, is secondary or descriptive and is labelled so in the manuscript.

## Falsifiability check

H1 is disconfirmed if the multi-sensor model's balanced accuracy is no higher than the
spectral baseline's, and that outcome is not merely plausible but likely on this sample:
severity is trace and light throughout, which is where any signal is weakest; the labels
are sketch-mapped and unverified, which caps agreement; and 61 units with five spatial
folds gives a wide interval. A result near 0.5 balanced accuracy for all three models is a
plausible outcome and would disconfirm both hypotheses.

## Pipeline test

A test on synthetic data with known truth precedes any claim from real data, per the
standing convention. The test builds a synthetic sample of the same shape, 61 units, the
same predictor counts and the same block structure, under two regimes: a null regime in
which no predictor carries signal, where the pipeline must return balanced accuracy near
0.5 and intervals spanning zero; and a planted regime in which a known subset of the
structural predictors carries a separating signal, where the pipeline must recover a
positive difference. The test is in the manuscript and its output is reported.

## Deviations

Any deviation is documented in the manuscript and renders the affected analysis
exploratory.

## Amendments

Amendments are legitimate only while no outcome value has been read, plotted or joined to
a predictor. Each is dated, states what it changes and what it leaves unchanged, and
states the evidence that the outcome data were still untouched.

---

### Amendment 1, 2026-08-15

**Evidence the outcome data are still untouched.** No model has been fitted. The label has
been read only for the inclusion counts already reported. No predictor value has been
joined to, crossed with, plotted against or summarised by any label. The structural table
is being rebuilt by this amendment, so the values it will contain do not yet exist.

**What changes, and why.** Raised by Seamus on 2026-08-15, that the metric set must
answer to the biology and to the prior literature on where the adelgid signal sits.

1. **The structural family gains three variables**, from 12 to 15: canopy permeability
   `rh10`, the height below which a tenth of all returns above 0.5 m fall; `p_mid`, the
   proportion of returns from 5 to 15 m; and `p_under`, the proportion below 5 m. The
   reason is @Boucher_2020, who found midstorey plant area at 11 to 12 m and canopy
   permeability by RH10 accounted for 60 percent of the variation in hemlock mortality
   because the insect defoliates from the midstorey and understorey upward, and
   @Garris_2019, who locate the optical signal in the same stratum. The metric set as
   frozen was weighted to the overstorey and would have looked in the wrong place.
2. **The common density target rises from 8 to 16 points per square metre**, because the
   three new variables depend on pulses reaching the lower canopy and the archive supports
   it: delivered density has a median of 43.9 per polygon.
3. **The density floor stays at 4 points per square metre**, set by what the canopy model
   cell rule requires. Polygons between the floor and the target are not at common
   density, so **achieved density is carried as a covariate in every model**, on the same
   footing as terrain, and a **sensitivity analysis restricted to polygons at target** is
   reported alongside the primary result.
4. **Lidar processing adopts two methods from the lidar-forestry book**
   (github.com/seamusrobertmurphy/lidar-forestry, commit `7de4140`): statistical outlier
   removal for noise, `sor(k = 10, m = 3)`, and a triangulated canopy model,
   `dsmtin(max_edge = 8)`, whose edge limit doubles as the gap rule. The book's inverse
   distance terrain interpolator [@Tu_2020] is **not** adopted, and the deviation is
   measured rather than asserted: on one polygon the two surfaces agree to 0.19 m at
   r = 0.9999, but triangulation runs in 5.1 s against 61 s and leaves 180 cells to
   nearest-neighbour fallback against 71,357, because the book's 50 m search radius is
   tuned to a 1 ha clip and these polygons reach 353 ha. Cloth simulation filtering
   [@Zhang_2016] is not needed because the tiles carry a delivered ground class.

**What is unchanged.** The hypotheses, the decision rules, the inconclusive case, the
blocking scheme, the model specification and fixed hyperparameters, the bootstrap and its
seed, and inclusion criteria 1, 2 and 4. The sample count under criterion 3 will be
restated once the rebuild completes, since the achieved density changes with the target.

**Stated expectation, recorded before the result.** @Choi_2023 found the structural
impact of press disturbances "could not be clearly detected, likely because of
compensatory growth". Adelgid damage is a press disturbance. This amendment improves the
chance of finding a signal if one exists; it does not make a null less likely to be true,
and a null remains the outcome to be reported plainly if it is what the data give.

### Sample restated, 2026-08-16

Amendment 1 raised the common density from 8 to 16 points per square metre and stated
that the count under inclusion criterion 3 would be restated once the rebuild finished.
It has, and the count moves **up**, not down: **69 polygons, 41 adelgid and 28 bark
beetle, imbalance 1.46 to 1**, against 61 under the previous build.

Raising the target lifted achieved density across the sample, median 15.19 against 7.79,
so eight polygons that fell below the 4 points per square metre floor now clear it. Three
remain below and are excluded: P034 at 0.55, P005 at 2.40 and P040 at 3.01. The floor
itself is unchanged at 4, and the pre-registered sensitivity restricted to polygons at
target covers the 40 polygons at or above 15 points per square metre, which are balanced
20 to 20.

Blocking and the pipeline test were rebuilt on the 69 before any model was fitted. Ten
blocks, five folds, two blocks per fold, 13 to 14 polygons per fold. The pipeline test
passes both regimes on that structure: balanced accuracy 0.49, 0.47 and 0.48 under the
null with paired differences of -0.027 and -0.013, and 0.45 against 0.95 under the
planted signal, a difference of 0.51. No outcome value had been joined to any predictor
at the time of this restatement.
