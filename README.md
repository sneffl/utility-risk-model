# Utility Non-Payment Risk & Consequence Model

By Hugo Garcia Moreno

This project forecasts an electricity bill from real weather, predicts
non-payment risk from real usage data, models how a bill's status evolves
over time as a Markov chain, and maps out what actually happens next, in
cited legal and financial detail, when a bill goes unpaid.

**Live web app:** https://hugogarcia.shinyapps.io/utility-risk-model/

**Try it in 10 seconds:** enter your last electric bill in the app's left
panel and every number recalibrates to your household.

**Full report:** open `report/report.html` in a browser. It's a
self-contained file with all charts and tables embedded, so no internet
connection is needed.

## The four parts

```
[Real NYC weather] --> [Degree-day regression] --> [Predicted monthly bill]
                                                            |
                                                            v
[Real SGCC usage data] --> [Logistic reg. + tree] --> [ML risk tier] --> [Markov chain risk engine] --> [P(disconnected), E[months to disconnect]]
                                                                                   ^
                                                                                   |
                                                                    [HEFPA-cited consequence cascade]
```

1. A statistical model (logistic regression and a decision tree, written
   in R from scratch) that estimates an account's risk of a serious
   non-payment or billing problem from the shape of its daily electricity
   usage over about 3 years: volatility, missing or zero reads, trend,
   and seasonality. Trained and evaluated on 33,787 real customers from a
   published utility dataset, with a test-set AUC around 0.75.
2. A weather-driven bill forecast using the standard utility degree-day
   method on 2015 NYC temperature history, calibrated so its summer
   cooling add-on matches NEADA's published Mid-Atlantic average. It also
   includes a heatwave shock simulator.
3. A discrete-time Markov chain modeling a bill's lifecycle (Current to
   Late to Severe to Disconnected) month by month, driven by the ML risk
   tier and a bill-to-income stress index. The matrix algebra (n-step
   transition matrices, the fundamental matrix, expected time to
   absorption) is implemented directly in base R. The report is clear
   about which inputs are fitted and which are stated assumptions, and a
   sensitivity analysis measures how much the assumptions matter.
4. A consequence cascade built from New York State's Home Energy Fair
   Practices Act (HEFPA) and consumer finance sources. It turns a missed
   bill into a day-by-day timeline, including the most useful fact in the
   whole project: a missed utility bill by itself generally does not hit
   your credit score. That only happens if the debt is referred to a
   collection agency.

These four are different kinds of claims, and the report keeps the
boundaries visible throughout. See Sections 1, 6, and 8.

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
  weather/nyc_weather_raw.csv   daily NYC weather history, included
output/
  features.csv                   the engineered per-customer feature table
  consequence_cascade.csv         the HEFPA timeline as data
  risk_tier_examples.csv          worked risk-tier examples
  monthly_bill_forecast.csv       the 2015 weather-driven monthly bill forecast
  markov_scenarios.csv            Markov chain scenario results (tier x income x bill)
  sensitivity_tornado.csv         sensitivity analysis results
  plots/                           all chart PNGs
shiny_app/
  app.R                            the public web app (self-contained, single file)
  README.md                        how to run it locally or deploy it
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
- Daily NYC-area weather history: [zonination/weather-us](https://github.com/zonination/weather-us)
  (public GitHub archive).
- NEADA, 2026 Summer Residential Cooling Outlook, used to calibrate the
  weather-driven forecast.

Consequence-cascade sources are cited individually in Section 7 of the
report (NY Dept. of Public Service / HEFPA, the Consumer Financial
Protection Bureau, and NY OTDA HEAP guidance).
