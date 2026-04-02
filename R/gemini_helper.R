# gemini_helper.R — Reusable function to generate AI summaries via Gemini API

library(httr2)
library(jsonlite)
library(dotenv)
library(here)

load_dot_env(here(".env"))

#' Generate a school summary using Gemini
#'
#' @param school_name Character. Name of the school.
#' @param notes Character vector. Field visit notes (Q26, Q27, Q28, Q93).
#' @return Character string with the AI-generated summary.
generate_school_summary <- function(school_name, notes) {
  api_key <- Sys.getenv("GEMINI_API_KEY")
  if (api_key == "") stop("GEMINI_API_KEY not set in .env")

  prompt <- paste0(
    "You are summarizing field visit notes for ", school_name,
    ", a school in rural Ghana participating in Empower Playgrounds Inc. programs.\n\n",
    "Based on the following staff observations, write a concise 2-3 paragraph summary ",
    "covering: (1) what the school is doing well, (2) current challenges, and ",
    "(3) any urgent issues needing attention.\n\n",
    "Notes:\n", paste(notes, collapse = "\n\n")
  )

  resp <- request("https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent") |>
    req_url_query(key = api_key) |>
    req_body_json(list(
      contents = list(list(
        parts = list(list(text = prompt))
      ))
    )) |>
    req_perform()

  body <- resp_body_json(resp)
  body$candidates[[1]]$content$parts[[1]]$text
}
