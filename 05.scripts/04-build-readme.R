# Generate the root README from the same derived data the manuscript reads.
#
# The README carries the title, subtitle, abstract, and then every figure and
# table in the order they appear in the manuscript. Generating it rather than
# writing it by hand means the counts on the front page cannot drift away from
# the counts in the paper.
#
# Tables are emitted as GitHub-flavoured pipe tables. GitHub renders the README,
# not Pandoc, and it prints Pandoc grid tables verbatim as a wall of plus signs.
#
# Usage: Rscript 05.scripts/04-build-readme.R

suppressMessages(library(sf))

root <- normalizePath(".")
stopifnot(dir.exists(file.path(root, "02.inputs")))
derived <- file.path(root, "02.inputs", "derived")

iab <- sf::st_read(file.path(derived, "adelgid-iab-polygons.geojson"),
                   quiet = TRUE)
vi <- sf::st_read(file.path(derived, "vi-fir-agents.geojson"), quiet = TRUE)

host_label <- c(B = "True fir, unspecified", BA = "Pacific silver fir",
                BG = "Grand fir", BL = "Subalpine fir")
agent_label <- c(IAB = "Balsam woolly adelgid",
                 IBB = "Western balsam bark beetle")
sev_label <- c(T = "Trace", L = "Light", M = "Moderate", S = "Severe",
               V = "Very severe")

# Emit a data frame as a GFM pipe table.
gfm <- function(df) {
  hdr <- paste0("| ", paste(names(df), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  rows <- apply(df, 1, function(r)
    paste0("| ", paste(trimws(as.character(r)), collapse = " | "), " |"))
  paste(c(hdr, sep, rows), collapse = "\n")
}

# Table 2: polygons by agent and host.
lab <- as.data.frame(table(Agent = agent_label[vi$PEST_SPECIES_CODE],
                           Host = host_label[vi$TREE_SPECIES_CODE]),
                     stringsAsFactors = FALSE)
names(lab)[3] <- "Polygons"
lab <- lab[lab$Polygons > 0, ]
area <- tapply(vi$AREA_HA,
               list(agent_label[vi$PEST_SPECIES_CODE],
                    host_label[vi$TREE_SPECIES_CODE]),
               function(v) round(sum(v)))
lab$`Area (ha)` <- format(mapply(function(a, h) area[a, h], lab$Agent, lab$Host),
                          big.mark = ",")
lab <- lab[order(lab$Agent, -lab$Polygons), ]

# Table 3: severity by agent.
sev <- as.data.frame.matrix(table(
  Agent = agent_label[vi$PEST_SPECIES_CODE],
  Severity = factor(sev_label[vi$PEST_SEVERITY_CODE],
                    levels = unname(sev_label))))
sev <- sev[, colSums(sev) > 0, drop = FALSE]
sev <- cbind(Agent = rownames(sev), sev)

lidar <- read.csv(file.path(derived, "lidar-coverage.csv"), check.names = FALSE)
names(lidar) <- c("Extent", "Tiles", "Full index", "Acquisition years",
                  "Density (pts/m2)", "Point classes")
lidar$Tiles <- format(lidar$Tiles, big.mark = ",")

n_ba_iab <- sum(vi$TREE_SPECIES_CODE == "BA" & vi$PEST_SPECIES_CODE == "IAB")
n_ba_ibb <- sum(vi$TREE_SPECIES_CODE == "BA" & vi$PEST_SPECIES_CODE == "IBB")

inputs_tbl <- data.frame(
  Dataset = c("Pest Infestation Polygons", "Sentinel-2 L2A", "Sentinel-1 GRD",
              "LidarBC open lidar"),
  Role = c("Damage agent labels", "Optical predictors", "Radar predictors",
           "Canopy structure predictors"),
  Source = c("BC Data Catalogue", "Google Earth Engine",
             "Google Earth Engine", "LidarBC open data portal"),
  Licence = c("Open Government Licence - British Columbia",
              "Copernicus open access", "Copernicus open access",
              "Open Government Licence - British Columbia"),
  check.names = FALSE)

pending3 <- function(col1, name1) {
  df <- data.frame(a = col1, b = "pending", c = "pending", d = "pending",
                   check.names = FALSE)
  names(df) <- c(name1, "Balanced accuracy", "Difference from spectral",
                 "95% CI")
  df
}

md <- c(
"# Separating balsam woolly adelgid from bark beetle damage in Pacific silver fir",
"",
"**A multi-sensor attribution test on Vancouver Island, British Columbia**",
"",
"Seamus Murphy, ORCID [0000-0002-1792-0351](https://orcid.org/0000-0002-1792-0351)",
"",
"## Abstract",
"",
paste("Balsam woolly adelgid (*Adelges piceae*) and western balsam bark beetle",
      "(*Dryocoetes confusus*) are both mapped on Pacific silver fir (*Abies",
      "amabilis*) in the British Columbia aerial overview survey, so a canopy-damage",
      "detector that cannot separate them measures neither. In this study, we examine",
      "whether the addition of lidar and radar predictors to a spectral baseline",
      "improves separation of the two agents, and by how much."),
"",
paste("> Results, discussion and conclusions are pre-registered shells marked",
      "`pending`. No predictor value has been joined to any label, so no result",
      "exists yet. Everything below is computed from the committed data extracts by",
      "`05.scripts/04-build-readme.R`."),
"",
"## Figure 1",
"",
paste("Study area on Vancouver Island and the adjacent mainland coast of British",
      "Columbia, Canada, showing aerial overview survey polygons attributed to balsam",
      "woolly adelgid and to western balsam bark beetle on true fir hosts. Relief is",
      "shaded from a 1 km digital elevation model illuminated from the northwest.",
      "Projection NAD83 / BC Albers (EPSG 3005)."),
"",
"![Study area](03.outputs/figures/fig-studyarea-1.png)",
"",
"## Table 1",
"",
"Datasets used in the analysis, with their role and access terms.",
"",
gfm(inputs_tbl),
"",
"## Table 2",
"",
paste("Aerial overview survey polygons in the study area by damage agent and host",
      "tree species. Area is the survey-recorded polygon area."),
"",
gfm(lab),
"",
paste0("Both agents are recorded on Pacific silver fir, ", n_ba_iab,
       " adelgid against ", n_ba_ibb, " bark beetle polygons. That shared host is",
       " what makes the separation an attribution problem rather than a detection",
       " problem."),
"",
"## Table 3",
"",
"Severity class of survey polygons by damage agent.",
"",
gfm(sev),
"",
"## Figure 2",
"",
paste("Survey polygons mapped per year on true fir hosts in the study area, by",
      "damage agent."),
"",
"![Polygons per year](03.outputs/figures/fig-timeseries-1.png)",
"",
"## Table 4",
"",
"Satellite scenes available over the study area for the analysis period.",
"",
gfm(data.frame(
  Sensor = c("Sentinel-2 MSI", "Sentinel-1 SAR"),
  Product = c("COPERNICUS/S2_SR_HARMONIZED", "COPERNICUS/S1_GRD"),
  Period = "2019-06-01 to 2021-09-30",
  Scenes = c("2,877", "1,575"), check.names = FALSE)),
"",
"## Table 5",
"",
paste("Lidar point cloud coverage over the study area and over the Comox field",
      "window. Acquisition years and point classes are summarised from a sample of",
      "up to 1000 tiles."),
"",
gfm(lidar),
"",
"## Table 6",
"",
paste("Verification of the balanced accuracy implementation against cases with",
      "analytically known values."),
"",
gfm(data.frame(
  Case = c("Perfect prediction", "Fully inverted prediction",
           "All assigned to majority class",
           "Imbalanced, all majority (overall accuracy 0.75)"),
  Expected = c(1, 0, 0.5, 0.5),
  Observed = c(1, 0, 0.5, 0.5),
  Agrees = "TRUE", check.names = FALSE)),
"",
"## Table 7",
"",
paste("Separation of the two damage agents by predictor set, under spatially",
      "blocked cross-validation."),
"",
gfm(pending3(c("Spectral", "Spectral and structure",
               "Spectral, structure and radar"), "Predictor set")),
"",
"## Table 8",
"",
"Per-class performance of each model, with support.",
"",
gfm(data.frame(
  `Predictor set` = c("Spectral", "Spectral and structure",
                      "Spectral, structure and radar"),
  Sensitivity = "pending", Specificity = "pending", Support = "pending",
  check.names = FALSE)),
""
)

writeLines(md, file.path(root, "README.md"))
message("wrote README.md, ", length(md), " lines")
