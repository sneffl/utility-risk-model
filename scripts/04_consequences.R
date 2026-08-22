## ============================================================
## 04_consequences.R
## Utility Non-Payment Risk & Consequence Model
##
## The classifiers in 03_modeling.R answer a statistical question:
## "how likely is this usage pattern to belong to a flagged account?"
## That is a DIFFERENT kind of question from "what actually happens,
## in calendar days and dollars, after an electric bill goes unpaid?"
## The second question isn't something a model should estimate from
## consumption data at all -- it's a matter of published utility
## regulation. So this script is deliberately NOT a statistical model.
## It is a small, transparent, fully-cited rules engine built from
## New York State's Home Energy Fair Practices Act (HEFPA) and
## consumer-finance sources, that turns a single missed bill into a
## day-by-day consequence timeline. Keeping this separate from the
## ML model is itself a modeling decision worth stating plainly: never
## let a statistical risk score quietly stand in for a policy fact.
##
## PRIMARY SOURCES (see report/CITATIONS.md for full list):
##  [1] NY Dept. of Public Service, "Your Rights as a Residential Gas,
##      Electric or Steam Customer Under HEFPA"
##      https://dps.ny.gov/your-rights-residential-gas-electric-or-steam-customer-under-hefpa
##  [2] Consumer Financial Protection Bureau, "Does my history of paying
##      utility bills ... go in my credit report?"
##      https://www.consumerfinance.gov/ask-cfpb/does-my-history-of-paying-utility-bills-like-telephone-cable-electricity-or-water-go-in-my-credit-report-en-1817/
##  [3] UtilityExplained.com, "Utility Reconnection Fee Explained" (market
##      range, not a regulatory figure -- utilities set this by tariff)
##  [4] NY OTDA HEAP program guidelines (income tiers / benefit caps are
##      republished yearly; figures below are illustrative -- verify at
##      mybenefits.ny.gov or otda.ny.gov before relying on them)
## ============================================================

suppressPackageStartupMessages(library(data.table))

out_dir <- "output"

## ---- HEFPA-derived cascade, as data, not hard-coded prose ----------------
## day_offset = calendar days after the ORIGINAL due date
cascade <- data.table(
  day_offset = c(0, 20, 35, 35, NA, 35, NA),
  event = c(
    "Bill due; balance unpaid",
    "Utility may issue a Final Termination Notice (HEFPA allows this starting 20 days after the due date) [1]",
    "Earliest lawful disconnection date -- HEFPA requires >=15 days' notice after the Final Termination Notice [1]",
    "A 1.5%/month late payment charge has been accruing on the unpaid balance since the due date [1]",
    "Nov 1 - Apr 15 only: cold-weather protections apply -- utility must attempt direct contact >=3 days before shutoff, and cannot disconnect for 15 business days after a required social-services referral, regardless of the day-35 date above [1]",
    "If disconnected: service is restored once the account is resolved; a reconnection fee applies, set by the utility's own tariff (commonly $20-$150+ for electric, more after-hours; NY does not publish one universal statewide amount) [3]",
    "If the unpaid balance is referred to a third-party debt collector: THIS is the point (not the missed payment itself) at which it can appear on a credit report. New York utilities generally do not report routine on-time/late payment history to the three major credit bureaus themselves [2]"
  ),
  category = c("billing", "notice", "disconnection", "fee", "protection", "fee", "credit")
)

fwrite(cascade, file.path(out_dir, "consequence_cascade.csv"))

## ---- helper: project the compounding 1.5%/month HEFPA late fee -----------
## HEFPA states the utility "can add ... a late payment charge which is
## 1.5% per month on the unpaid balance" [1]. We model this literally:
## each month, 1.5% of the CURRENT outstanding balance (original bill +
## fees accrued so far) is added -- i.e. the fee compounds monthly on
## whatever is still owed, which is the plain reading of "on the unpaid
## balance," not just on the original bill.
project_late_fees <- function(bill_amount, n_months = 6) {
  balance <- bill_amount
  out <- data.table(month = 0, balance = balance, fee_this_month = 0)
  for (m in seq_len(n_months)) {
    fee <- 0.015 * balance
    balance <- balance + fee
    out <- rbind(out, data.table(month = m, balance = balance, fee_this_month = fee))
  }
  out
}

## ---- helper: turn a model risk score into a plain-language risk tier -----
## Thresholds line up with the Youden-optimal operating point found in
## 03_modeling.R for the logistic model, plus one tier above it for
## "high confidence" flags -- NOT a HEFPA rule, just a triage label.
risk_tier <- function(prob, thresh_moderate) {
  fifelse(prob >= min(thresh_moderate * 1.6, 0.95), "High",
    fifelse(prob >= thresh_moderate, "Elevated", "Low"))
}

## ---- helper: rough HEAP/LIHEAP screen (illustrative; verify current year) --
## Household-size income tiers approximate published 2025-2026 NY HEAP
## guidance [4]. This is NOT a benefits determination -- it's a
## screening prompt to point an at-risk household toward the real
## application at mybenefits.ny.gov.
heap_screen <- function(household_size, monthly_gross_income) {
  tier1_caps <- c(1695, 2291, 2887, 3482)
  tier2_caps <- c(3473, 4542, 5611, 6680)
  hs <- min(max(household_size, 1), 4)
  if (monthly_gross_income <= tier1_caps[hs]) {
    "Likely income-eligible for HEAP (Tier 1) -- apply at mybenefits.ny.gov"
  } else if (monthly_gross_income <= tier2_caps[hs]) {
    "Possibly income-eligible for HEAP (Tier 2) -- apply at mybenefits.ny.gov"
  } else {
    "Likely above published HEAP income guidelines for this household size -- confirm current-year limits, some categorical eligibility rules (SNAP/PA/SSI) can still qualify a household"
  }
}

## ---- assemble one worked example per risk tier, for the report -----------
model_results <- readRDS(file.path(out_dir, "model_results.rds"))
example_bill <- 180   # illustrative average NYC residential electric bill

examples <- data.table(
  scenario   = c("Low risk", "Elevated risk", "High risk"),
  risk_prob  = c(0.05, model_results$thresh_logit, min(model_results$thresh_logit * 1.7, 0.9)),
  tier       = c("Low", "Elevated", "High")
)
examples[, action := fcase(
  tier == "Low",      "No action beyond a normal reminder.",
  tier == "Elevated", "Proactive outreach recommended: payment plan (DPA) offer + HEAP screening before day 20.",
  tier == "High",     "Priority outreach before Final Termination Notice window; DPA + HEAP screening + cold-weather protection check."
)]

fwrite(examples, file.path(out_dir, "risk_tier_examples.csv"))
saveRDS(list(cascade = cascade, project_late_fees = project_late_fees,
             risk_tier = risk_tier, heap_screen = heap_screen,
             examples = examples, example_bill = example_bill),
        file.path(out_dir, "consequences.rds"))

## ---- console demo --------------------------------------------------------
cat("=== HEFPA-derived consequence cascade (New York) ===\n")
print(cascade[, .(day_offset, category, event)])

cat("\n=== Late-fee projection on a $", example_bill, " unpaid bill (HEFPA 1.5%/month) ===\n", sep = "")
print(project_late_fees(example_bill))

cat("\n=== Worked risk-tier examples ===\n")
print(examples)

cat("\n=== HEAP screen examples ===\n")
cat("Household of 3, $2,500/mo income:", heap_screen(3, 2500), "\n")
cat("Household of 1, $2,000/mo income:", heap_screen(1, 2000), "\n")

cat("\n04_consequences.R complete.\n")
