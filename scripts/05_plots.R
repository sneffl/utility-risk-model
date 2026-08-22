## ============================================================
## 05_plots.R -- diagnostic + narrative plots for the report
## Palette follows the project's dataviz standard: fixed categorical
## hue order (slot1 blue #2a78d6, slot2 orange #eb6834), diverging
## blue/red for signed coefficients, muted gray for reference lines.
## ============================================================

suppressPackageStartupMessages({
  library(data.table)
  library(ggplot2)
})

out_dir  <- "output"
plot_dir <- file.path(out_dir, "plots")

BLUE   <- "#2a78d6"; ORANGE <- "#eb6834"; RED <- "#e34948"
MUTED  <- "#898781"; GRID   <- "#e1e0d9"; INK <- "#0b0b0b"; INK2 <- "#52514e"

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

model_results <- readRDS(file.path(out_dir, "model_results.rds"))
features      <- readRDS(file.path(out_dir, "features.rds"))
cons          <- readRDS(file.path(out_dir, "consequences.rds"))

## ---- 1. ROC curves --------------------------------------------------------
roc_df <- rbind(
  data.table(fpr = model_results$roc_logit$fpr, tpr = model_results$roc_logit$tpr, model = "Logistic regression"),
  data.table(fpr = model_results$roc_tree$fpr,  tpr = model_results$roc_tree$tpr,  model = "Decision tree")
)
roc_df$model <- factor(roc_df$model, levels = c("Logistic regression", "Decision tree"))

p_roc <- ggplot(roc_df, aes(fpr, tpr, color = model)) +
  geom_abline(slope = 1, intercept = 0, color = MUTED, linewidth = 0.5, linetype = "dashed") +
  geom_line(linewidth = 1) +
  scale_color_manual(values = c("Logistic regression" = BLUE, "Decision tree" = ORANGE)) +
  coord_equal() +
  labs(title = "Both models beat chance by a wide margin",
       subtitle = sprintf("AUC: logistic %.3f, tree %.3f\n(a naive \"always non-risk\" guess gets %.1f%% accuracy and finds zero flagged accounts)",
                           model_results$auc_logit, model_results$auc_tree, 100 * model_results$baseline_acc),
       x = "False positive rate", y = "True positive rate") +
  base_theme

ggsave(file.path(plot_dir, "roc_curves.png"), p_roc, width = 7.5, height = 6.6, dpi = 200, bg = "white")

## ---- 2. Logistic regression coefficients (standardized) ------------------
co <- summary(model_results$logit_fit)$coefficients
co_df <- data.table(term = rownames(co), estimate = co[, "Estimate"])
co_df <- co_df[term != "(Intercept)"]
co_df[, term := factor(term, levels = term[order(estimate)])]
co_df[, sign := ifelse(estimate >= 0, "Higher risk", "Lower risk")]

p_coef <- ggplot(co_df, aes(estimate, term, fill = sign)) +
  geom_col(width = 0.65) +
  geom_vline(xintercept = 0, color = INK, linewidth = 0.4) +
  scale_fill_manual(values = c("Higher risk" = RED, "Lower risk" = BLUE)) +
  labs(title = "What moves the risk score",
       subtitle = "Standardized logistic regression coefficients -- one unit = one SD of that feature",
       x = "Effect on log-odds of being flagged", y = NULL) +
  base_theme + theme(legend.position = "top")

ggsave(file.path(plot_dir, "coefficients.png"), p_coef, width = 8, height = 5.5, dpi = 200, bg = "white")

## ---- 3. Confusion matrix heatmap (logistic, Youden threshold) ------------
cm <- model_results$cm_logit
cm_df <- data.table(
  actual = factor(c("Flagged", "Flagged", "Not flagged", "Not flagged"), levels = c("Not flagged", "Flagged")),
  predicted = factor(c("Flagged", "Not flagged", "Flagged", "Not flagged"), levels = c("Not flagged", "Flagged")),
  n = c(cm$tp, cm$fn, cm$fp, cm$tn)
)

p_cm <- ggplot(cm_df, aes(predicted, actual, fill = n)) +
  geom_tile(color = "white", linewidth = 2) +
  geom_text(aes(label = scales::comma(n)), color = INK, fontface = "bold", size = 5.5) +
  scale_fill_gradient(low = "#cde2fb", high = BLUE) +
  labs(title = "Confusion matrix -- logistic model, test set",
       subtitle = sprintf("Youden-optimal threshold: precision %.0f%%, recall %.0f%%",
                           100 * cm$precision, 100 * cm$recall),
       x = "Predicted", y = "Actual") +
  base_theme + theme(legend.position = "none", panel.grid = element_blank())

ggsave(file.path(plot_dir, "confusion_matrix.png"), p_cm, width = 6.5, height = 5.2, dpi = 200, bg = "white")

## ---- 4. Feature distributions by FLAG (small multiples) ------------------
feat_long <- melt(features[, .(FLAG, log_sd_kwh, yoy_decline_ratio, cv_kwh, pct_missing)],
                   id.vars = "FLAG")
feat_long[, FLAG := factor(FLAG, levels = c(0, 1), labels = c("Not flagged", "Flagged"))]
label_map <- c(log_sd_kwh = "log(1 + day-to-day SD of usage)",
               yoy_decline_ratio = "2014 -> 2016 usage trend (log-ratio)",
               cv_kwh = "Coefficient of variation",
               pct_missing = "Share of missing meter-reads")
feat_long[, variable := factor(label_map[as.character(variable)], levels = label_map)]

p_dist <- ggplot(feat_long, aes(value, fill = FLAG)) +
  geom_density(alpha = 0.6, linewidth = 0.2, color = "white") +
  scale_fill_manual(values = c("Not flagged" = BLUE, "Flagged" = ORANGE)) +
  facet_wrap(~variable, scales = "free", ncol = 2) +
  labs(title = "The features that separate flagged accounts from ordinary ones",
       subtitle = "Density of each feature, split by whether the account was ever flagged", x = NULL, y = NULL) +
  base_theme + theme(axis.text.y = element_blank(), strip.text = element_text(face = "bold"))

ggsave(file.path(plot_dir, "feature_distributions.png"), p_dist, width = 9, height = 7, dpi = 200, bg = "white")

## ---- 5. Late-fee compounding under HEFPA's 1.5%/month rule ---------------
fee_proj <- cons$project_late_fees(cons$example_bill, n_months = 6)

p_fee <- ggplot(fee_proj, aes(month, balance)) +
  geom_area(fill = BLUE, alpha = 0.15) +
  geom_line(color = BLUE, linewidth = 1.1) +
  geom_point(color = BLUE, size = 2.5) +
  labs(title = sprintf("A $%d unpaid bill, left alone for 6 months", cons$example_bill),
       subtitle = "HEFPA permits a 1.5%/month late charge on the unpaid balance -- this alone, before any disconnection or fees",
       x = "Months unpaid", y = "Balance owed ($)") +
  scale_y_continuous(labels = scales::dollar) +
  base_theme

ggsave(file.path(plot_dir, "late_fee_projection.png"), p_fee, width = 8.2, height = 5.8, dpi = 200, bg = "white")

cat("Saved 5 plots to", plot_dir, "\n")
cat("05_plots.R complete.\n")
