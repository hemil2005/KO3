# KO3 report relay

A tiny Cloudflare Worker that files bug reports as GitHub issues. The
plugin posts a report here; the Worker holds the GitHub token, so no
credential ships in the plugin and users do not need a GitHub account.

```
plugin ──POST /report──▶ Worker ──POST /repos/.../issues──▶ GitHub
                          │
                          └─ KV: 10 reports / IP / day
```

Deployed endpoint (used by `bugreport.lua`):

```
https://ko3-reports.ko3-reports.workers.dev/report
```

## Configuration

| Name | Kind | Value |
|---|---|---|
| `REPO` | var | `hemil2005/KO3` |
| `GITHUB_TOKEN` | secret | fine-grained token, **Issues: read and write**, only this repo |
| `RATE` | KV binding | namespace id in `wrangler.toml` |

The token is fine-grained and scoped to KO3 issues only. Rotate it when it
expires (90 days) with `wrangler secret put GITHUB_TOKEN`; no code change or
plugin release is needed.

## Deploy

From this directory, with a Cloudflare account that has Workers enabled:

```sh
npx wrangler login

# once, if the namespace does not exist yet
npx wrangler kv namespace create RATE
# put the printed id in wrangler.toml

npx wrangler secret put GITHUB_TOKEN   # paste the fine-grained token
npx wrangler deploy
```

The first deploy needs a `workers.dev` subdomain; the dashboard or the API
(`PUT /accounts/<id>/workers/subdomain`) sets it. The account subdomain is
not renameable later.

## Behaviour

- `POST /report` with `{ "title": "...", "body": "...", "version": "..." }`.
- Body is capped at 60,000 characters (GitHub's limit is 65,536).
- Creates an issue titled `[report] <title>` with the `bug` label.
- Rate limit: 10 reports per IP per day (KV counter, 2-day expiry).
- Returns `{ "url": "...", "number": N }` on success; `429` when limited.
- GET/other paths return 405/404, so the endpoint is not a web page.

## Local development

```sh
npx wrangler dev
```

KV and the GitHub token are read from the same bindings; use a test repo and
a throwaway token locally.

## Privacy

The Worker only receives what the plugin's consent dialog describes: the
description, the environment block, and (if attached) the log. It adds the
client IP and a timestamp to the issue body. It stores only a per-IP daily
counter in KV.
