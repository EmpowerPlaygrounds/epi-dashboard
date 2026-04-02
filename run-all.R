# run-all.R — Execute the full data pipeline
# Called by Quarto pre-render or manually via: Rscript run-all.R

library(here)

cat("=== EPI Data Pipeline ===\n")

cat("[1/4] Importing from Google Sheets...\n")
source(here("R", "01-import.R"))

cat("[2/4] Cleaning data...\n")
source(here("R", "02-clean.R"))

cat("[3/4] Joining datasets...\n")
source(here("R", "03-join.R"))

cat("[4/4] Exporting CSVs and JSONs...\n")
source(here("R", "04-export.R"))

cat("=== Pipeline complete ===\n")
