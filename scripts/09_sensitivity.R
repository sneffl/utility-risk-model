## ============================================================
## 09_sensitivity.R
## Sensitivity analysis on the Markov chain's stated assumptions
##
## The transition-probability functions in 07_markov_chain.R are stated
## modeling assumptions (no public dataset labels individual month-by-
## month delinquency transitions, so there is nothing to fit them to).
## The right response to that limitation is to measure how much the
## model's conclusions depend on the exact numbers chosen. Two checks:
##
##   1. One-at-a-time tornado analysis: perturb each assumed parameter
##      +/-20% around its stated value and record the effect on the
##      12-month disconnection probability for a reference scenario.
##   2. Joint Monte Carlo: draw all assumed parameters simultaneously
##      from +/-20% uniform ranges (2,000 draws), and check (a) the
##      spread of the 12-month disconnection probability and (b) whether
##      the qualitative conclusion -- High tier > Elevated > Low --
##      survives in every single draw.
##
## Reference scenario: Elevated risk tier, near-HEAP-eligible income
## ($1,800/mo), typical August bill -- the same illustrative scenario
## used in 07 and in the report.
## ============================================================

suppressPackageStartupMessages({ library(data.table); library(ggplot2) })
set.seed(42)

out_dir  <- "output"
plot_dir <- file.path(out_dir, "plots")
wthr <- readRDS(file.path(out_dir, "weather_results.rds"))

STATES <- c("Current", "Late", "Severe", "Disconnected")

## Assumed parameters, at their stated values (matching 07_markov_chain.R)
base_params <- c(
  slip_low       = 0.03,  slip_elevated = 0.12,  slip_high = 0.28,
  cure_late_int  = 0.75,  cure_late_slope  = 1.6,
  prog_late_int  = 0.08,  prog_late_slope  = 1.6,
  cure_sev_int   = 0.42,  cure_sev_slope   = 1.3,
  prog_sev_int   = 0.06,  prog_sev_slope   = 1.1
)

## Parameterized version of 07's transition machinery. Returns NULL when
## a perturbed draw produces an invalid probability row (cure + progress
## > 1), so joint draws can be rejected and counted instead of crashing.
build_P <- function(pm, tier, stress) {
  slip <- switch(tier, Low = pm[["slip_low"]], Elevated = pm[["slip_elevated"]], High = pm[["slip_high"]])
  cL <- pmax(0.05, pmin(0.85, pm[["cure_late_int"]] - pm[["cure_late_slope"]] * stress))
  pL <- pmax(0.03, pmin(0.90, pm[["prog_late_int"]] + pm[["prog_late_slope"]] * stress))
  cS <- pmax(0.02, pmin(0.60, pm[["cure_sev_int"]]  - pm[["cure_sev_slope"]]  * stress))
  pS <- pmax(0.02, pmin(0.70, pm[["prog_sev_int"]]  + pm[["prog_sev_slope"]]  * stress))
  if (cL + pL > 1 || cS + pS > 1) return(NULL)
  P <- matrix(0, 4, 4, dimnames = list(STATES, STATES))
  P["Current", "Current"] <- 1 - slip; P["Current", "Late"] <- slip
  P["Late", "Current"] <- cL; P["Late", "Late"] <- 1 - cL - pL; P["Late", "Severe"] <- pL
  P["Severe", "Current"] <- cS; P["Severe", "Severe"] <- 1 - cS - pS; P["Severe", "Disconnected"] <- pS
  P["Disconnected", "Disconnected"] <- 1
  P
}

p_disc_12mo <- function(P) {
  x <- c(1, 0, 0, 0)
  for (m in 1:12) x <- x %*% P
  x[4]
}

ref_stress <- wthr$baseline_bill / 1800
ref_tier   <- "Elevated"
p12_base   <- p_disc_12mo(build_P(base_params, ref_tier, ref_stress))
cat(sprintf("Reference scenario 12-month disconnection probability: %.4f\n\n", p12_base))

## ---- 1. One-at-a-time tornado (+/-20% per parameter) ---------------------
## slip_low / slip_high do not affect the Elevated reference scenario, so
## the tornado covers the 8 parameters that do.
tornado_params <- setdiff(names(base_params), c("slip_low", "slip_high"))
tornado <- rbindlist(lapply(tornado_params, function(nm) {
  lo <- base_params; lo[[nm]] <- lo[[nm]] * 0.8
  hi <- base_params; hi[[nm]] <- hi[[nm]] * 1.2
  P_lo <- build_P(lo, ref_tier, ref_stress); P_hi <- build_P(hi, ref_tier, ref_stress)
  data.table(param = nm,
             p12_low  = if (is.null(P_lo)) NA_real_ else p_disc_12mo(P_lo),
             p12_high = if (is.null(P_hi)) NA_real_ else p_disc_12mo(P_hi))
}))
tornado[, swing := abs(p12_high - p12_low)]
setorder(tornado, swing)
cat("=== Tornado: effect of +/-20% in each assumed parameter on P(disconnected, 12mo) ===\n")
print(tornado[order(-swing)])

## ---- 2. Joint Monte Carlo (+/-20% uniform on everything, 2000 draws) -----
n_draws <- 2000
draws <- vapply(seq_len(n_draws), function(i) {
  pm <- base_params * runif(length(base_params), 0.8, 1.2)
  names(pm) <- names(base_params)
  Ps <- lapply(c("Low", "Elevated", "High"), function(t) build_P(pm, t, ref_stress))
  if (any(vapply(Ps, is.null, logical(1)))) return(c(NA_real_, NA_real_, NA_real_))
  vapply(Ps, p_disc_12mo, numeric(1))
}, numeric(3))
draws <- t(draws)
colnames(draws) <- c("Low", "Elevated", "High")
valid <- complete.cases(draws)
cat(sprintf("\nValid joint draws: %d of %d (%d rejected for producing an invalid probability row)\n",
            sum(valid), n_draws, n_draws - sum(valid)))
dv <- as.data.table(draws[valid, ])

q <- quantile(dv$Elevated, c(0.025, 0.5, 0.975))
cat(sprintf("Elevated-tier P(disconnected, 12mo): median %.3f, 95%% interval [%.3f, %.3f] (stated-value run: %.3f)\n",
            q[2], q[1], q[3], p12_base))
ordering_holds <- mean(dv$High > dv$Elevated & dv$Elevated > dv$Low)
cat(sprintf("Tier ordering High > Elevated > Low holds in %.1f%% of joint draws\n", 100 * ordering_holds))

## ---- Plots ----------------------------------------------------------------
BLUE <- "#2a78d6"; ORANGE <- "#eb6834"; MUTED <- "#898781"
GRID <- "#e1e0d9"; INK <- "#0b0b0b"; INK2 <- "#52514e"
base_theme <- theme_minimal(base_size = 13) +
  theme(panel.grid.minor = element_blank(),
        panel.grid.major = element_line(color = GRID, linewidth = 0.3),
        axis.line = element_line(color = "#c3c2b7", linewidth = 0.3),
        text = element_text(color = INK), axis.text = element_text(color = INK2),
        plot.title = element_text(face = "bold", size = 15),
        plot.subtitle = element_text(color = INK2, size = 11),
        legend.position = "top", legend.title = element_blank())

pretty_names <- c(
  slip_elevated  = "Base slip prob. (Elevated tier)",
  cure_late_int  = "Late cure: intercept",
  cure_late_slope  = "Late cure: stress slope",
  prog_late_int  = "Late progression: intercept",
  prog_late_slope  = "Late progression: stress slope",
  cure_sev_int   = "Severe cure: intercept",
  cure_sev_slope   = "Severe cure: stress slope",
  prog_sev_int   = "Severe progression: intercept",
  prog_sev_slope   = "Severe progression: stress slope"
)
tornado[, label := factor(pretty_names[param], levels = pretty_names[param])]

p_tornado <- ggplot(tornado) +
  geom_segment(aes(x = p12_low, xend = p12_high, y = label, yend = label),
               color = BLUE, linewidth = 5, alpha = 0.85, lineend = "round") +
  geom_vline(xintercept = p12_base, linetype = "dashed", color = INK2) +
  annotate("text", x = p12_base, y = 0.6, label = "stated values",
           color = INK2, size = 3.4, hjust = -0.1) +
  labs(title = "How much does each assumption matter?",
       subtitle = "P(disconnected, 12mo) when each parameter moves +/-20%. Elevated-tier reference.",
       x = "P(disconnected within 12 months)", y = NULL) +
  scale_x_continuous(expand = expansion(mult = 0.08)) +
  base_theme
ggsave(file.path(plot_dir, "sensitivity_tornado.png"), p_tornado,
       width = 9.5, height = 5.2, dpi = 150, bg = "white")

p_mc <- ggplot(dv, aes(Elevated)) +
  geom_histogram(bins = 45, fill = BLUE, alpha = 0.75, color = "white", linewidth = 0.2) +
  geom_vline(xintercept = p12_base, linetype = "dashed", color = ORANGE, linewidth = 0.8) +
  annotate("text", x = p12_base, y = Inf, label = " stated values", color = ORANGE,
           vjust = 2, hjust = 0, size = 3.6) +
  labs(title = "Joint Monte Carlo: all assumptions perturbed at once",
       subtitle = sprintf("%s valid draws, every parameter drawn +/-20%%. 95%% of outcomes fall in [%.3f, %.3f].",
                          format(sum(valid), big.mark = ","), q[1], q[3]),
       x = "P(disconnected within 12 months), Elevated tier", y = "Draws") +
  base_theme
ggsave(file.path(plot_dir, "sensitivity_montecarlo.png"), p_mc,
       width = 9.5, height = 5.2, dpi = 150, bg = "white")

sens_results <- list(
  p12_base = p12_base, tornado = tornado,
  mc_quantiles = q, ordering_holds = ordering_holds,
  n_valid = sum(valid), n_draws = n_draws
)
saveRDS(sens_results, file.path(out_dir, "sensitivity_results.rds"))
fwrite(tornado[, .(param, p12_low, p12_high, swing)], file.path(out_dir, "sensitivity_tornado.csv"))

cat("\nSaved sensitivity_results.rds, sensitivity_tornado.csv, and two plots.\n")
cat("09_sensitivity.R complete.\n")
