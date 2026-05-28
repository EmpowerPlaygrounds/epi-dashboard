# 02-clean.R — Clean, fix typos, standardize school names

library(tidyverse)
library(stringdist)
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
# Drop junk columns generically:
#   - unnamed columns (readr auto-generates "...N" names)
#   - columns whose name looks like a date (accidental spreadsheet entry)
clean_schools <- raw_schools |>
  select(
    -matches("^\\.\\.\\.\\d+$"),
    -matches("^\\d{1,2}/\\d{1,2}/\\d{2,4}$")
  ) |>
  rename(school_name = `School Name`) |>
  mutate(school_name = str_trim(school_name))

# Canonical school names (the source of truth)
canonical_names <- sort(unique(clean_schools$school_name))

# ------------------------------------------------------------------
# School name crosswalk — map known typos/variants to canonical names
# Keys = variant found in data, Values = canonical name from Schools Overview
# Add new entries here as you discover them.
# ------------------------------------------------------------------
name_fixes <- c(
  # --- Typos (1-2 character errors) ---
  "Mepotumtum"                 = "Bepotumtum",
  "Bepotuntum"                 = "Bepotumtum",
  "Nyienpeya"                  = "Nyapienya",
  "Akeyermanteng"              = "Akyeremanteng",
  "Akeyeremateng"              = "Akyeremanteng",
  "Ankwansrem"                 = "Akwanserem",
  "Azizakope"                  = "Azizakpem",
  "Mamkrom"                    = "Mamakrom",
  "mamakrom"                   = "Mamakrom",
  "Mentkwa"                    = "Mantukwa",
  "Mosipani"                   = "Mosipanin",
  "Obane"                      = "Obani",
  "Oblemanya"                  = "Obelemanya",
  "Obelemaya"                  = "Obelemanya",
  "Obosono"                    = "Obosonu",
  "Tseldom"                    = "Tsledom",
  "Todjer"                     = "Torjeh",
  "Ankwasu"                    = "Akwansu",
  "Amaneampa"                  = "Anamenampa",
  "Wuurudu Wurudu"             = "Wurudu Wurudu",
  "Fawotirikosie"              = "Fawotrikosie",
  "Fawotirkosie"               = "Fawotrikosie",

  # --- Alternate spellings (>2 chars but confirmed matches) ---
  "TunTum"                     = "Tun Tun",
  "TumTum"                     = "Tun Tun",
  "Tuntum"                     = "Tun Tun",
  "Old KonKrompe"              = "Old Konkompe",
  "Mongpong Shai"              = "Mampong Shai",
  "Mampong"                    = "Mampong Shai",
  "Fatwakosie"                 = "Fawotrikosie",
  "Watroso"                    = "Watro (Watroso)",
  "Kpala"                      = "Kpala Government",

  # --- Longer/shorter formal name variants ---
  "Adorkope"                         = "Ador Kope R/C Primary",
  "Ador Kope"                        = "Ador Kope R/C Primary",
  "Afransua Dedewa"                  = "Afransua Dedewa MA Primary",
  "Afransua Dedewa M/A Primary School" = "Afransua Dedewa MA Primary",
  "Akwanserem D/A Basic School"      = "Akwanserem",
  "Alorkpem"                         = "Alorkpem Island",
  "Ankwansu Anglican Basic School"   = "Akwansu",
  "Ataampuutum"                      = "Ataampuutum A/B",
  "Community School 3"               = "Community 3",
  "Community School 9"               = "Community 9",
  "Community school 9"               = "Community 9",
  "Domase D/A"                       = "Domase",
  "Domase D/A School"                = "Domase",
  "Ekorso-Akuoadu"                   = "Ekorso Akwadum",
  "Essam Golden Sunbeam Montessori School" = "Essam",
  "Galalia D/A Primary School"       = "Galalia",
  "Kpala Government School"          = "Kpala Government",
  "Kpala Private School (IOHCA)"     = "Kpala Private",
  "Kurasua #1 MA School"             = "Kurasua #1 MA",
  "Minya D/A Basic School"           = "Minya",
  "Mosipanin D/A Basic School"       = "Mosipanin",
  "Mpaem M/A Basic School"           = "Mpaem",
  "Nwawasua MA School"               = "Nwawasua MA",
  "Nwawasua M/A School"              = "Nwawasua MA",
  "Nyariga Girls School"             = "Nyariga Girls' School",
  "Obosono M/A"                      = "Obosonu",
  "Wenamda D A"                      = "Wenamda",
  "Wenamda D/A"                      = "Wenamda",
  "Wenamda D/A Primary School"       = "Wenamda",
  "Wangarakrom-Tarkuea"              = "Wangarakrom",
  "Yonguase M/A Basic School"        = "Yonguase",
  "Zippo Nyuinyui R/C"               = "Zippo Nyuinyui"
)

# Names to ignore during fuzzy matching (not real school names)
ignore_names <- c("Other", "Other:", "central", "Modem m a", "a")

# ------------------------------------------------------------------
# fix_school_name: 3-step name resolution
#   1. Apply known fixes from the crosswalk above
#   2. Fuzzy-match remaining unknowns against canonical names
#      - Auto-correct if string distance <= 2 (very close match)
#      - Warn if distance 3-4 (possible match, needs human review)
#   3. Leave anything else as-is (could be a genuinely new school)
# ------------------------------------------------------------------
fix_school_name <- function(x) {
  out <- str_trim(x)

  # Step 1: apply known crosswalk
  idx <- match(out, names(name_fixes))
  out <- ifelse(!is.na(idx), name_fixes[idx], out)

  # Step 2: fuzzy-match anything still not in the canonical list
  unmatched <- !is.na(out) & out != "" &
    !out %in% canonical_names &
    !out %in% ignore_names
  if (any(unmatched)) {
    for (i in which(unmatched)) {
      # Calculate string distances to all canonical names (case-insensitive)
      dists <- stringdist(tolower(out[i]), tolower(canonical_names), method = "osa")
      best_idx   <- which.min(dists)
      best_dist  <- dists[best_idx]
      best_match <- canonical_names[best_idx]

      if (best_dist <= 2) {
        # Close enough to auto-correct
        cat("    [auto-fix] '", out[i], "' -> '", best_match,
            "' (distance ", best_dist, ")\n", sep = "")
        out[i] <- best_match
      } else if (best_dist <= 4) {
        # Possible match — warn so a human can verify
        cat("    [WARNING] '", out[i], "' might be '", best_match,
            "' (distance ", best_dist, ") — please verify\n", sep = "")
      }
      # distance > 4: likely a new school or very different name, leave as-is
    }
  }

  out
}

# ------------------------------------------------------------------
# parse_sheet_date: handle BOTH text timestamps and Google Sheets serial
# numbers.
#   - Qualtrics' API writes dates as text, e.g. "2026-05-11 9:29:00".
#   - Manually entered/pasted cells become real date VALUES, which
#     googlesheets4 (reading with col_types = "c") returns as serial
#     numbers like "46153.395" (days since 1899-12-30). Those fail normal
#     parsing, so update_date becomes NA and the row silently drops out of
#     the dashboard. This coalesces both forms into a proper datetime.
# ------------------------------------------------------------------
parse_sheet_date <- function(x, orders = c("Ymd HMS", "mdY HMS", "Ymd HM", "mdy HM")) {
  parsed <- parse_date_time(x, orders = orders, quiet = TRUE)
  serial <- suppressWarnings(as.numeric(x))
  needs_serial <- is.na(parsed) & !is.na(serial)
  parsed[needs_serial] <- as.POSIXct(
    serial[needs_serial] * 86400, origin = "1899-12-30", tz = "UTC"
  )
  parsed
}

# ------------------------------------------------------------------
# Quick Update — skip Qualtrics label row, clean names
# ------------------------------------------------------------------
clean_quick <- raw_quick |>
  slice(-1) |>
  filter(!str_detect(StartDate, fixed("{")) | is.na(StartDate)) |>
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
    visit_date   = as.Date(parse_sheet_date(StartDate, orders = c("Ymd HMS", "mdY HMS", "Ymd HM", "mdy HM"))),
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
  filter(!is.na(school_name) & school_name != "" & !school_name %in% ignore_names)

# ------------------------------------------------------------------
# Full Update — skip Qualtrics label row, clean school names
# ------------------------------------------------------------------
clean_full <- raw_full |>
  slice(-1) |>
  filter(!str_detect(StartDate, fixed("{")) | is.na(StartDate)) |>
  rename(
    school_name         = `Q2.5`,
    recommend_mgr_swap  = Q27,
    recommend_project   = Q45,
    recommended_types   = Q82,
    recommended_other   = Q82_13_TEXT
  ) |>
  mutate(
    school_name = fix_school_name(school_name),
    update_date = as.Date(parse_sheet_date(StartDate, orders = c("mdY HMS", "Ymd HMS", "mdY HM", "mdy HM"))),
    # Clean up "Other:" in recommended project types
    recommended_types = if_else(
      !is.na(recommended_other) & recommended_other != "",
      str_replace(recommended_types, "Other:?", recommended_other),
      str_remove(recommended_types, ",?\\s*Other:?")
    ),
    across(where(is.character), str_trim)
  )

# ------------------------------------------------------------------
# Student Survey — skip label row, resolve "Other" write-ins
# ------------------------------------------------------------------
clean_student <- raw_student |>
  slice(-1) |>
  # Remove Qualtrics metadata rows (ImportId JSON objects from historical data)
  filter(!str_detect(Q3, fixed("ImportId"), negate = FALSE) | is.na(Q3)) |>
  filter(!str_detect(Q3, fixed("{"), negate = FALSE) | is.na(Q3)) |>
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
    # (Qualtrics stores the full answer text, not just "No")
    school_name = case_when(
      str_detect(is_existing, "(?i)first time") & !is.na(new_school) & new_school != "" ~ new_school,
      TRUE ~ school_name
    ),
    school_name  = fix_school_name(school_name),
    project_date = parse_sheet_date(StartDate, orders = c("mdY HMS", "Ymd HMS", "mdY HM")),
    project_date = as.Date(project_date)
  ) |>
  filter(!is.na(school_name) & school_name != "" & !school_name %in% ignore_names)

# ------------------------------------------------------------------
# Diagnostic: report any school names that don't match canonical list
# ------------------------------------------------------------------
all_survey_names <- bind_rows(
  tibble(source = "quick_update", school_name = clean_quick$school_name),
  tibble(source = "full_update",  school_name = clean_full$school_name),
  tibble(source = "student_survey", school_name = clean_student$school_name),
  tibble(source = "new_project",  school_name = clean_newproj$school_name)
) |>
  filter(!is.na(school_name) & school_name != "")

unmatched_names <- all_survey_names |>
  filter(!school_name %in% canonical_names) |>
  filter(!school_name %in% ignore_names) |>
  count(school_name, source, sort = TRUE)

if (nrow(unmatched_names) == 0) {
  cat("  All school names match the canonical list\n")
} else {
  cat("\n  *** UNMATCHED SCHOOL NAMES ***\n")
  cat("  These names appear in survey data but not in Schools Overview.\n")
  cat("  They may be typos (add to name_fixes) or genuinely new schools.\n\n")
  for (i in seq_len(nrow(unmatched_names))) {
    row <- unmatched_names[i, ]
    # Show the closest canonical match for easy diagnosis
    dists <- stringdist(tolower(row$school_name), tolower(canonical_names), method = "osa")
    closest <- canonical_names[which.min(dists)]
    cat("    '", row$school_name, "' (", row$n, "x in ", row$source,
        ") — closest match: '", closest, "'\n", sep = "")
  }
  cat("\n")
}

cat("  Cleaned 5 datasets\n")
