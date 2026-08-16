# Separating balsam woolly adelgid from bark beetle damage in Pacific silver fir on Vancouver Island: a multi-sensor attribution test

## Abstract

Balsam woolly adelgid (Adelges piceae) and western balsam bark beetle (Dryocoetes confusus) are both mapped on Pacific silver fir (Abies amabilis) in the British Columbia aerial overview survey, so a canopy-damage detector that cannot separate them measures neither. In this study, we examine whether adding lidar and radar predictors to a spectral baseline improves separation of the two agents. On 69 survey polygons under spatially blocked cross-validation, with the sample, folds and decision rule fixed before any model was fitted, it does not. A spectral baseline reaches a balanced accuracy of 0.632; adding canopy structure lowers it to 0.549, a paired difference of -0.083 whose interval excludes zero; adding radar as well returns 0.640, indistinguishable from the baseline. The structural hypothesis is contradicted rather than merely unsupported, which is consistent with published evidence that press disturbances leave canopy structure largely unchanged. The result holds for trace and light damage, the only severities for which public lidar and the survey record coincide anywhere in British Columbia.

## Figure 1

Study area on Vancouver Island and the adjacent mainland coast of British Columbia, Canada, showing aerial overview survey polygons attributed to balsam woolly adelgid and to western balsam bark beetle on true fir hosts. Relief is shaded from a 1 km digital elevation model illuminated from the northwest. Projection NAD83 / BC Albers (EPSG 3005); axis labels in degrees.

![Study area on Vancouver Island and the adjacent mainland coast of British Columbia, Canada, showing aerial overview survey polygons attributed to balsam woolly adelgid and to western balsam bark beetle on true fir hosts. Relief is shaded from a 1 km digital elevation model illuminated from the northwest. Projection NAD83 / BC Albers (EPSG 3005); axis labels in degrees.](03.outputs/figures/fig-studyarea-1.png)


## Table 1

Datasets used in the analysis, with their role and access terms.

| Dataset | Role | Source | Licence |
|---|---|---|---|
| Pest Infestation Polygons | Damage agent labels | BC Data Catalogue | Open Government Licence - British Columbia |
| Sentinel-2 L2A | Optical predictors | Google Earth Engine | Copernicus open access |
| Sentinel-1 GRD | Radar predictors | Google Earth Engine | Copernicus open access |
| LidarBC open lidar | Canopy structure predictors | LidarBC open data portal | Open Government Licence - British Columbia |


## Table 2

Aerial overview survey polygons in the study area by damage agent and host tree species. Area is the survey-recorded polygon area.

| Agent | Host | Polygons | Area (ha) |
|---|---|---|---|
| Balsam woolly adelgid | Pacific silver fir | 176 | 8,324 |
| Balsam woolly adelgid | True fir, unspecified | 12 | 118 |
| Balsam woolly adelgid | Grand fir | 2 | 6 |
| Western balsam bark beetle | Subalpine fir | 1,125 | 75,797 |
| Western balsam bark beetle | Pacific silver fir | 592 | 25,685 |
| Western balsam bark beetle | True fir, unspecified | 41 | 1,756 |
| Western balsam bark beetle | Grand fir | 2 | 58 |


## Table 3

Severity class of survey polygons by damage agent. Severity is the surveyor’s ordinal rating.

| Agent | Trace | Light | Moderate | Severe |
|---|---|---|---|---|
| Balsam woolly adelgid | 133 | 46 | 4 | 7 |
| Western balsam bark beetle | 1,187 | 457 | 100 | 16 |


## Figure 2

Survey polygons mapped per year on true fir hosts in the study area, by damage agent.

![Survey polygons mapped per year on true fir hosts in the study area, by damage agent.](03.outputs/figures/fig-timeseries-1.png)


## Table 4

Satellite scenes available over the study area for the analysis period.

| Sensor | Product | Period | Scenes |
|---|---|---|---|
| Sentinel-2 MSI | COPERNICUS/S2_SR_HARMONIZED | 2019-06-01 to 2021-09-30 | 2,877 |
| Sentinel-1 SAR | COPERNICUS/S1_GRD | 2019-06-01 to 2021-09-30 | 1,575 |


## Table 5

Lidar point cloud coverage over the study area and over the Comox field window. Acquisition years and point classes are summarised from a sample of up to 1000 tiles.

| Extent | Tiles | Full index | Acquisition years | Density (pts/m2) | Point classes |
|---|---|---|---|---|---|
| study area | 18,840 | False | 2023;2024;2025 | 8 | [1,2,7,12] |
| Comox field window | 999 | True | 2018;2019;2023;2024 | 8 | [1, 2, 7];[1, 7];[1,2,7,12];[7] |


## Figure 3

Candidate field sites. Points are aerial overview survey polygons attributed to balsam woolly adelgid, sized by area and coloured by severity class; open circles lack lidar coverage and filled circles have it. Shaded envelopes show LidarBC point cloud coverage. Rings mark 50, 100 and 150 km from Comox and are shown for travel planning only, not as a selection criterion. Two mainland records fall outside this frame. Projection NAD83 / BC Albers (EPSG 3005).

![Candidate field sites. Points are aerial overview survey polygons attributed to balsam woolly adelgid, sized by area and coloured by severity class; open circles lack lidar coverage and filled circles have it. Shaded envelopes show LidarBC point cloud coverage. Rings mark 50, 100 and 150 km from Comox and are shown for travel planning only, not as a selection criterion. Two mainland records fall outside this frame. Projection NAD83 / BC Albers (EPSG 3005).](03.outputs/figures/fig-fieldsites-1.png)


## Figure 4

Lidar tiles and survey polygons over northern Vancouver Island. Grey squares are individual LidarBC point cloud tiles, shaded by acquisition year. Polygon outlines are aerial overview survey records: red for balsam woolly adelgid, blue for western balsam bark beetle, with adelgid polygons rated moderate or worse drawn heavier. Projection NAD83 / BC Albers (EPSG 3005).

![Lidar tiles and survey polygons over northern Vancouver Island. Grey squares are individual LidarBC point cloud tiles, shaded by acquisition year. Polygon outlines are aerial overview survey records: red for balsam woolly adelgid, blue for western balsam bark beetle, with adelgid polygons rated moderate or worse drawn heavier. Projection NAD83 / BC Albers (EPSG 3005).](03.outputs/figures/fig-tiles-1.png)


## Table 6

Effect of statistical outlier removal on the structural metrics, measured on the three densest small polygons. Overstorey metrics are unmoved; the lower-profile metrics shift, and almost everything the filter removes lies inside the canopy rather than above it.

| Quantity | As delivered | After the filter |
|---|---|---|
| Raw maximum height (m) | 64.31, 195.06, 109.69 | 64.31, 114.1, 62.32 |
| 99th percentile height (m) | 47.42, 51.81, 44.69 | 47.47, 51.85, 44.73 |
| 95th percentile height (m) | 38.93, 46.44, 40.15 | 39.02, 46.51, 40.21 |
| Canopy permeability rh10 (m) | 3.97, 5.16, 10.79 | 4.05, 5.3, 11.62 |
| Midstorey return fraction | 0.2702, 0.1261, 0.0672 | 0.2675, 0.1228, 0.0614 |
| Rumple | 4.224, 4.517, 3.347 | 4.215, 4.489, 3.334 |
| Returns flagged |  | 115,808, 236,740, 96,774 |
| Of those, above the 95th percentile |  | 968, 761, 205 |
| Of those, inside the canopy |  | 94,226, 205,479, 84,706 |


## Table 7

Verification of the balanced accuracy implementation against cases with analytically known values.

| Case | Expected | Observed | Agrees |
|---|---|---|---|
| Perfect prediction | 1 | 1 | true |
| Fully inverted prediction | 0 | 0 | true |
| All assigned to majority class | 0.5 | 0.5 | true |
| Imbalanced, all majority (overall accuracy 0.75) | 0.5 | 0.5 | true |


## Table 8

Polygons of the frozen sample that carry lidar returns, against those the tile index claimed but the point clouds do not cover.

| Class | Frozen sample | With returns | No returns |
|---|---|---|---|
| Balsam woolly adelgid | 48 | 43 | 5 |
| Western balsam bark beetle | 36 | 29 | 7 |
| Total | 84 | 72 | 12 |


## Table 9

The three predictor families as built, with the imagery and point cloud volumes behind them.

| Family | Source | Polygons | Variables | Observations |
|---|---|---|---|---|
| Spectral | Sentinel-2 L2A | 84 | 36 | 1,266 scenes |
| Radar | Sentinel-1 GRD | 84 | 8 | 673 scenes |
| Structural | LidarBC point clouds | 72 | 16 | 121 tiles |


## Table 10

Association between Sentinel-1 backscatter and terrain geometry, before and after radiometric terrain flattening.

| Quantity | Uncorrected | Flattened |
|---|---|---|
| Correlation with range slope | 0.925 | -0.154 |
| Correlation with slope | -0.001 | -0.505 |
| Between-polygon standard deviation (dB) | 2.64 | 1.01 |


## Table 11

Delivered point density by acquisition year against the density advertised for every tile, and the density achieved after thinning.

| Year | Tiles | Advertised | Delivered median | Delivered range | Achieved median |
|---|---|---|---|---|---|
| 2,019 | 93 | 8 | 31.1 | 0.5 to 140.1 | 15.2 |
| 2,023 | 20 | 8 | 64.8 | 44.7 to 226.8 | 15.04 |
| 2,024 | 3 | 8 | 56 | 48.7 to 57.0 | 15.61 |
| 2,025 | 5 | 8 | 70.6 | 65.6 to 72.0 | 5.38 |


## Table 12

Per-class performance from pooled out-of-fold predictions, every polygon predicted once by a model that never saw it.

| Predictor set | Sensitivity | Specificity | Balanced accuracy | Adelgid correct | Bark beetle correct |
|---|---|---|---|---|---|
| Spectral | 0.707 | 0.464 | 0.586 | 29 of 41 | 13 of 28 |
| Spectral and structure | 0.683 | 0.357 | 0.52 | 28 of 41 | 10 of 28 |
| Spectral, structure and radar | 0.854 | 0.393 | 0.623 | 35 of 41 | 11 of 28 |


## Table 13

Separation of the two damage agents by predictor set, under spatially blocked cross-validation. The interval is the bias-corrected percentile bootstrap over folds on the paired difference from the spectral baseline.

| Predictor set | Balanced accuracy | Difference | 95% interval | Verdict |
|---|---|---|---|---|
| Spectral | 0.632 | baseline |  | baseline |
| Spectral and structure | 0.549 | -0.083 | -0.184 to -0.023 | disconfirmed |
| Spectral, structure and radar | 0.64 | +0.008 | -0.090 to +0.059 | inconclusive |


## Table 14

Pipeline test on synthetic data with known truth. The null regime must return balanced accuracy near one half and differences near zero; the planted regime must recover the structural signal.

| regime | model | balanced_accuracy | diff_from_spectral |
|---|---|---|---|
| null | spectral | 0.4935 | 0 |
| null | structure | 0.4667 | -0.0268 |
| null | all | 0.481 | -0.0125 |
| planted | spectral | 0.4482 | 0 |
| planted | structure | 0.9542 | 0.506 |
| planted | all | 0.9583 | 0.5101 |


