# Study scope and the constraints that fixed it

2026-08-13: The species is balsam woolly adelgid (*Adelges piceae*), not hemlock woolly
adelgid, despite the repository name. Hemlock woolly adelgid does not damage forests in
British Columbia and the aerial overview survey standards carry no code for it, so it
could never have been mapped. Matters because the repository name will keep suggesting
otherwise. Rests on MacQuarrie et al. 2025 (doi 10.4039/tce.2025.2), the CFIA fact sheet,
and the survey standards code list read at
`www2.gov.bc.ca/assets/gov/environment/natural-resource-stewardship/nr-laws-policy/risc/aerial.pdf`.

2026-08-14: Existing public lidar cannot support a moderate-and-above severity floor
anywhere in British Columbia. Adelgid polygons rated moderate or worse that fall under
LidarBC coverage number zero at 1, 3, 5 and 10 year offsets and one at 20 years. Matters
because it is the binding constraint on the whole design and no choice of study area
changes it; do not re-propose a high-severity structural study. Rests on
`05.scripts/13-data-availability-first.R` and the sensitivity table in commit `18d32f7`.

2026-08-14: The analysis set is 132 polygons, 53 adelgid and 79 bark beetle, on Pacific
silver fir, under lidar acquired within five years of the survey, frozen at
`02.inputs/derived/analysis-set.geojson`. Class imbalance 1.5 to 1, median offset 2 years.
Matters because it is the sample and nothing downstream should filter it again. Rests on
`05.scripts/14-build-analysis-set.R`.

2026-08-14: The bark beetle comparison class is a complex, not a single agent. Western
balsam bark beetle acts with *Armillaria*, *Ophiostoma dryocoetidis* and spruce beetle on
true fir. Matters because it is a property of the system that no labelling scheme fixes,
and the manuscript describes the class as bark-beetle-associated mortality throughout.
Rests on Lalande, Hughes and Jacobi 2020 and Klutsch et al. 2014
(doi 10.1016/j.foreco.2013.12.024).
