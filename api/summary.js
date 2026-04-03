// Vercel serverless function — proxies AI summary requests to Gemini API
// Keeps the API key server-side (set GEMINI_API_KEY in Vercel environment variables)

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    return res.status(500).json({ error: "GEMINI_API_KEY not configured" });
  }

  const { school_name, notes } = req.body;
  if (!school_name || !notes || notes.length === 0) {
    return res.status(400).json({ error: "school_name and notes are required" });
  }

  const prompt =
    `You are summarizing field visit notes for ${school_name}, ` +
    `a school in rural Ghana participating in Empower Playgrounds Inc. programs.\n\n` +
    `Based on the following staff observations, write a concise 2-3 paragraph summary ` +
    `covering: (1) what the school is doing well, (2) current challenges, and ` +
    `(3) any urgent issues needing attention.\n\n` +
    `Notes:\n${notes.join("\n\n")}`;

  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: prompt }] }],
        }),
      }
    );

    if (!response.ok) {
      const err = await response.text();
      return res.status(502).json({ error: "Gemini API error", details: err });
    }

    const data = await response.json();
    const summary = data.candidates?.[0]?.content?.parts?.[0]?.text;

    if (!summary) {
      return res.status(502).json({ error: "No summary returned from Gemini" });
    }

    return res.status(200).json({ summary });
  } catch (err) {
    return res.status(500).json({ error: "Server error", details: err.message });
  }
}
