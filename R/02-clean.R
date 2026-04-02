# 02-clean.R — Clean, fix typos, standardize school names

library(tidyverse)
library(here)

# ------------------------------------------------------------------
# Load raw data
# ------------------------------------------------------------------
raw_schools <- read_csv(here("data", "raw", "schools_overview.csv"), show_col_types = FALSE)
raw_quick   <- read_csv(here("data", "raw", "quick_update.csv"), show_col_types = FALSE)
raw_full    <- read_csv(here("data", "raw", "full_update.csv"), show_col_types = FALSE)
raw_student <- read_csv(here("data", "raw", "student_survey.csv"), show_col_types = FALSE)
raw_newproj <- read_csv(here("data", "raw", "new_project.csv"), show_col_types = FALSE)

# ------------------------------------------------------------------
# Schools Overview
# ------------------------------------------------------------------
# Drop corrupted/empty columns
clean_schools <- raw_schools |>
  select(-any_of(c("...17", "3/14/2026"))) |>
  rename(school_name = `School Name`) |>
  mutate(school_name = str_trim(school_name))

# ------------------------------------------------------------------
# School name crosswalk — map typos/variants to canonical names
# Keys = variant found in data, Values = canonical name from Schools Overview
# ------------------------------------------------------------------
name_fixes <- c(
  # Typos in Quick Update
  "Mepotumtum"                = "Bepotumtum",
  "Nyienpeya"                 = "Nyapienya",

  # Student Survey variants (longer/shorter forms)
  "Afransua Dedewa"           = "Afransua Dedewa MA Primary",
  "Akeyermanteng"             = "Akyeremanteng",
  "Alorkpem"                  = "Alorkpem Island",
  "Ekorso-Akuoadu"            = "Ekorso Akwadum",
  "Kurasua #1 MA School"      = "Kurasua #1 MA",
  "Mosipanin D/A Basic School" = "Mosipanin",
  "Mpaem M/A Basic School"    = "Mpaem",
  "Nwawasua MA School"        = "Nwawasua MA",
  "Old KonKrompe"             = "Old Konkompe",
  "TunTum"                    = "Tun Tun",
  "Watroso"                   = "Watro (Watroso)",
  "Yonguase M/A Basic School" = "Yonguase",
  "Amaneampa"                 = "Anamenampa"
)

fix_school_name <- function(x) {
  out <- str_trim(x)
  idx <- match(out, names(name_fixes))
  ifelse(!is.na(idx), name_fixes[idx], out)
}

# ------------------------------------------------------------------
# Quick Update — skip Qualtrics label row, clean names
# ------------------------------------------------------------------
clean_quick <- raw_quick |>
  slice(-1) |>
  rename(
    school_name   = Q95,
    visitor       = Q1,
    visit_reason  = Q3,
    activities    = Q4,
    doing_well    = Q26,
    struggles     = Q27,
    urgent_issues = Q28,
    observations  = Q93
  ) |>
  mutate(
    school_name  = fix_school_name(school_name),
    visit_date   = parse_date_time(StartDate, orders = c("Ymd HMS", "mdY HMS", "Ymd HM")),
    visit_date   = as.Date(visit_date),
    # Replace "Other:" with the actual write-in text
    visit_reason = if_else(
      !is.na(Q3_6_TEXT) & Q3_6_TEXT != "",
      str_replace(visit_reason, "Other:?", Q3_6_TEXT),
      str_remove(visit_reason, ",?\\s*Other:?")
    ),
    activities = if_else(
      !is.na(Q4_6_TEXT) & Q4_6_TEXT != "",
      str_replace(activities, "Other:?", Q4_6_TEXT),
      str_remove(activities, ",?\\s*Other:?")
    )
  ) |>
  filter(!is.na(school_name) & school_name != "")

# ------------------------------------------------------------------
# Full Update — skip Qualtrics label row, clean school names
# ------------------------------------------------------------------
clean_full <- raw_full |>
  slice(-1) |>
  rename(school_name = Q2) |>
  mutate(
    school_name = fix_school_name(school_name),
    update_date = parse_date_time(StartDate, orders = c("mdY HMS", "Ymd HMS", "mdY HM")),
    update_date = as.Date(update_date),
    across(where(is.character), str_trim)
  )

# ------------------------------------------------------------------
# Student Survey — skip label row, resolve "Other" write-ins
# ------------------------------------------------------------------
clean_student <- raw_student |>
  slice(-1) |>
  rename(
    school_selected = Q2,
    school_other    = Q2_51_TEXT,
    lantern_group   = Q21,
    has_library     = Q10,
    menstrual_kit   = Q31,
    has_computers   = Q36
  ) |>
  mutate(
    # Use the write-in name if the selected choice was "Other" or missing
    school_name = case_when(
      !is.na(school_other) & school_other != "" ~ school_other,
      TRUE ~ school_selected
    ),
    school_name = fix_school_name(school_name)
  )

# ------------------------------------------------------------------
# New Project Survey — skip label row, clean school + project names
# ------------------------------------------------------------------
clean_newproj <- raw_newproj |>
  slice(-1) |>
  rename(
    visitor       = `1`,
    school_name   = `5`,
    project_type  = `3`,
    is_existing   = `4`,
    new_school    = `6`
  ) |>
  mutate(
    # Use new school name if not an existing EPI school
    school_name = case_when(
      is_existing == "No" & !is.na(new_school) & new_school != "" ~ new_school,
      TRUE ~ school_name
    ),
    school_name  = fix_school_name(school_name),
    project_date = parse_date_time(StartDate, orders = c("mdY HMS", "Ymd HMS", "mdY HM")),
    project_date = as.Date(project_date)
  ) |>
  filter(!is.na(school_name) & school_name != "")

cat("  Cleaned 5 datasets\n")
