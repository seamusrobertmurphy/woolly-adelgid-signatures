# GENERATED FILE. Do not edit.
# Written from 01.manuscript/manuscript.qmd by the pipe-purl chunk.
# Edit the chunk in the manuscript and regenerate; edits here are lost.
# Run from the repository root.

suppressMessages({ library(sf); library(terra) })
root <- normalizePath('.')
inputs <- file.path(root, '02.inputs')
outputs <- file.path(root, '03.outputs')
derived <- file.path(inputs, 'derived')
BC_ALBERS <- 3005

# --- from chunk pipe-blocks, definitions this script depends on ---
blocks_path <- file.path(derived, "spatial-blocks.csv")
N_FOLDS <- 5L
N_BLOCKS <- 10L      # two blocks per fold at least, per the pre-registration
ADJ_M <- 50          # polygons within this distance share a block
SEED <- 20260815L


synth_path <- file.path(derived, "pipeline-test.csv")

# The estimator, defined once and used by both the test and the real analysis,
# so the test exercises the code that produces the result rather than a copy.
balanced_acc <- function(truth, pred, positive = "IAB") {
  truth <- as.character(truth); pred <- as.character(pred)
  tp <- sum(truth == positive & pred == positive)
  fn <- sum(truth == positive & pred != positive)
  tn <- sum(truth != positive & pred != positive)
  fp <- sum(truth != positive & pred == positive)
  sens <- if ((tp + fn) > 0) tp / (tp + fn) else NA_real_
  spec <- if ((tn + fp) > 0) tn / (tn + fp) else NA_real_
  (sens + spec) / 2
}

# Fit one nested model set over the given folds and return the per-fold
# balanced accuracy of each. Resampling is applied to training folds only, so
# reported performance refers to the observed class prevalence.
run_folds <- function(dat, sets, folds, seed = SEED) {
  out <- lapply(names(sets), function(nm) {
    vapply(sort(unique(folds)), function(f) {
      tr <- dat[folds != f, , drop = FALSE]
      te <- dat[folds == f, , drop = FALSE]
      if (length(unique(tr$y)) < 2 || nrow(te) == 0) return(NA_real_)
      # Upsample the minority class within the training fold only.
      n_max <- max(table(tr$y))
      set.seed(seed + f)
      idx <- unlist(lapply(unique(tr$y), function(l) {
        w <- which(tr$y == l)
        if (length(w) == n_max) w else sample(w, n_max, replace = TRUE)
      }))
      trb <- tr[idx, , drop = FALSE]
      vars <- sets[[nm]]
      fit <- ranger::ranger(
        x = trb[, vars, drop = FALSE], y = factor(trb$y),
        num.trees = 1000L, mtry = max(1L, floor(sqrt(length(vars)))),
        min.node.size = 5L, seed = seed + f, probability = FALSE)
      p <- predict(fit, data = te[, vars, drop = FALSE])$predictions
      balanced_acc(te$y, as.character(p))
    }, numeric(1))
  })
  names(out) <- names(sets)
  out
}

if (!file.exists(synth_path)) local({
  library(ranger)
  b <- read.csv(blocks_path, stringsAsFactors = FALSE)
  n <- nrow(b)
  n_spec <- 36L; n_struct <- 15L; n_rad <- 8L; n_cov <- 3L
  mk <- function(prefix, k) {
    m <- matrix(stats::rnorm(n * k), n, k)
    colnames(m) <- paste0(prefix, seq_len(k)); as.data.frame(m)
  }
  regime <- function(planted) {
    set.seed(SEED + as.integer(planted))
    y <- rep(c("IAB", "IBB"), length.out = n)
    d <- cbind(mk("s", n_spec), mk("t", n_struct), mk("r", n_rad),
               mk("c", n_cov))
    if (planted) {
      # A known separating signal in three structural predictors only, so a
      # correct pipeline must show structure beating spectral.
      shift <- ifelse(y == "IAB", 1.2, -1.2)
      for (v in c("t1", "t2", "t3")) d[[v]] <- d[[v]] + shift
    }
    d$y <- y
    sets <- list(
      spectral = c(paste0("s", seq_len(n_spec)), paste0("c", seq_len(n_cov))),
      structure = c(paste0("s", seq_len(n_spec)), paste0("t", seq_len(n_struct)),
                    paste0("c", seq_len(n_cov))),
      all = c(paste0("s", seq_len(n_spec)), paste0("t", seq_len(n_struct)),
              paste0("r", seq_len(n_rad)), paste0("c", seq_len(n_cov))))
    ba <- run_folds(d, sets, b$fold)
    data.frame(regime = if (planted) "planted" else "null",
               model = names(ba),
               balanced_accuracy = round(vapply(ba, mean, 0, na.rm = TRUE), 4),
               diff_from_spectral = round(
                 vapply(ba, function(v) mean(v - ba$spectral, na.rm = TRUE), 0), 4),
               stringsAsFactors = FALSE)
  }
  write.csv(rbind(regime(FALSE), regime(TRUE)), synth_path, row.names = FALSE)
})


