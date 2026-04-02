# 01-import.R — Pull all 4 Google Sheets into data/raw/

library(tidyverse)
library(googlesheets4)
library(dotenv)
library(here)

load_dot_env(here(".env"))

# Authenticate with Google Sheets (service account or cached OAuth)
gs4_deauth()  # Use public access; switch to gs4_auth() if sheets are private

# Sheet IDs from .env
id_schools   <- Sys.getenv("SHEET_SCHOOLS_OVERVIEW")
id_quick     <- Sys.getenv("SHEET_QUICK_UPDATE")
id_full      <- Sys.getenv("SHEET_FULL_UPDATE")
id_student   <- Sys.getenv("SHEET_STUDENT_SURVEY")
id_newproj   <- Sys.getenv("SHEET_NEW_PROJECT")

# Import each sheet
# Qualtrics sheets have a label row (row 2) with text like "Start Date" that
# causes googlesheets4 to mis-type the StartDate column. Fix: read with
# col_types to force StartDate as character, then parse dates after dropping
# the label row in 02-clean.R.
raw_schools <- read_sheet(id_schools)
raw_quick   <- read_sheet(id_quick,   col_types = "c")
raw_full    <- read_sheet(id_full,    col_types = "c")
raw_student <- read_sheet(id_student, col_types = "c")
raw_newproj <- read_sheet(id_newproj, col_types = "c")

# Save raw data
dir.create(here("data", "raw"), showWarnings = FALSE, recursive = TRUE)

write_csv(raw_schools, here("data", "raw", "schools_overview.csv"))
write_csv(raw_quick,   here("data", "raw", "quick_update.csv"))
write_csv(raw_full,    here("data", "raw", "full_update.csv"))
write_csv(raw_student, here("data", "raw", "student_survey.csv"))
write_csv(raw_newproj, here("data", "raw", "new_project.csv"))

cat("  Imported 5 sheets to data/raw/\n")
