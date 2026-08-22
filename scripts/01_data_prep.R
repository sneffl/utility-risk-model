## ============================================================
## 01_data_prep.R
## Utility Non-Payment Risk & Consequence Model
##
## Loads the raw SGCC (State Grid Corporation of China) real-world
## electricity consumption dataset, cleans it, orders the daily
## reading columns chronologically, and saves a tidy wide matrix
## plus a long (tidy) version for downstream feature engineering.
##
## Source: Zheng, Yang, Niu, Dai & Zhou (2018), "Wide and Deep
## Convolutional Neural Networks for Electricity-Theft Detection to
## Secure Smart Grids," IEEE Transactions on Industrial Informatics,
## 14(4), 1606-1615. https://doi.org/10.1109/TII.2017.2785963
## 42,372 real electricity customers, Jan 1 2014 - Oct 31 2016.
## FLAG = 1 marks customers confirmed by the utility to have been
## engaged in electricity theft / billing fraud (the closest publicly
## available, individually-labeled real-world proxy for serious
## utility non-payment behavior).
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
})

set.seed(1027)

raw_path <- "data/data.csv"
out_dir  <- "output"
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

cat("Reading raw CSV (this is a ~140MB file, 33,841 rows)...\n")
dt <- fread(raw_path, showProgress = FALSE)

cat("Raw dimensions:", nrow(dt), "rows x", ncol(dt), "cols\n")

## --- Drop malformed rows (fread flags them via warnings; re-check directly) ---
n_before <- nrow(dt)
dt <- dt[!is.na(CONS_NO) & !is.na(FLAG)]
cat("Dropped", n_before - nrow(dt), "malformed row(s) with missing ID/FLAG.\n")

## --- Identify date columns and parse them ---
id_cols   <- c("CONS_NO", "FLAG")
date_cols <- setdiff(names(dt), id_cols)

parsed_dates <- as.Date(date_cols, format = "%Y/%m/%d")
stopifnot(sum(is.na(parsed_dates)) == 0)

## Order date columns chronologically (they arrive out of order in the raw file)
ord <- order(parsed_dates)
date_cols_sorted  <- date_cols[ord]
dates_sorted      <- parsed_dates[ord]

cat("Date range:", format(min(dates_sorted)), "to", format(max(dates_sorted)),
    "(", length(dates_sorted), "days )\n")

## Reorder columns: ID, FLAG, then chronological daily readings
setcolorder(dt, c(id_cols, date_cols_sorted))

## --- Coerce consumption columns to numeric (blanks -> NA already handled by fread) ---
for (col in date_cols_sorted) {
  if (!is.numeric(dt[[col]])) dt[[col]] <- suppressWarnings(as.numeric(dt[[col]]))
}

## --- Basic sanity / class balance ---
flag_tab <- table(dt$FLAG)
cat("\nClass balance (FLAG):\n"); print(flag_tab)
cat("Positive (theft/non-payment-flagged) rate:",
    round(100 * flag_tab["1"] / sum(flag_tab), 2), "%\n")

## --- Missingness overview ---
consumption_mat <- as.matrix(dt[, ..date_cols_sorted])
overall_missing_rate <- mean(is.na(consumption_mat))
cat("Overall missing-reading rate:", round(100 * overall_missing_rate, 2), "%\n")

## --- Save cleaned artifacts for downstream scripts ---
saveRDS(dt, file.path(out_dir, "clean_wide.rds"))
saveRDS(dates_sorted, file.path(out_dir, "dates_sorted.rds"))

cat("\nSaved cleaned wide table + date index to", out_dir, "\n")
cat("01_data_prep.R complete.\n")
