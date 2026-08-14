# Verify all downloaded inputs against the checksums recorded at download
# (02.inputs/SHA256SUMS.txt). Run after any fresh download and before analysis
# sessions. Fails loudly: a silent mismatch is the failure mode this guards.
inputs <- file.path(dirname(sub("--file=", "", grep("--file=", commandArgs(FALSE),
                    value = TRUE))), "..", "02.inputs")
manifest <- read.table(file.path(inputs, "SHA256SUMS.txt"),
                       col.names = c("sha256", "file"))
manifest$verified <- vapply(manifest$file, function(f) {
  h <- system2("shasum", c("-a", "256", shQuote(file.path(inputs, f))),
               stdout = TRUE)
  identical(strsplit(h, " ")[[1]][1], manifest$sha256[manifest$file == f])
}, logical(1))
print(manifest[, c("file", "verified")])
stopifnot(all(manifest$verified))
cat("all inputs verified\n")
