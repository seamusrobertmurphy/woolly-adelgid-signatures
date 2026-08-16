# Generate the root README from the rendered manuscript.
#
# The README carries the title, the abstract, and then every figure and table
# the manuscript contains, in the order the manuscript declares them, and
# nothing else. It is extracted from `01.manuscript/manuscript.html` rather
# than rebuilt from the derived data, so it cannot disagree with the paper:
# whatever the manuscript renders is what the front page shows.
#
# Tables are emitted as GitHub-flavoured pipe tables. GitHub renders the README,
# not Pandoc, and it prints Pandoc grid tables verbatim as a wall of plus signs.
# Figures are referenced as committed PNGs under 03.outputs/figures rather than
# embedded, so the README stays small.
#
# Usage: Rscript 05.scripts/04-build-readme.R

suppressMessages({
  library(xml2)
  library(rvest)
})

root <- normalizePath(".")
html_path <- file.path(root, "01.manuscript", "manuscript.html")
stopifnot(file.exists(html_path))
doc <- read_html(html_path)

# Quarto separates the float label from its number with a non-breaking space,
# U+00A0, which [[:space:]] does not match. Normalise it first or every
# caption fails a "Figure 1" test and the headings fall back to raw ids.
squash <- function(x) {
  x <- gsub("\u00a0", " ", x, useBytes = FALSE)
  trimws(gsub("[[:space:]]+", " ", x))
}

# Emit a data frame as a GFM pipe table, escaping any pipe in a cell.
gfm <- function(df) {
  cell <- function(v) gsub("|", "\\|", squash(as.character(v)), fixed = TRUE)
  hdr <- paste0("| ", paste(vapply(names(df), cell, ""), collapse = " | "), " |")
  sep <- paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|")
  rows <- vapply(seq_len(nrow(df)), function(i)
    paste0("| ", paste(vapply(df[i, ], cell, ""), collapse = " | "), " |"), "")
  paste(c(hdr, sep, rows), collapse = "\n")
}

title <- squash(html_text(html_element(doc, "h1.title")))
abstract <- squash(html_text(html_element(doc, "section.abstract, div.abstract")))
abstract <- sub("^Abstract\\s*", "", abstract)

# Every float, in document order, so the README follows the paper rather than a
# list maintained by hand that will fall behind it.
floats <- html_elements(doc, "div[id^='tbl-'], div[id^='fig-']")

blocks <- lapply(floats, function(el) {
  id <- xml_attr(el, "id")
  cap <- html_element(el, "figcaption, caption")
  # length() on an xml_node counts child nodes, so a caption holding only text
  # returns zero and a length test silently discards it. Test the class.
  has_cap <- !inherits(cap, "xml_missing")
  cap_txt <- if (has_cap) squash(html_text(cap)) else id
  # Quarto numbers the float inside the caption; keep it as the heading.
  head_txt <- sub("^(Table [0-9]+|Figure [0-9]+)[:.]?\\s*", "", cap_txt)
  num <- regmatches(cap_txt, regexpr("^(Table|Figure) [0-9]+", cap_txt))
  heading <- if (length(num)) num else id

  if (startsWith(id, "fig-")) {
    img <- html_element(el, "img")
    # The rendered document embeds the figure; the README points at the
    # committed file of the same name instead.
    body <- sprintf("![%s](03.outputs/figures/%s-1.png)", head_txt, id)
  } else {
    tb <- html_element(el, "table")
    if (inherits(tb, "xml_missing")) return(NULL)
    df <- html_table(tb, header = TRUE)
    df <- as.data.frame(df, check.names = FALSE)
    names(df) <- ifelse(names(df) == "" | is.na(names(df)),
                        paste0("V", seq_along(df)), names(df))
    body <- gfm(df)
  }
  paste0("## ", heading, "\n\n", head_txt, "\n\n", body, "\n")
})
blocks <- Filter(Negate(is.null), blocks)

# Scoping outputs that are not manuscript floats. They are the maps and tables
# that located the study and that scope its successors, so they belong on the
# front page even though the paper does not carry them. Listed explicitly rather
# than globbed, so a stray file in 03.outputs never lands on the README.
extra_figs <- list(
  c("fig-vi-agents-1.png", "Island agents",
    "Forest health damage agents recorded on and around Vancouver Island from 2020 onward, against LidarBC tile coverage. The twelve most recorded agents are named individually and the remaining twenty are coloured by class, so no polygon is filed under an undifferentiated other."),
  c("fig-adelgid-province-1.png", "Adelgid province-wide",
    "Balsam woolly adelgid across British Columbia, coloured by survey year. Triangles are moderate or worse severity, outlined black where lidar covers them and grey where it does not; small circles are trace and light."),
  c("fig-availability-1.png", "Damage and lidar",
    "Moderate or worse damage in the current survey year across British Columbia, against the extent of public lidar acquisition."))
extra_tabs <- list(
  c("vi-agents-2020plus.csv", "Island agent counts",
    "Every damage agent recorded on and around Vancouver Island from 2020 onward, with polygon counts, the number rated moderate or worse, and area."),
  c("sentinel-by-year.csv", "Sentinel by year",
    "Sentinel scenes per year over the Vancouver Island envelope. Radar halves after 2021 with the loss of Sentinel-1B and recovers in 2025 with Sentinel-1C."))

extra <- c()
for (f in extra_figs) {
  if (!file.exists(file.path(root, "03.outputs", "figures", f[1]))) next
  extra <- c(extra, paste0("## ", f[2]), "", f[3], "",
             sprintf("![%s](03.outputs/figures/%s)", f[3], f[1]), "")
}
for (t in extra_tabs) {
  fp <- file.path(root, "03.outputs", "tables", t[1])
  if (!file.exists(fp)) next
  d <- utils::read.csv(fp, stringsAsFactors = FALSE, check.names = FALSE)
  extra <- c(extra, paste0("## ", t[2]), "", t[3], "", gfm(d), "")
}

out <- c(paste0("# ", title), "", "## Abstract", "", abstract, "",
         unlist(lapply(blocks, function(b) c(b, ""))))
if (length(extra))
  out <- c(out, "## Availability", "",
           "Maps and tables that located this study and scope its successors. They are not floats in the manuscript.",
           "", extra)
writeLines(out, file.path(root, "README.md"))

cat("wrote README.md\n")
cat("  title:    ", substr(title, 1, 70), "\n")
cat("  abstract: ", nchar(abstract), "characters\n")
cat("  floats:   ", length(blocks), "\n")
cat("  appended: ", length(extra_figs), "figures and", length(extra_tabs), "tables\n")
