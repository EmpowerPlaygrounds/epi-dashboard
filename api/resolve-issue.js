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

    return res.status(200).json({ success: true, resolved_date });
  } catch (err) {
    return res.status(500).json({ error: "Failed to write to Google Sheet", details: err.message });
  }
}
