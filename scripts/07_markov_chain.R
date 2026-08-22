## ============================================================
## 07_markov_chain.R
## Utility Non-Payment Risk & Consequence Model -- stochastic risk engine
##
## Models a bill's lifecycle explicitly as a discrete-time Markov chain
## over four states, one calendar month per step, aligned with the
## HEFPA timeline in 04_consequences.R (a ~35-day notice-to-disconnection
## window is, for modeling purposes, "about one month"):
##
##   1. Current          -- paid on time
##   2. Late              -- 1-30 days past due (Final Termination Notice window)
##   3. Severe             -- 31-60+ days past due (disconnection-eligible)
##   4. Disconnected      -- absorbing state in this model
##
## Two things feed the transition probabilities, deliberately kept
## distinct in provenance:
##   (a) the ML risk tier from 03_modeling.R (Low/Elevated/High) sets how
##       easily an account slips from Current into Late in the first
##       place -- this IS grounded in the fitted classifier's operating
##       thresholds.
##   (b) a bill-to-income "stress index" -- the predicted bill from
##       06_weather_bill_forecast.R divided by an assumed monthly income
##       -- sets how likely an already-late account is to cure or
##       progress. These particular functional forms and coefficients
##       are ILLUSTRATIVE MODELING ASSUMPTIONS, stated as such: no public
##       dataset labels real month-by-month delinquency transitions at
##       the individual level, so there is nothing to fit them to. What
##       IS real: the HEFPA timing structure, the ML risk tiers, and the
##       weather-driven bill. The transition-probability *functions*
##       connecting them are a modeling choice, and this file says so
##       instead of quietly presenting them as measured.
##
## All matrix algebra (n-step transition matrices, the fundamental
## matrix, expected time to absorption) is implemented directly with
## base R linear algebra rather than a canned package call, since the
## point of this file is to show the mechanics, not hide them behind
## one function call.
## ============================================================

suppressPackageStartupMessages(library(data.table))

out_dir <- "output"
mr    <- readRDS(file.path(out_dir, "model_results.rds"))
wthr  <- readRDS(file.path(out_dir, "weather_results.rds"))

STATES <- c("Current", "Late", "Severe", "Disconnected")

## ---- risk-tier -> base monthly slip probability (Current -> Late) --------
## Anchored to the same three tiers used in 04_consequences.R / the
## showcase (Low / Elevated / High), which in turn come from the fitted
## logistic model's own operating thresholds.
tier_base_slip <- c(Low = 0.03, Elevated = 0.12, High = 0.28)

## ---- transition-probability functions of "stress index" = bill/income ----
## Stated functional form, not fit to data (see header). Monotonic and
## clipped to [0,1] by construction; coefficients chosen so a stress
## index around 0.10 (a comfortable bill/income ratio) gives fairly
## forgiving cure/progress odds, and an index above ~0.25 (a bill that's
## a real bite out of monthly income) gives sharply worse ones.
cure_from_late    <- function(s) pmax(0.05, pmin(0.85, 0.75 - 1.6 * s))
progress_from_late <- function(s) pmax(0.03, pmin(0.90, 0.08 + 1.6 * s))
cure_from_severe   <- function(s) pmax(0.02, pmin(0.60, 0.42 - 1.3 * s))
progress_from_severe <- function(s) pmax(0.02, pmin(0.70, 0.06 + 1.1 * s))

build_transition_matrix <- function(tier, stress_index) {
  a <- tier_base_slip[[tier]]                      # Current -> Late
  cL <- cure_from_late(stress_index)                # Late -> Current
  pL <- progress_from_late(stress_index)            # Late -> Severe
  sL <- 1 - cL - pL                                 # Late -> Late
  cS <- cure_from_severe(stress_index)              # Severe -> Current
  pS <- progress_from_severe(stress_index)          # Severe -> Disconnected
  sS <- 1 - cS - pS                                 # Severe -> Severe
  stopifnot(sL >= 0, sS >= 0)

  P <- matrix(0, nrow = 4, ncol = 4, dimnames = list(STATES, STATES))
  P["Current", "Current"] <- 1 - a
  P["Current", "Late"]    <- a
  P["Late", "Current"]    <- cL
  P["Late", "Late"]       <- sL
  P["Late", "Severe"]     <- pL
  P["Severe", "Current"]  <- cS
  P["Severe", "Severe"]   <- sS
  P["Severe", "Disconnected"] <- pS
  P["Disconnected", "Disconnected"] <- 1
  P
}

## ---- fundamental-matrix analysis (standard absorbing Markov chain math) --
analyze_chain <- function(P) {
  transient <- STATES[STATES != "Disconnected"]
  Q <- P[transient, transient]
  R <- P[transient, "Disconnected", drop = FALSE]
  N <- solve(diag(nrow(Q)) - Q)              # fundamental matrix, N = (I - Q)^-1
  expected_steps <- N %*% matrix(1, nrow = nrow(Q))  # expected months to absorption, per starting state
  rownames(expected_steps) <- transient

  ## 12-month-ahead state distribution starting fully in "Current"
  x0 <- setNames(c(1, 0, 0, 0), STATES)
  horizon <- 24
  traj <- matrix(0, nrow = horizon + 1, ncol = 4, dimnames = list(0:horizon, STATES))
  traj[1, ] <- x0
  for (m in seq_len(horizon)) traj[m + 1, ] <- traj[m, ] %*% P

  list(N = N, expected_months_to_disconnect = expected_steps, trajectory = traj,
       p_disconnected_12mo = traj["12", "Disconnected"],
       p_disconnected_6mo  = traj["6", "Disconnected"])
}

## ============================================================
## Worked scenarios: risk tier x income context, using the real
## weather-driven August bill (with and without the heatwave shock)
## ============================================================
income_scenarios <- list(
  "Moderate income ($3,000/mo)" = 3000,
  "Near HEAP-eligible ($1,800/mo)" = 1800
)
bill_scenarios <- list(
  "Typical August bill" = wthr$baseline_bill,
  "August + heatwave"   = wthr$shock_bill
)

scenario_grid <- CJ(tier = names(tier_base_slip),
                     income_label = names(income_scenarios),
                     bill_label = names(bill_scenarios), sorted = FALSE)

results <- lapply(seq_len(nrow(scenario_grid)), function(i) {
  row <- scenario_grid[i]
  income <- income_scenarios[[row$income_label]]
  bill   <- bill_scenarios[[row$bill_label]]
  stress <- bill / income
  P <- build_transition_matrix(row$tier, stress)
  a <- analyze_chain(P)
  data.table(
    tier = row$tier, income_label = row$income_label, bill_label = row$bill_label,
    bill = round(bill, 2), income = income, stress_index = round(stress, 4),
    expected_months_to_disconnect = round(a$expected_months_to_disconnect["Current", 1], 1),
    p_disconnected_6mo  = round(a$p_disconnected_6mo, 4),
    p_disconnected_12mo = round(a$p_disconnected_12mo, 4)
  )
})
results <- rbindlist(results)
setorder(results, tier, income_label, bill_label)

cat("=== Markov chain scenario results ===\n")
print(results)

## ---- save the full trajectory for one illustrative scenario for plotting --
illustrative <- build_transition_matrix("Elevated", wthr$baseline_bill / 1800)
illustrative_analysis <- analyze_chain(illustrative)

markov_results <- list(
  states = STATES,
  build_transition_matrix = build_transition_matrix,
  analyze_chain = analyze_chain,
  scenario_results = results,
  illustrative_matrix = illustrative,
  illustrative_trajectory = illustrative_analysis$trajectory,
  tier_base_slip = tier_base_slip
)
saveRDS(markov_results, file.path(out_dir, "markov_results.rds"))
fwrite(results, file.path(out_dir, "markov_scenarios.csv"))

cat("\nExample transition matrix (Elevated risk, near-HEAP-eligible income, typical bill):\n")
print(round(illustrative, 3))

cat("\nSaved markov_results.rds and markov_scenarios.csv\n")
cat("07_markov_chain.R complete.\n")
