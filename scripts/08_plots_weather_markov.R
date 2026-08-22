## ============================================================
## 08_plots_weather_markov.R -- figures for the weather + Markov modules
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

out_dir  <- "output"
plot_dir <- file.path(out_dir, "plots")

BLUE <- "#2a78d6"; ORANGE <- "#eb6834"; RED <- "#e34948"; YELLOW <- "#eda100"
GREEN <- "#1baf7a"; MUTED <- "#898781"; GRID <- "#e1e0d9"; INK <- "#0b0b0b"; INK2 <- "#52514e"

base_theme <- theme_minimal(base_size = 13) +
  theme(
    panel.grid.minor = element_blank(),
    panel.grid.major = element_line(color = GRID, linewidth = 0.3),
    axis.line = element_line(color = "#c3c2b7", linewidth = 0.3),
    text = element_text(color = INK),
    axis.text = element_text(color = INK2),
    plot.title = element_text(face = "bold", size = 15),
    plot.subtitle = element_text(color = INK2, size = 11),
    legend.position = "top",
    legend.title = element_blank()
  )

wthr   <- readRDS(file.path(out_dir, "weather_results.rds"))
markov <- readRDS(file.path(out_dir, "markov_results.rds"))

## ---- 1. Monthly weather-driven bill forecast, with the heatwave shock ----
m <- copy(wthr$monthly)
m[, month_lbl := factor(month, levels = month)]
shock_row <- data.table(month_lbl = wthr$hottest_month, predicted_bill = wthr$shock_bill)

p_bill <- ggplot(m, aes(month_lbl, predicted_bill, group = 1)) +
  geom_area(fill = BLUE, alpha = 0.12) +
  geom_line(color = BLUE, linewidth = 1.1) +
  geom_point(color = BLUE, size = 2.6) +
  geom_point(data = shock_row, aes(month_lbl, predicted_bill), color = RED, size = 4, shape = 18) +
  annotate("text", x = shock_row$month_lbl, y = shock_row$predicted_bill + 18,
           label = "+ 6-day heatwave", color = RED, size = 3.6, fontface = "bold") +
  scale_y_continuous(labels = scales::dollar) +
  scale_x_discrete(labels = function(x) format(as.Date(paste0(x, "-01")), "%b")) +
  labs(title = "A weather-driven bill forecast, from real 2015 NYC temperatures",
       subtitle = "Degree-day model, calibrated to NEADA's published Mid-Atlantic average",
       x = NULL, y = "Predicted monthly bill") +
  base_theme

ggsave(file.path(plot_dir, "weather_bill_forecast.png"), p_bill, width = 9.2, height = 6.0, dpi = 200, bg = "white")

## ---- 2. Markov state-occupancy trajectory (stacked area) -----------------
traj <- as.data.table(markov$illustrative_trajectory, keep.rownames = "month")
traj[, month := as.integer(month)]
traj_long <- melt(traj, id.vars = "month", variable.name = "state", value.name = "prob")
traj_long[, state := factor(state, levels = c("Disconnected", "Severe", "Late", "Current"))]

state_colors <- c(Current = GREEN, Late = YELLOW, Severe = ORANGE, Disconnected = RED)

p_traj <- ggplot(traj_long, aes(month, prob, fill = state)) +
  geom_area(position = "stack", alpha = 0.9, color = "white", linewidth = 0.15) +
  scale_fill_manual(values = state_colors, breaks = c("Current", "Late", "Severe", "Disconnected")) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Where an elevated-risk, near-HEAP-eligible account ends up over 24 months",
       subtitle = "State occupancy over time, starting in \"Current\" (illustrative transitions, see report)",
       x = "Months", y = "Probability of being in each state") +
  base_theme

ggsave(file.path(plot_dir, "markov_trajectory.png"), p_traj, width = 9.2, height = 6.0, dpi = 200, bg = "white")

## ---- 3. Scenario comparison: 12-month disconnection probability ---------
sc <- copy(markov$scenario_results)
sc[, tier := factor(tier, levels = c("Low", "Elevated", "High"))]
sc[, scenario := paste(income_label, bill_label, sep = "\n")]

p_scenarios <- ggplot(sc, aes(tier, p_disconnected_12mo, fill = bill_label)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  facet_wrap(~income_label) +
  scale_fill_manual(values = c("Typical August bill" = BLUE, "August + heatwave" = RED)) +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "The same heatwave, more disconnection risk at lower income",
       subtitle = "Modeled probability of reaching \"Disconnected\" within 12 months, by ML risk tier and income context",
       x = "ML-predicted risk tier", y = "P(disconnected within 12 months)") +
  base_theme + theme(strip.text = element_text(face = "bold"))

ggsave(file.path(plot_dir, "markov_scenarios.png"), p_scenarios, width = 9.2, height = 6.0, dpi = 200, bg = "white")

cat("Saved 3 weather/Markov plots to", plot_dir, "\n")
cat("08_plots_weather_markov.R complete.\n")
