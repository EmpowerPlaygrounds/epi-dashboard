# 04-export.R — Export CSVs + per-school JSONs

library(tidyverse)
library(jsonlite)
library(here)
library(digest)
library(googlesheets4)

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
  select(school_name, urgent_issues, visit_reason, activities, observations, visit_date, visitor) |>
  mutate(
    issue_id = map_chr(
      paste(school_name, visit_date, urgent_issues),
      ~ substr(digest(.x, algo = "md5"), 1, 12)
    )
  )

# ------------------------------------------------------------------
# Read resolved issues from Google Sheet (if configured)
# ------------------------------------------------------------------
id_resolved <- Sys.getenv("SHEET_RESOLVED_ISSUES")

if (nzchar(id_resolved)) {
  sa_key <- Sys.getenv("GOOGLE_SERVICE_ACCOUNT_KEY")
  if (nzchar(sa_key)) {
    tmp <- tempfile(fileext = ".json")
    writeLines(sa_key, tmp)
    gs4_auth(path = tmp)
  } else {
    gs4_deauth()
  }

  resolved_raw <- tryCatch(
    read_sheet(id_resolved, col_types = "c"),
    error = function(e) {
      cat("  Note: Could not read resolved sheet:", e$message, "\n")
      tibble(issue_id = character())
    }
  )

  # Ensure issue_id is character (Google Sheets may guess numeric)
  resolved_raw <- resolved_raw |> mutate(issue_id = as.character(issue_id))
  resolved_ids <- resolved_raw$issue_id

  issues_open <- issues |> filter(!issue_id %in% resolved_ids)
  issues_resolved <- issues |>
    filter(issue_id %in% resolved_ids) |>
    left_join(
      resolved_raw |> select(issue_id, resolved_date, resolved_by, resolution_notes),
      by = "issue_id"
    )
} else {
  cat("  Note: SHEET_RESOLVED_ISSUES not set, treating all issues as open\n")
  issues_open <- issues
  issues_resolved <- issues |>
    slice(0) |>
    mutate(resolved_date = character(), resolved_by = character(), resolution_notes = character())
}

write_csv(issues, here("data", "clean", "issues.csv"))
write_csv(issues_open, here("data", "clean", "issues_open.csv"))
write_csv(issues_resolved, here("data", "clean", "issues_resolved.csv"))

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
