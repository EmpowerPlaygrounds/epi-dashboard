# 04-export.R — Export CSVs + per-school JSONs

library(tidyverse)
library(jsonlite)
library(here)

# ------------------------------------------------------------------
# Create output directories
# ------------------------------------------------------------------
dir.create(here("data", "clean", "schools"), showWarnings = FALSE, recursive = TRUE)

# ------------------------------------------------------------------
# Export flat CSVs
# ------------------------------------------------------------------
write_csv(schools_joined, here("data", "clean", "schools.csv"))
write_csv(clean_quick,    here("data", "clean", "visits.csv"))
write_csv(clean_student,  here("data", "clean", "surveys.csv"))
write_csv(clean_newproj,  here("data", "clean", "new_projects.csv"))
write_csv(clean_full,     here("data", "clean", "full_updates.csv"))

# Issues: extract urgent issues from visit data (exclude No/None/N/A)
issues <- clean_quick |>
  filter(!is.na(urgent_issues) & urgent_issues != "") |>
  filter(!str_to_lower(str_trim(urgent_issues)) %in% c("no", "none", "n/a", "na", "no.", "none.", "n/a.")) |>
  select(school_name, urgent_issues, visit_reason, activities, observations, visit_date, visitor)

write_csv(issues, here("data", "clean", "issues.csv"))

# ------------------------------------------------------------------
# Per-school JSONs for the detail view
# ------------------------------------------------------------------
school_names <- schools_joined$school_name

for (name in school_names) {
  school_data <- list(
    info        = schools_joined |> filter(school_name == name) |> as.list(),
    visits      = clean_quick |> filter(school_name == name),
    full_update = clean_full |> filter(school_name == name),
    surveys     = clean_student |> filter(school_name == name),
    issues      = issues |> filter(school_name == name)
  )

  filename <- name |>
    str_to_lower() |>
    str_replace_all("[^a-z0-9]+", "-") |>
    str_remove("-$")

  write_json(school_data, here("data", "clean", "schools", paste0(filename, ".json")),
             auto_unbox = TRUE, pretty = TRUE)
}

# School index JSON for the dropdown
school_index <- schools_joined |>
  transmute(
    name = school_name,
    slug = name |>
      str_to_lower() |>
      str_replace_all("[^a-z0-9]+", "-") |>
      str_remove("-$")
  ) |>
  arrange(name)

write_json(school_index, here("data", "clean", "school_index.json"), auto_unbox = TRUE, pretty = TRUE)

cat("  Exported CSVs and", length(school_names), "school JSONs\n")
