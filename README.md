# EPI Data Dashboard

A Quarto + R dashboard for **Empower Playgrounds Inc. (EPI)** that consolidates field visit reports, student surveys, project records, and school metadata into an interactive website. Built as the final project for GLHLTH 562 at Duke University.

Live pages: **Overview** | **School Profiles** | **Visits** | **Student Surveys** | **Issues**

---

## Data Sources

All source data lives in five Google Sheets maintained by EPI field staff in Ghana. Four of the five sheets are Qualtrics survey exports (Quick Update, Full Update, Student Survey, New Project); the fifth is a manually maintained school roster.

| Sheet | Description | Key fields |
|---|---|---|
| **Schools Overview** | Canonical list of EPI partner schools with location, region, programs offered | School Name, Latitude, Longitude, Region, Programs (Merry-Go-Round, Solar Lanterns, etc.) |
| **Quick Update** (Qualtrics) | Short field visit reports filed after each school visit | Visitor, School, Visit Date, Visit Reason, Activities, Doing Well, Struggles, Urgent Issues, Observations |
| **Full Update** (Qualtrics) | Longer periodic school assessments | School, Update Date, detailed program-level questions |
| **Student Survey** (Qualtrics) | Student-level responses about program access | School, Lantern Group, Library Access, Menstrual Kit, Computer Access |
| **New Project** (Qualtrics) | Records of new project installations at schools | Visitor, School, Project Type, Date |

Sheet IDs are stored in a `.env` file (not committed) and read at runtime.

---

## Data Pipeline

The pipeline is four R scripts executed sequentially by `run-all.R`. Quarto calls this automatically via the `pre-render` hook in `_quarto.yml`, so data is always refreshed before the site builds.

```
run-all.R
  -> R/01-import.R   (Google Sheets -> data/raw/*.csv)
  -> R/02-clean.R     (raw CSVs -> cleaned data frames)
  -> R/03-join.R      (cleaned frames -> joined master table)
  -> R/04-export.R    (joined data -> data/clean/*.csv + per-school JSONs)
```

### Step 1: Import (`R/01-import.R`)

- **Packages:** `googlesheets4`, `dotenv`, `tidyverse`, `here`
- Reads five Google Sheet IDs from environment variables (`SHEET_SCHOOLS_OVERVIEW`, `SHEET_QUICK_UPDATE`, `SHEET_FULL_UPDATE`, `SHEET_STUDENT_SURVEY`, `SHEET_NEW_PROJECT`)
- Uses `gs4_deauth()` for public sheet access (switch to `gs4_auth()` with a service account JSON if sheets become private)
- Qualtrics sheets are read with `col_types = "c"` (all character) to prevent googlesheets4 from mis-typing the StartDate column due to a Qualtrics label row
- Writes raw CSVs to `data/raw/`

### Step 2: Clean (`R/02-clean.R`)

- **Packages:** `tidyverse`, `lubridate` (via tidyverse), `here`
- Drops the Qualtrics metadata/label row (row 1 after header) from all survey sheets using `slice(-1)`
- Renames cryptic Qualtrics column codes (e.g., `Q95` -> `school_name`, `Q1` -> `visitor`) to readable names
- Parses `StartDate` strings into proper dates using `parse_date_time()` with multiple format orders (`"mdY HMS"`, `"Ymd HMS"`, `"mdY HM"`)
- Applies a **school name crosswalk** (`name_fixes` vector) to standardize typos and variant spellings across all datasets to match the canonical Schools Overview roster (e.g., "Mepotumtum" -> "Bepotumtum", "Watroso" -> "Watro (Watroso)")
- Resolves Qualtrics "Other" write-in fields — replaces generic "Other:" entries with the actual free-text response from the companion `_TEXT` column
- Filters out rows with missing school names

### Step 3: Join (`R/03-join.R`)

- **Packages:** `tidyverse`, `here`
- Builds summary tables from the cleaned data:
  - **Visit counts** per school (from Quick Update)
  - **Survey summaries** per school — response count plus proportion answering "Yes" to lantern group, library, menstrual kit, and computer access questions
  - **Issue counts** per school (rows where `urgent_issues` is non-empty)
- Left-joins all summaries onto the canonical school list by `school_name`
- Replaces `NA` counts with `0`

### Step 4: Export (`R/04-export.R`)

- **Packages:** `tidyverse`, `jsonlite`, `here`
- Writes six flat CSVs to `data/clean/`:
  - `schools.csv` — master school table with joined summaries
  - `visits.csv` — all cleaned field visits
  - `surveys.csv` — all cleaned student survey responses
  - `new_projects.csv` — all cleaned new project records
  - `full_updates.csv` — all cleaned full update records
  - `issues.csv` — filtered subset of visits where `urgent_issues` is non-empty (excludes "No", "None", "N/A" responses)
- Writes per-school JSON files to `data/clean/schools/<slug>.json` containing that school's info, visits, full updates, surveys, and issues
- Writes `data/clean/school_index.json` mapping school names to URL-safe slugs

---

## Output

A static Quarto website (`_site/`) with five pages:

| Page | What it shows |
|---|---|
| **Overview** | Stat cards (visit count, new projects, full updates, survey responses, open issues), Leaflet school map, recent visits table, recent projects table, program availability bars, schools with open issues |
| **School Profiles** | Dropdown to select a school; shows header with programs, visit stats, survey summary bars, notes from last visit, visit history table — all filterable by date range |
| **Visits** | Pie chart of schools visited vs. not visited, full visit log DataTable, visits-by-school count table — all filterable by date range |
| **Student Surveys** | Stat cards, survey response DataTable with school filter, all filterable by date range |
| **Issues** | Stat cards, list of all urgent issues with links to school profiles |

Client-side interactivity uses **Chart.js** (pie charts), **Leaflet** (maps), **jQuery DataTables** (sortable/searchable tables), and vanilla JavaScript for date range filtering. All data is embedded as JSON in `<script>` tags at build time — no server or API calls are needed to view the dashboard.

### AI Summary Feature

The School Profiles page includes a "Generate AI Summary" button that calls the **Google Gemini API** (`gemini-2.0-flash`) at view time to produce a narrative summary of a school's field visit notes. This requires a `GEMINI_API_KEY` in the `.env` file. The helper function is in `R/gemini_helper.R`.

---

## How to Run It

### Prerequisites

- **R** (>= 4.3) with the following packages:
  ```r
  install.packages(c(
    "tidyverse", "googlesheets4", "jsonlite",
    "dotenv", "here", "DT", "htmltools", "httr2", "leaflet"
  ))
  ```
- **Quarto** (>= 1.4) — [install here](https://quarto.org/docs/get-started/)
- **Node.js** (optional, for local preview server via `npx http-server`)

### Environment Setup

Create a `.env` file in the project root with your Google Sheet IDs and (optionally) a Gemini API key:

```
SHEET_SCHOOLS_OVERVIEW=<Google Sheet ID>
SHEET_QUICK_UPDATE=<Google Sheet ID>
SHEET_FULL_UPDATE=<Google Sheet ID>
SHEET_STUDENT_SURVEY=<Google Sheet ID>
SHEET_NEW_PROJECT=<Google Sheet ID>
GEMINI_API_KEY=<your Gemini API key>
```

Each Sheet ID is the long string in the Google Sheets URL between `/d/` and `/edit` (e.g., `1aBcDeFgHiJkLmNoPqRsTuVwXyZ`).

If the sheets are **public** (anyone with the link can view), no additional authentication is needed. If they are **private**, you will need to either:
- Run `googlesheets4::gs4_auth()` interactively to use OAuth, or
- Set up a Google Cloud service account and point `gs4_auth(path = "service-account.json")` to the key file

### Build the Site

```bash
# Full build (runs data pipeline + renders all pages)
quarto render

# Or run the data pipeline manually first
Rscript run-all.R
quarto render
```

### Preview Locally

```bash
# Option 1: Quarto preview (watches for changes)
quarto preview

# Option 2: Static file server
npx http-server _site -p 8080
```

### Project Structure

```
epi-dashboard/
├── _quarto.yml          # Site config (navbar, theme, pre-render hook)
├── run-all.R            # Pipeline orchestrator
├── R/
│   ├── 01-import.R      # Google Sheets -> data/raw/
│   ├── 02-clean.R       # Raw -> cleaned data frames
│   ├── 03-join.R        # Join datasets by school name
│   ├── 04-export.R      # Export CSVs + per-school JSONs
│   └── gemini_helper.R  # Gemini API wrapper for AI summaries
├── index.qmd            # Overview page
├── schools.qmd          # School Profiles page
├── visits.qmd           # Visits page
├── surveys.qmd          # Student Surveys page
├── issues.qmd           # Issues page
├── styles.css           # Custom CSS (stat cards, nav, tables)
├── images/
│   └── epi-logo.png     # Navbar logo
├── data/
│   ├── raw/             # Raw CSVs from Google Sheets (gitignored)
│   └── clean/           # Pipeline output CSVs + JSONs (gitignored)
├── _site/               # Rendered HTML output (gitignored)
└── .env                 # Sheet IDs + API keys (gitignored)
```

### Deployment

The `_site/` directory contains a fully static website that can be deployed to any static hosting service:

- **GitHub Pages:** Push `_site/` to a `gh-pages` branch, or configure GitHub Actions to run `quarto render` and publish
- **Netlify/Vercel:** Point the build command to `quarto render` and the publish directory to `_site`
- **Manual:** Copy the `_site/` folder to any web server

Note: The data pipeline requires Google Sheets access, so automated CI/CD builds need either public sheets or a service account credential file.
