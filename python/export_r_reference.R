## Pulls the shutoff model straight out of the live app's code and saves
## its answers for a grid of inputs, so the Python version can be checked
## against the exact functions the website runs.
##
## Run from the repo root:  Rscript python/export_r_reference.R

wanted <- c("TIER_BASE_SLIP", "cure_from_late", "progress_from_late",
            "cure_from_severe", "progress_from_severe", "STATES",
            "build_transition_matrix", "analyze_chain")

exprs <- parse("shiny_app/app.R")
for (e in exprs) {
  if (is.call(e) && identical(e[[1]], as.name("<-")) &&
      as.character(e[[2]])[1] %in% wanted) {
    eval(e, envir = globalenv())
  }
}
stopifnot(all(vapply(wanted, exists, logical(1))))

cases <- list()
for (tier in names(TIER_BASE_SLIP)) {
  for (s in c(0.02, 0.05, 0.08, 0.12, 0.20, 0.30, 0.50)) {
    P <- build_transition_matrix(tier, s)
    a <- analyze_chain(P, horizon = 24)
    cases[[length(cases) + 1]] <- list(
      tier = tier, stress = s,
      P = unname(split(P, row(P))),
      expected_months = a$expected_months,
      trajectory = unname(split(a$trajectory, row(a$trajectory)))
    )
  }
}

out <- "python/r_reference.json"
writeLines(jsonlite::toJSON(cases, auto_unbox = TRUE, digits = NA, pretty = FALSE), out)
cat("wrote", length(cases), "cases to", out, "\n")
