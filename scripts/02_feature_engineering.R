## ============================================================
## 02_feature_engineering.R
## Utility Non-Payment Risk & Consequence Model
##
## Turns each customer's 1,034-day daily consumption series into a
## compact set of statistical features. The guiding idea: a bill
## itself is just "usage x rate," so the earliest signal that a
## customer relationship with a utility is going wrong shows up in
## the *shape* of usage over time, well before a bill is missed --
## erratic day-to-day swings, a slow downward drift, unexplained
## zero-reading stretches, or usage that stops tracking normal
## seasonal (heating/cooling) demand.
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
})

out_dir <- "output"
dt      <- readRDS(file.path(out_dir, "clean_wide.rds"))
dates   <- readRDS(file.path(out_dir, "dates_sorted.rds"))

id_cols   <- c("CONS_NO", "FLAG")
date_cols <- setdiff(names(dt), id_cols)
stopifnot(length(date_cols) == length(dates))

X <- as.matrix(dt[, ..date_cols])   # customers x days, numeric, NAs present
n <- nrow(X); d <- ncol(X)
cat("Feature matrix:", n, "customers x", d, "days\n")

day_idx  <- seq_len(d)
wday     <- as.POSIXlt(dates)$wday                # 0 = Sunday
is_weekend <- wday %in% c(0, 6)
month_of   <- as.integer(format(dates, "%m"))
year_of    <- as.integer(format(dates, "%Y"))
is_winter  <- month_of %in% c(12, 1, 2)
is_summer  <- month_of %in% c(6, 7, 8)

row_mean_safe <- function(m) rowMeans(m, na.rm = TRUE)
row_sd_safe   <- function(m) apply(m, 1, sd, na.rm = TRUE)

## ---- basic distributional features ----
n_present   <- rowSums(!is.na(X))
pct_missing <- 1 - n_present / d

mean_kwh <- row_mean_safe(X)
sd_kwh   <- row_sd_safe(X)
cv_kwh   <- sd_kwh / pmax(mean_kwh, 1e-6)

max_kwh  <- apply(X, 1, function(r) suppressWarnings(max(r, na.rm = TRUE)))
min_kwh  <- apply(X, 1, function(r) suppressWarnings(min(r, na.rm = TRUE)))
max_kwh[!is.finite(max_kwh)] <- NA
min_kwh[!is.finite(min_kwh)] <- NA
range_ratio <- (max_kwh - min_kwh) / pmax(mean_kwh, 1e-6)

pct_zero_days <- rowSums(X == 0, na.rm = TRUE) / pmax(n_present, 1)

## ---- longest consecutive gap (NA run) as a fraction of the series ----
longest_na_run <- apply(is.na(X), 1, function(v) {
  r <- rle(v)
  if (!any(r$values)) return(0L)
  max(r$lengths[r$values])
})
longest_na_run_pct <- longest_na_run / d

## ---- trend: slope of usage regressed on day index, normalized ----
## (vectorized OLS slope per row, ignoring NAs)
trend_slope <- vapply(seq_len(n), function(i) {
  y <- X[i, ]; keep <- !is.na(y)
  if (sum(keep) < 30) return(NA_real_)
  xk <- day_idx[keep]; yk <- y[keep]
  xc <- xk - mean(xk)
  b  <- sum(xc * (yk - mean(yk))) / sum(xc^2)
  b
}, numeric(1))
## normalize slope by each customer's own mean level so it's comparable across customers
trend_slope_norm <- trend_slope / pmax(mean_kwh, 1e-6)

## ---- weekday vs weekend, seasonal, and year-over-year comparisons --------
## These start life as ratios (weekend/weekday, winter/summer, later-year/
## earlier-year), but a straight ratio explodes whenever the denominator
## period happens to sit near zero -- and with ~340 likely-vacant or
## near-zero-usage accounts in a file this size, "near zero" is common
## enough that outliers, not typical accounts, would end up driving any
## model fit on the raw ratio. We instead take the difference of
## log1p(mean usage) between the two periods (a log-ratio): it carries
## the same "which period was higher, and by roughly what multiple"
## information, but stays bounded and well-behaved as usage -> 0, instead
## of diverging to +/- infinity. A value of 0 means the two periods were
## equal; +0.7 means the second period averaged roughly 2x the first.
wkday_mean <- row_mean_safe(X[, !is_weekend, drop = FALSE])
wkend_mean <- row_mean_safe(X[, is_weekend, drop = FALSE])
weekend_ratio <- log1p(wkend_mean) - log1p(wkday_mean)

winter_mean <- row_mean_safe(X[, is_winter, drop = FALSE])
summer_mean <- row_mean_safe(X[, is_summer, drop = FALSE])
seasonal_ratio <- log1p(winter_mean) - log1p(summer_mean)

y14 <- row_mean_safe(X[, year_of == 2014, drop = FALSE])
y16 <- row_mean_safe(X[, year_of == 2016, drop = FALSE])
yoy_decline_ratio <- log1p(y16) - log1p(y14)   # negative means usage fell since 2014

## ---- month-to-month volatility ----
month_key <- paste(year_of, month_of, sep = "-")
month_means <- sapply(split(seq_len(d), month_key), function(idx) {
  row_mean_safe(X[, idx, drop = FALSE])
})
month_to_month_cv <- apply(month_means, 1, function(v) sd(v, na.rm = TRUE) / pmax(mean(v, na.rm = TRUE), 1e-6))

features <- data.table(
  CONS_NO            = dt$CONS_NO,
  FLAG               = dt$FLAG,
  pct_missing        = pct_missing,
  mean_kwh           = mean_kwh,
  sd_kwh             = sd_kwh,
  cv_kwh             = cv_kwh,
  range_ratio        = range_ratio,
  pct_zero_days      = pct_zero_days,
  longest_na_run_pct = longest_na_run_pct,
  trend_slope_norm   = trend_slope_norm,
  weekend_ratio      = weekend_ratio,
  seasonal_ratio     = seasonal_ratio,
  yoy_decline_ratio  = yoy_decline_ratio,
  month_to_month_cv  = month_to_month_cv
)

## ---- clean up infinities / impossible values produced by near-zero denominators ----
num_cols <- setdiff(names(features), c("CONS_NO", "FLAG"))
for (col in num_cols) {
  v <- features[[col]]
  v[!is.finite(v)] <- NA
  features[[col]] <- v
}

## ---- winsorize ratio-type features -------------------------------------
## A handful of accounts (almost certainly commercial/industrial meters
## mixed into this "residential" utility file) have usage in the
## thousands of kWh/day against otherwise ~5-10 kWh/day households. Any
## feature built as a ratio (weekend/weekday, winter/summer, year-over-
## year) can explode when its denominator period happens to sit near
## zero for one of these accounts. Rather than silently let a few
## outlier accounts dominate every ratio-based feature and any model
## trained on them, we winsorize (cap) each ratio feature at its 1st and
## 99th percentile. This is a deliberate, documented modeling choice --
## see the report for the before/after distribution.
ratio_cols <- c("range_ratio")
winsorize <- function(v, p = 0.01) {
  qs <- quantile(v, c(p, 1 - p), na.rm = TRUE)
  pmin(pmax(v, qs[1]), qs[2])
}
for (col in ratio_cols) features[[col]] <- winsorize(features[[col]])

## ---- log-transform heavily right-skewed magnitude features --------------
## mean/sd of daily kWh span several orders of magnitude across accounts;
## modeling log1p(x) keeps a few very large (likely commercial) accounts
## from dominating a linear model's fitted coefficients.
features[, log_mean_kwh := log1p(mean_kwh)]
features[, log_sd_kwh   := log1p(sd_kwh)]

cat("\nRows before dropping unusable customers (too little data):", nrow(features), "\n")
## Require at least 90 non-missing days (~3 months) to trust the features
features[, keep := (1 - pct_missing) * 1034 >= 90]
cat("Customers with < 90 recorded days (dropped):", sum(!features$keep), "\n")
features <- features[keep == TRUE]
features[, keep := NULL]

## Median-impute remaining NAs feature-by-feature (rare, from edge-case ratios)
for (col in num_cols) {
  v <- features[[col]]
  if (any(is.na(v))) {
    v[is.na(v)] <- median(v, na.rm = TRUE)
    features[[col]] <- v
  }
}

cat("Final feature table:", nrow(features), "customers x", ncol(features) - 2, "features\n")
cat("Class balance after filtering:\n"); print(table(features$FLAG))

saveRDS(features, file.path(out_dir, "features.rds"))
fwrite(features, file.path(out_dir, "features.csv"))
cat("\nSaved feature table to output/features.rds and output/features.csv\n")
cat("02_feature_engineering.R complete.\n")
