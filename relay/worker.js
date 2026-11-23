// KO3 bug-report relay.
//
// The plugin posts a report here; this Worker files it on GitHub with a
// fine-grained token that never ships in the plugin. Reports are rate-limited
// per IP so a public endpoint cannot be used to spam the tracker.
//
// Secrets:  GITHUB_TOKEN  fine-grained token, Issues: read and write on REPO
// Vars:     REPO          owner/name
// Bindings: RATE          KV namespace

const MAX_BODY_CHARS = 60000;
const DAILY_LIMIT = 10;
const LABEL = "bug";

function json(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8" },
  });
}

export default {
  async fetch(request, env) {
    if (request.method !== "POST") {
      return json({ error: "POST only" }, 405);
    }
    if (new URL(request.url).pathname !== "/report") {
      return json({ error: "not found" }, 404);
    }

    const ip = request.headers.get("CF-Connecting-IP") || "unknown";
    const day = new Date().toISOString().slice(0, 10);
    const key = `rl:${ip}:${day}`;
    const used = parseInt((await env.RATE.get(key)) || "0", 10);
    if (used >= DAILY_LIMIT) {
      return json({ error: "too many reports from this connection today" }, 429);
    }

    const text = await request.text();
    if (text.length > MAX_BODY_CHARS) {
      return json({ error: "report is too large" }, 413);
    }

    let data;
    try {
      data = JSON.parse(text);
    } catch {
      return json({ error: "invalid JSON" }, 400);
    }
    if (typeof data.title !== "string" || typeof data.body !== "string") {
      return json({ error: "title and body are required" }, 400);
    }

    const title = `[report] ${data.title}`.slice(0, 120);
    const body = [
      data.body,
      "",
      "---",
      `Relay received: ${new Date().toISOString()}`,
      `Client: ${String(data.version || "unknown").slice(0, 40)}`,
      `From: ${ip}`,
    ].join("\n");

    const response = await fetch(
      `https://api.github.com/repos/${env.REPO}/issues`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.GITHUB_TOKEN}`,
          Accept: "application/vnd.github+json",
          "User-Agent": "KO3-relay",
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ title, body, labels: [LABEL] }),
      },
    );

    if (!response.ok) {
      return json(
        { error: "the issue tracker rejected the report", status: response.status },
        502,
      );
    }

    const issue = await response.json();
    await env.RATE.put(key, String(used + 1), { expirationTtl: 172800 });
    return json({ url: issue.html_url, number: issue.number });
  },
};
