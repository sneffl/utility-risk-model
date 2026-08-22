## ============================================================
## 06_weather_bill_forecast.R
## Utility Non-Payment Risk & Consequence Model -- weather module
##
## Ties a household's predicted bill to real local weather, using the
## standard utility-industry degree-day method (the same logic behind
## "weather normalization" in real rate cases): electricity demand for
## heating and cooling scales with how far the day's temperature sits
## from a 65F balance point, not with temperature itself.
##
## DATA: real daily NYC temperature records, 1948-2015 (Central-Park-
## area station history, aggregated by the public "weather-us" GitHub
## dataset -- https://github.com/zonination/weather-us). We use full-
## year 2015 to line up with the SGCC electricity data's own 2014-2016
## window used elsewhere in this project.
##
## CALIBRATION: the baseload + heating/cooling sensitivity constants
## below are NOT fit to any individual real customer's bill (no such
## paired weather+billing dataset is public). They ARE calibrated so
## that a full cooling season's predicted add-on matches NEADA's
## published 2026 Mid-Atlantic average summer cooling bill of $790
## [see report Section 5 for the citation]. That is real, cited,
## external validation of the *scale* of the model -- not a claim that
## it reproduces any specific bill.
## ============================================================

suppressPackageStartupMessages(library(data.table))

out_dir <- "output"
w <- fread("data/weather/nyc_weather_raw.csv")
w[, Date := as.Date(Date)]
w <- w[!is.na(`Mean.TemperatureF`)]

w2015 <- w[Date >= as.Date("2015-01-01") & Date <= as.Date("2015-12-31")]
cat("2015 NYC daily records:", nrow(w2015), "\n")

BALANCE_POINT <- 65
w2015[, HDD := pmax(BALANCE_POINT - Mean.TemperatureF, 0)]
w2015[, CDD := pmax(Mean.TemperatureF - BALANCE_POINT, 0)]
w2015[, month := format(Date, "%Y-%m")]

monthly <- w2015[, .(HDD = sum(HDD), CDD = sum(CDD), mean_temp = mean(Mean.TemperatureF)), by = month]
setorder(monthly, month)

## ---- calibrate cooling sensitivity against the real NEADA figure --------
## NEADA (2026): projected avg Mid-Atlantic summer cooling bill = $790
## across the cooling season (Jun-Sep). We treat that as the total
## COOLING ADD-ON over those months (baseload excluded) and solve for
## a $/CDD rate against 2015's actual Jun-Sep CDD total.
neada_midatlantic_summer_cooling_bill <- 790
summer_months <- monthly[month %in% c("2015-06", "2015-07", "2015-08", "2015-09")]
total_summer_cdd <- sum(summer_months$CDD)
cooling_rate_per_cdd <- neada_midatlantic_summer_cooling_bill / total_summer_cdd
cat("2015 Jun-Sep total CDD:", round(total_summer_cdd, 1),
    " -> calibrated cooling rate: $", round(cooling_rate_per_cdd, 3), "/CDD\n", sep = "")

## Heating sensitivity: residential gas heat is far more common than electric
## resistance heat in the Northeast, so the ELECTRIC bill's heating-season
## response is smaller than its cooling-season response per degree-day.
## We set it at 40% of the cooling rate -- a stated, illustrative
## assumption (electric heat pumps and supplemental space heaters still
## draw real load), not a second NEADA-anchored figure.
heating_rate_per_hdd <- 0.40 * cooling_rate_per_cdd

BASELOAD <- 45   # non-weather-sensitive monthly baseload ($): lighting, fridge, electronics

monthly[, predicted_bill := BASELOAD + heating_rate_per_hdd * HDD + cooling_rate_per_cdd * CDD]

cat("\n--- Predicted monthly electric bill, 2015, NYC-area household ---\n")
print(monthly[, .(month, mean_temp = round(mean_temp, 1), HDD = round(HDD, 1),
                   CDD = round(CDD, 1), predicted_bill = round(predicted_bill, 2))])

## ============================================================
## Weather-shock simulator: inject a real-magnitude heatwave
## ============================================================
## Historical NYC heatwaves run 5-7 days with highs around 95-100F
## (mean daily temp ~90F is a reasonable stand-in). We replace 6 days
## of the model's hottest month (by mean_temp) with a heatwave and
## recompute that month's CDD and predicted bill.
hottest_month <- monthly[which.max(mean_temp)]$month
hw_days <- w2015[month == hottest_month][order(-Mean.TemperatureF)][1:6]$Date
w2015_shock <- copy(w2015)
w2015_shock[Date %in% hw_days, Mean.TemperatureF := 90]
w2015_shock[, CDD := pmax(Mean.TemperatureF - BALANCE_POINT, 0)]
w2015_shock[, HDD := pmax(BALANCE_POINT - Mean.TemperatureF, 0)]

shock_month <- w2015_shock[month == hottest_month, .(HDD = sum(HDD), CDD = sum(CDD))]
shock_bill <- BASELOAD + heating_rate_per_hdd * shock_month$HDD + cooling_rate_per_cdd * shock_month$CDD
baseline_bill <- monthly[month == hottest_month]$predicted_bill

cat("\n--- Weather-shock scenario:", hottest_month, "---\n")
cat("Baseline predicted bill: $", round(baseline_bill, 2), "\n", sep = "")
cat("With a 6-day heatwave (mean temp -> 90F): $", round(shock_bill, 2), "\n", sep = "")
cat("Shock increase: $", round(shock_bill - baseline_bill, 2),
    " (", round(100 * (shock_bill / baseline_bill - 1), 1), "%)\n", sep = "")

weather_results <- list(
  monthly = monthly,
  BASELOAD = BASELOAD,
  cooling_rate_per_cdd = cooling_rate_per_cdd,
  heating_rate_per_hdd = heating_rate_per_hdd,
  hottest_month = hottest_month,
  baseline_bill = baseline_bill,
  shock_bill = shock_bill,
  neada_citation = "NEADA, 2026 Summer Residential Cooling Outlook -- Mid-Atlantic avg summer cooling bill $790"
)
saveRDS(weather_results, file.path(out_dir, "weather_results.rds"))
fwrite(monthly, file.path(out_dir, "monthly_bill_forecast.csv"))

cat("\nSaved weather_results.rds and monthly_bill_forecast.csv\n")
cat("06_weather_bill_forecast.R complete.\n")
