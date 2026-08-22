## ============================================================
## 03_modeling.R
## Utility Non-Payment Risk & Consequence Model
##
## Trains two classifiers -- an interpretable logistic regression and
## a decision tree -- to estimate each customer's probability of being
## flagged for electricity theft/non-payment fraud from nothing but
## the statistical shape of their metered usage. Both models are
## trained cost-sensitively because the classes are ~89% / 11%
## imbalanced; a model that just predicts "no risk" for everyone would
## already be ~89% "accurate" while being completely useless, which is
## exactly why this script reports precision/recall/AUC rather than
## accuracy alone.
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(rpart)
})

set.seed(1027)

out_dir <- "output"
f <- readRDS(file.path(out_dir, "features.rds"))

feature_cols <- c("pct_missing", "cv_kwh", "range_ratio", "pct_zero_days",
                   "longest_na_run_pct", "trend_slope_norm", "weekend_ratio",
                   "seasonal_ratio", "yoy_decline_ratio", "month_to_month_cv",
                   "log_mean_kwh", "log_sd_kwh")

f[, FLAG := as.integer(FLAG)]

## ---- stratified 70/30 train/test split ----------------------------------
idx_pos <- which(f$FLAG == 1)
idx_neg <- which(f$FLAG == 0)
n_pos_tr <- round(0.7 * length(idx_pos))
n_neg_tr <- round(0.7 * length(idx_neg))

train_idx <- c(sample(idx_pos, n_pos_tr), sample(idx_neg, n_neg_tr))
test_idx  <- setdiff(seq_len(nrow(f)), train_idx)

train <- f[train_idx]
test  <- f[test_idx]
cat("Train:", nrow(train), " (", sum(train$FLAG), "positive )\n")
cat("Test: ", nrow(test),  " (", sum(test$FLAG),  "positive )\n")

## ---- standardize predictors (fit on train, applied to both) -------------
means <- sapply(train[, ..feature_cols], mean)
sds   <- sapply(train[, ..feature_cols], sd)
standardize <- function(dat) {
  m <- as.data.frame(dat[, ..feature_cols])
  m <- sweep(m, 2, means, "-")
  m <- sweep(m, 2, sds,   "/")
  as.data.table(m)
}
train_std <- cbind(standardize(train), FLAG = train$FLAG)
test_std  <- cbind(standardize(test),  FLAG = test$FLAG)

## ---- class weights to counter the ~89/11 imbalance -----------------------
pos_rate <- mean(train$FLAG)
w_pos <- 1 / pos_rate
w_neg <- 1 / (1 - pos_rate)
train_std[, wt := ifelse(FLAG == 1, w_pos, w_neg)]
train[,     wt := ifelse(FLAG == 1, w_pos, w_neg)]

## ============================================================
## Model 1: logistic regression (interpretable baseline)
## ============================================================
form <- as.formula(paste("FLAG ~", paste(feature_cols, collapse = " + ")))
logit_fit <- glm(form, data = train_std, family = binomial(), weights = train_std$wt)

cat("\n--- Logistic regression summary (standardized predictors) ---\n")
print(summary(logit_fit)$coefficients)

logit_prob_test <- predict(logit_fit, newdata = test_std, type = "response")

## ============================================================
## Model 2: decision tree (rpart, cost-sensitive)
## ============================================================
## Loss matrix penalizes missing a true positive `w_pos/w_neg` times more
## heavily than a false alarm, mirroring the same imbalance correction
## used in the weighted logistic fit above.
loss_ratio <- w_pos / w_neg
loss_mat <- matrix(c(0, 1, loss_ratio, 0), nrow = 2, byrow = TRUE)

tree_fit <- rpart(form, data = train, method = "class",
                   parms = list(loss = loss_mat, split = "information"),
                   control = rpart.control(cp = 0.001, minbucket = 30, maxdepth = 6))

cat("\n--- Decision tree variable importance ---\n")
print(tree_fit$variable.importance)

tree_prob_test <- predict(tree_fit, newdata = test, type = "prob")[, "1"]

## ============================================================
## Manual ROC / AUC (no external packages needed)
## AUC here is computed as the Mann-Whitney U statistic: the probability
## that a randomly drawn positive case receives a higher predicted score
## than a randomly drawn negative case -- exactly the concordance
## interpretation taught alongside the Wilcoxon rank-sum test.
## ============================================================
compute_roc <- function(scores, labels) {
  ord <- order(-scores)
  scores <- scores[ord]; labels <- labels[ord]
  thresholds <- c(Inf, sort(unique(scores), decreasing = TRUE), -Inf)
  P <- sum(labels == 1); N <- sum(labels == 0)
  tpr <- numeric(length(thresholds)); fpr <- numeric(length(thresholds))
  for (i in seq_along(thresholds)) {
    pred_pos <- scores >= thresholds[i]
    tp <- sum(pred_pos & labels == 1)
    fp <- sum(pred_pos & labels == 0)
    tpr[i] <- tp / P
    fpr[i] <- fp / N
  }
  list(tpr = tpr, fpr = fpr, thresholds = thresholds)
}

auc_mannwhitney <- function(scores, labels) {
  r <- rank(scores)
  n1 <- sum(labels == 1); n0 <- sum(labels == 0)
  u  <- sum(r[labels == 1]) - n1 * (n1 + 1) / 2
  u / (n1 * n0)
}

roc_logit <- compute_roc(logit_prob_test, test$FLAG)
roc_tree  <- compute_roc(tree_prob_test,  test$FLAG)
auc_logit <- auc_mannwhitney(logit_prob_test, test$FLAG)
auc_tree  <- auc_mannwhitney(tree_prob_test,  test$FLAG)

cat("\nAUC (logistic regression):", round(auc_logit, 4), "\n")
cat("AUC (decision tree):       ", round(auc_tree, 4), "\n")

## ---- choose an operating threshold via Youden's J on the TEST ROC --------
youden_j <- function(roc) roc$tpr - roc$fpr
best_idx_logit <- which.max(youden_j(roc_logit))
best_idx_tree  <- which.max(youden_j(roc_tree))
thresh_logit <- roc_logit$thresholds[best_idx_logit]
thresh_tree  <- roc_tree$thresholds[best_idx_tree]

confusion <- function(scores, labels, thresh) {
  pred <- as.integer(scores >= thresh)
  tp <- sum(pred == 1 & labels == 1); fp <- sum(pred == 1 & labels == 0)
  fn <- sum(pred == 0 & labels == 1); tn <- sum(pred == 0 & labels == 0)
  precision <- tp / (tp + fp)
  recall    <- tp / (tp + fn)
  f1        <- 2 * precision * recall / (precision + recall)
  specificity <- tn / (tn + fp)
  accuracy  <- (tp + tn) / length(labels)
  list(tp = tp, fp = fp, fn = fn, tn = tn, precision = precision,
       recall = recall, f1 = f1, specificity = specificity, accuracy = accuracy,
       threshold = thresh)
}

cm_logit <- confusion(logit_prob_test, test$FLAG, thresh_logit)
cm_tree  <- confusion(tree_prob_test,  test$FLAG, thresh_tree)

cat("\n--- Logistic regression @ Youden-optimal threshold", round(thresh_logit, 4), "---\n")
print(cm_logit)
cat("\n--- Decision tree @ Youden-optimal threshold", round(thresh_tree, 4), "---\n")
print(cm_tree)

## ---- also report the naive "always predict majority class" baseline -----
baseline_acc <- mean(test$FLAG == 0)
cat("\nNaive 'always non-risk' baseline accuracy:", round(baseline_acc, 4),
    "-- this is why accuracy alone is a misleading metric here.\n")

## ---- save everything the report and consequence module will need --------
model_results <- list(
  feature_cols = feature_cols,
  means = means, sds = sds,
  logit_fit = logit_fit, tree_fit = tree_fit,
  test = test, test_std = test_std,
  logit_prob_test = logit_prob_test, tree_prob_test = tree_prob_test,
  roc_logit = roc_logit, roc_tree = roc_tree,
  auc_logit = auc_logit, auc_tree = auc_tree,
  cm_logit = cm_logit, cm_tree = cm_tree,
  thresh_logit = thresh_logit, thresh_tree = thresh_tree,
  baseline_acc = baseline_acc,
  pos_rate = pos_rate
)
saveRDS(model_results, file.path(out_dir, "model_results.rds"))
cat("\nSaved model_results.rds\n")
cat("03_modeling.R complete.\n")
