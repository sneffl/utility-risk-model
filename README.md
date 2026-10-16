# Behind on the Bill

**Live at [behindonthebill.com](https://behindonthebill.com)** · Built by Hugo Garcia Moreno, math student at BMCC (CUNY)

I grew up in a house where the electric bill was a source of stress, and the
worst part was not knowing what came next. When does the late fee hit? When
can they actually shut the power off? So I built the thing I wish we had.

Put your last electric bill into the first sentence on the site and it tells
you three things:

1. **What your bill should be every month.** I use 78 years of NOAA weather
   for Central Park (1948 to 2025) and the degree-day method utilities use
   themselves. Each month also shows the range it landed in 8 out of 10 years.
2. **Your real chance of a shutoff.** I trained a logistic regression and a
   decision tree on three years of daily meter readings from 33,787 real
   customers (test AUC 0.755). Then I modeled the path from a late bill to a
   shutoff as a Markov chain, month by month.
3. **What to do today if you're behind.** New York's HEFPA law says the
   utility has to offer a payment plan you can afford. The site works out that
   plan, writes the request letter for you, and lists hotlines I checked
   myself. It never asks for or saves anything personal.

## How I checked my own work

I didn't want to just trust my R code, so I rebuilt the shutoff model in
Python (`python/`). A script pulls the formulas straight out of the site's R
code, and 26 tests show both versions agree to 12 decimal places. Then I
checked it a second way, by simulating 400,000 households month by month and
counting how many get cut off. The simulation and the formula never disagree
by more than about a tenth of a percentage point.

A second Python script keeps the weather current. It downloads NOAA's data,
checks that no month is missing and that the numbers add up, rebuilds the
tables the site reads, and fits the climate trend (summers need about 15%
more cooling than in 1948, winters about 11% less heating).

## What's real and what's my assumption

I try to be upfront about this. The weather, the meter data, the late fee
and the shutoff rules are real and cited. What happens after an account goes
late (does it catch up or keep sliding) uses probabilities I picked, because
nobody publishes that data. I tested how much that matters: moving every
assumed number 20% up or down never changed the one year shutoff chance by
more than about 3 points. The full write-up is in `report/report.html`. Open it
in a browser, everything is built in.

## Repository layout

```
scripts/
  01_data_prep.R              load and clean the raw SGCC dataset, order dates
  02_feature_engineering.R    12 per-customer statistical features
  03_modeling.R                logistic regression + decision tree, ROC/AUC
  04_consequences.R            HEFPA-derived consequence cascade + HEAP screen
  05_plots.R                    figures for the usage-risk model
  06_weather_bill_forecast.R   NYC-weather degree-day bill forecast + heatwave shock
  07_markov_chain.R             absorbing Markov chain risk engine (base R linear algebra)
  08_plots_weather_markov.R     figures for the weather + Markov modules
  09_sensitivity.R              tornado + Monte Carlo sensitivity analysis of the Markov assumptions
report/
  report.Rmd                    full write-up, source
  report.html                   knitted, self-contained report (open this)
data/
  README.md                     SGCC dataset citation and download instructions
  weather/nyc_weather_raw.csv   daily NYC weather history 1948-2015, included
  weather/nyc_central_park_monthly_noaa.csv   NOAA monthly degree days, 1948 onward
output/
  features.csv                   the engineered per-customer feature table
  consequence_cascade.csv         the HEFPA timeline as data
  risk_tier_examples.csv          worked risk-tier examples
  monthly_bill_forecast.csv       the 2015 weather-driven monthly bill forecast
  markov_scenarios.csv            Markov chain scenario results (tier x income x bill)
  sensitivity_tornado.csv         sensitivity analysis results
  plots/                           all chart PNGs
shiny_app/
  app.R                            the site (R Shiny)
  www/fonts/                       the site's fonts (Archivo, Atkinson Hyperlegible)
  data/                            weather tables the app reads (written by python/update_weather.py)
  README.md                        how to run it locally or deploy it
python/
  update_weather.py                downloads NOAA weather, checks it, rebuilds the site's data, fits the climate trend
  test_update_weather.py           10 tests for the weather pipeline
  markov_shutoff.py                the shutoff model in NumPy, plus a household simulation
  test_markov_shutoff.py           26 tests, including exact matches against the R app
  export_r_reference.R             pulls the model out of app.R and saves its answers
  README.md                        what the Python check proves and what it doesn't
explainer/
  project_explainer.md             a plain-language explanation of the whole project
```

## Reproducing it

Requires R (4.0 or newer) with `data.table`, `ggplot2`, `rpart`,
`rmarkdown`, and `knitr`, all available from CRAN.

1. Download the raw SGCC dataset into `data/data.csv` (see
   `data/README.md`). The NYC weather data for scripts 06 to 09 is
   already included.
2. Run the scripts in order, 01 through 09.
3. Knit the report: `Rscript -e 'rmarkdown::render("report/report.Rmd")'`

No paid API and no GPU needed at any step. Once the two data files are in
place, everything runs offline.

## Data sources

- Zheng, Z., Yang, Y., Niu, X., Dai, H.-N., & Zhou, Y. (2018). "Wide and Deep
  Convolutional Neural Networks for Electricity-Theft Detection to Secure
  Smart Grids." *IEEE Transactions on Industrial Informatics*, 14(4),
  1606-1615. https://doi.org/10.1109/TII.2017.2785963
- Monthly heating and cooling degree days, New York Central Park station
  (USW00094728), 1948 onward: NOAA National Centers for Environmental
  Information, Global Summary of the Month. Downloaded and checked by
  `python/update_weather.py`, saved in `data/weather/nyc_central_park_monthly_noaa.csv`.
- Daily NYC-area weather history, 1948 to 2015: [zonination/weather-us](https://github.com/zonination/weather-us)
  (public GitHub archive). Used by the report scripts and for the site's
  replayed heat waves and cold snaps.
- NEADA, 2026 Summer Residential Cooling Outlook, used to calibrate the
  weather-driven forecast.

Consequence-cascade sources are cited individually in Section 7 of the
report (NY Dept. of Public Service / HEFPA, the Consumer Financial
Protection Bureau, and NY OTDA HEAP guidance).
