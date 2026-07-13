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

# Recommended projects: extract from full updates where recommendation was given
recommended_projects <- clean_full |>
  filter(!is.na(recommend_project) & recommend_project != "") |>
  filter(!str_detect(recommend_project, "^-?\\d")) |>  # remove junk numeric values
  filter(!is.na(school_name) & school_name != "") |>
  select(school_name, update_date, recommend_project, recommended_types,
         recommend_mgr_swap, Q1) |>
  rename(visitor = Q1) |>
  arrange(desc(update_date))

write_csv(recommended_projects, here("data", "clean", "recommended_projects.csv"))

# ------------------------------------------------------------------
# Items distributed & built — tidy long table for the Impact page.
# Derived from New Project entries. Two shapes:
#   * counted items   -> sum a quantity column
#   * occurrence items -> each matching install counts as 1
# Multi-school events (e.g. STEM Day) carry no item quantities and match
# no occurrence pattern, so they contribute nothing here.
# ------------------------------------------------------------------
np <- clean_newproj

# Safe numeric accessor (a column may be absent in some survey versions)
num_col <- function(df, code) {
  if (code %in% names(df)) suppressWarnings(as.numeric(df[[code]])) else rep(NA_real_, nrow(df))
}

items_counted <- tibble(
  school_name    = np$school_name,
  project_date   = np$project_date,
  lanterns       = rowSums(cbind(num_col(np, "12_1"), num_col(np, "26_1")), na.rm = TRUE),
  lantern_groups = num_col(np, "13"),
  computers      = num_col(np, "17_1"),
  solar_panels   = num_col(np, "28"),
  rooms          = num_col(np, "30"),
  science_kits   = num_col(np, "33_1"),
  menstrual_kits = num_col(np, "36"),
  library_books  = num_col(np, "43"),
  toilets        = num_col(np, "65_1")
) |>
  pivot_longer(-c(school_name, project_date), names_to = "item_key", values_to = "quantity") |>
  filter(!is.na(quantity) & quantity > 0) |>
  mutate(group = "distributed")

# Occurrence items: match the exact project_type option (multi-select, comma-
# joined). "Non-Generating MGR" is matched by its own string; the generating
# one uses "Electricity Generating MGR" so it never matches the non-gen option.
occ_defs <- tribble(
  ~item_key,           ~pattern,
  "mgr_generating",    "Electricity Generating MGR",
  "mgr_nongenerating", "Non-Generating MGR",
  "borehole",          "Borehole",
  "starlink",          "Starlink",
  "rachel",            "RACHEL",
  "library",           "Library",
  "grow",              "GROW Project",
  "construction",      "Building Construction"
)

items_occurrence <- map_dfr(seq_len(nrow(occ_defs)), function(i) {
  d <- occ_defs[i, ]
  np |>
    filter(str_detect(coalesce(project_type, ""), fixed(d$pattern))) |>
    transmute(school_name, project_date, item_key = d$item_key, quantity = 1, group = "built")
})

# Quick Update also records items handed out / replaced during routine visits
# (lanterns replaced, science kits given, menstrual kits distributed). Include
# these so Outputs reflects BOTH surveys (matches a manual cross-check).
qu_counted <- clean_quick |>
  transmute(
    school_name,
    project_date   = visit_date,
    lanterns       = suppressWarnings(as.numeric(Q9)),
    science_kits   = suppressWarnings(as.numeric(Q22)),
    menstrual_kits = suppressWarnings(as.numeric(Q20))
  ) |>
  pivot_longer(-c(school_name, project_date), names_to = "item_key", values_to = "quantity") |>
  filter(!is.na(quantity) & quantity > 0) |>
  mutate(group = "distributed")

item_labels <- tribble(
  ~item_key,           ~item_label,
  "lanterns",          "Lanterns Distributed",
  "lantern_groups",    "Lantern Groups Created",
  "computers",         "Computers Installed",
  "solar_panels",      "Solar Panels Installed",
  "rooms",             "Classrooms Created",
  "science_kits",      "Science Kits Distributed",
  "menstrual_kits",    "Menstrual Kits Distributed",
  "library_books",     "Library Books Distributed",
  "toilets",           "Biofil Toilets",
  "mgr_generating",    "Power-Generating MGRs Installed",
  "mgr_nongenerating", "Non-Generating MGRs Installed",
  "borehole",          "Boreholes Constructed",
  "starlink",          "Starlinks Installed",
  "rachel",            "RACHELs Installed",
  "library",           "Libraries Created",
  "grow",              "GROW Projects Initiated",
  "construction",      "Classroom Blocks Constructed"
)

items_distributed <- bind_rows(items_counted, qu_counted, items_occurrence) |>
  filter(!is.na(school_name) & school_name != "") |>
  left_join(item_labels, by = "item_key") |>
  mutate(project_date = as.character(project_date)) |>
  select(school_name, project_date, item_key, item_label, group, quantity) |>
  arrange(desc(project_date))

write_csv(items_distributed, here("data", "clean", "items_distributed.csv"))

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
    {
      sheet <- read_sheet(id_resolved, col_types = "ccccccc")
      # Force every column to character to avoid type mismatches
      sheet |> mutate(across(everything(), as.character))
    },
    error = function(e) {
      cat("  Note: Could not read resolved sheet:", e$message, "\n")
      tibble(
        issue_id = character(), school_name = character(),
        issue_text = character(), visit_date = character(),
        resolved_date = character(), resolved_by = character(),
        resolution_notes = character()
      )
    }
  )

  # Ensure issue_id column exists and is character
  if (!"issue_id" %in% names(resolved_raw)) {
    resolved_raw <- tibble(
      issue_id = character(), resolved_date = character(),
      resolved_by = character(), resolution_notes = character()
    )
  }

  resolved_ids <- as.character(resolved_raw$issue_id)

  issues_open <- issues |> filter(!issue_id %in% resolved_ids)

  resolved_for_join <- resolved_raw |>
    mutate(issue_id = as.character(issue_id)) |>
    select(any_of(c("issue_id", "resolved_date", "resolved_by", "resolution_notes")))

  issues_resolved <- issues |>
    filter(issue_id %in% resolved_ids) |>
    left_join(resolved_for_join, by = "issue_id")
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
