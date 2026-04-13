# gemini_helper.R — Reusable function to generate AI summaries via Gemini API

library(httr2)

if (file.exists(".env")) dotenv::load_dot_env()

generate_school_summary <- function(school_name, notes,
                                    system_prompt = NULL) {

  api_key <- Sys.getenv("GEMINI_API_KEY")
  if (api_key == "" || api_key == "your-key-here") {
    return("Gemini API key not configured. Add it to .env")
  }

  if (is.null(system_prompt)) {
    system_prompt <- paste(
      "You are summarizing field visit notes for", school_name,
      ", a school in rural Ghana participating in Empower",
      "Playgrounds Inc. programs. Based on the staff observations",
      "below, write a summary in exactly this format:\n\n",
      "**Doing Well:** Summarize what this school is doing well.\n\n",
      "**Challenges:** Summarize any challenges, struggles, or urgent issues.\n\n",
      "**Recommendations:** Provide actionable recommendations based on",
      "staff observations and the challenges listed.\n\n",
      "Keep each section to 2-3 sentences. If no information is",
      "available for a section, write 'No information available.'"
    )
  }

  prompt <- paste(system_prompt, "\n\nNotes:\n",
                  paste(notes, collapse = "\n\n"))

  tryCatch({
    resp <- request("https://generativelanguage.googleapis.com/v1beta") |>
      req_url_path_append("models/gemini-2.5-flash:generateContent") |>
      req_url_query(key = api_key) |>
      req_body_json(list(
        contents = list(list(
          parts = list(list(text = prompt))
        ))
      )) |>
      req_perform()

    body <- resp_body_json(resp)
    body$candidates[[1]]$content$parts[[1]]$text

  }, error = function(e) {
    paste("Could not generate summary:", e$message)
  })
}
