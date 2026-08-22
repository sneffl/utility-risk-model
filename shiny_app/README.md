# Utility Risk & Bill Forecast Shiny app

The web app version of the project. Forecast your electricity bill from
real weather, see how a random weather shock changes it, watch where your
bill's status ends up over 24 months via a Markov chain, and see what a
collections mark could cost on your next car loan.

Live instance: https://hugogarcia.shinyapps.io/utility-risk-model/

Everything lives in one self-contained file, `app.R`. No other project
files are needed to run it. It uses small hand-calibrated constants
instead of the full model files from the main analysis, so it's light
enough for free-tier hosting.

## Run it locally

```r
install.packages(c("shiny", "bslib", "plotly", "DT", "shinycssloaders"))
shiny::runApp("app.R")
```

## Deploy it (shinyapps.io, free tier)

The free tier gives 25 active hours a month and needs no credit card.

1. Sign up at https://www.shinyapps.io (free plan).
2. On the dashboard, go to Account, then Tokens, click Show secret, and
   copy the `setAccountInfo(...)` snippet.
3. In R, in this folder:

```r
install.packages("rsconnect")
rsconnect::setAccountInfo(name = "<your-name>", token = "<your-token>", secret = "<your-secret>")
rsconnect::deployApp(appName = "utility-risk-model")
```

4. It prints a public URL when it finishes. That's the link for a resume
   or LinkedIn.

## What's measured and what's assumed

Same rule as the full report, condensed for a public UI.

The weather forecast uses 2015 NYC temperature history and is calibrated
to NEADA's published average cooling bill. The risk tier you pick is a
plain-language stand-in for the fitted classifier's output tiers, since
the classifier needs 3 years of smart-meter statistics per account and
nobody can type that into a web form. The Markov chain transition
probabilities are stated modeling assumptions rather than measurements,
because no public dataset tracks individual month-by-month delinquency
transitions (the report's sensitivity analysis measures how much this
matters). The auto-loan APR table is Experian's published Q1 2026 data by
credit tier, and the credit-score-drop range is a commonly cited industry
estimate rather than an official FICO figure.

This app is an educational tool, not financial advice. The About tab says
so, and that disclaimer should stay if the app is shared publicly.
