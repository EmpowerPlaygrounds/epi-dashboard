# 03-join.R — Join all datasets by school name

library(tidyverse)
library(here)

# ------------------------------------------------------------------
# Build the master schools table
# ------------------------------------------------------------------
# Start with the canonical school list and join visit/survey summaries

# Visit counts per school
visit_summary <- clean_quick |>
  count(school_name, name = "n_visits")

# Student survey summaries per school
survey_summary <- clean_student |>
  group_by(school_name) |>
  summarise(
    n_responses    = n(),
    pct_lantern    = mean(lantern_group == "Yes", na.rm = TRUE),
    pct_library    = mean(has_library == "Yes", na.rm = TRUE),
    pct_menstrual  = mean(menstrual_kit == "Yes", na.rm = TRUE),
    pct_computers  = mean(has_computers == "Yes", na.rm = TRUE),
    .groups = "drop"
  )

# Issues count per school
issues_summary <- clean_quick |>
  filter(!is.na(urgent_issues) & urgent_issues != "") |>
  count(school_name, name = "n_issues")

# Join everything onto the schools table
schools_joined <- clean_schools |>
  left_join(visit_summary, by = "school_name") |>
  left_join(survey_summary, by = "school_name") |>
  left_join(issues_summary, by = "school_name") |>
  mutate(across(starts_with("n_"), \(x) replace_na(x, 0)))

cat("  Joined datasets by school name\n")
