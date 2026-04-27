// Vercel serverless function — writes resolved issues to Google Sheets
// Requires SHEET_RESOLVED_ISSUES and GOOGLE_SERVICE_ACCOUNT_KEY env vars

import { google } from "googleapis";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const sheetId = process.env.SHEET_RESOLVED_ISSUES;
  const serviceAccountKey = process.env.GOOGLE_SERVICE_ACCOUNT_KEY;
  if (!sheetId || !serviceAccountKey) {
    return res.status(500).json({ error: "Server not configured for issue resolution" });
  }

  const { issue_id, school_name, issue_text, visit_date, resolved_by, resolution_notes } = req.body;
  if (!issue_id || !school_name || !resolved_by) {
    return res.status(400).json({ error: "issue_id, school_name, and resolved_by are required" });
  }

  try {
    const credentials = JSON.parse(serviceAccountKey);
    const auth = new google.auth.GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/spreadsheets"],
    });
    const sheets = google.sheets({ version: "v4", auth });

    const resolved_date = new Date().toISOString().slice(0, 10);

    await sheets.spreadsheets.values.append({
      spreadsheetId: sheetId,
      range: "Sheet1!A:G",
      valueInputOption: "USER_ENTERED",
      requestBody: {
        values: [[
          issue_id,
          school_name,
          issue_text || "",
          visit_date || "",
          resolved_date,
          resolved_by,
          resolution_notes || "",
        ]],
      },
    });

    // Trigger the dashboard rebuild workflow so the resolution shows up for
    // everyone within a couple of minutes instead of waiting for the next
    // scheduled run. Failures here are non-fatal — the sheet write is the
    // source of truth, and the next scheduled run will pick it up regardless.
    let rebuildTriggered = false;
    const ghToken = process.env.GITHUB_TOKEN;
    const ghRepo = process.env.GITHUB_REPO; // e.g. "moloughlin16/epi-dashboard"
    const ghWorkflow = process.env.GITHUB_WORKFLOW_FILE || "update-data.yml";
    if (ghToken && ghRepo) {
      try {
        const dispatchRes = await fetch(
          `https://api.github.com/repos/${ghRepo}/actions/workflows/${ghWorkflow}/dispatches`,
          {
            method: "POST",
            headers: {
              Accept: "application/vnd.github+json",
              Authorization: `Bearer ${ghToken}`,
              "X-GitHub-Api-Version": "2022-11-28",
              "Content-Type": "application/json",
            },
            body: JSON.stringify({ ref: "main" }),
          }
        );
        rebuildTriggered = dispatchRes.ok;
        if (!dispatchRes.ok) {
          const detail = await dispatchRes.text();
          console.warn("workflow_dispatch failed:", dispatchRes.status, detail);
        }
      } catch (err) {
        console.warn("workflow_dispatch error:", err.message);
      }
    }

    return res.status(200).json({ success: true, resolved_date, rebuildTriggered });
  } catch (err) {
    return res.status(500).json({ error: "Failed to write to Google Sheet", details: err.message });
  }
}
