# AO3 access policy and the 403/429 failures

**Prepared:** 2026-11-23
**Scope:** why a normal browser reaches AO3 while this plugin's LuaSocket client gets `403` and independent `curl` gets `429`; what AO3/OTW officially permits for a read-only native e-reader client; feasible, non-evasive options.
**Method:** no request was made to any `archiveofourown.org` host. AO3 pages were read through Wayback Machine snapshots; Cloudflare documentation was read from `developers.cloudflare.com`; OTW status was read from `otwstatus.org`. Status is a moving target after the October 2026 incident, so the dates below matter.

**Implementation update:** after this research, the plugin was changed to recognize `cf-mitigated: challenge` or a `Just a moment` browser-check page and avoid retrying that response. References below to retrying *all* 403s describe the pre-change version; other 403s still receive one retry.

**Evidence labels**

- **[OFFICIAL]** — stated by AO3/OTW in policy, FAQ, source code, or status update.
- **[VENDOR]** — stated by Cloudflare in its documentation.
- **[INFERENCE]** — a reasoned conclusion from the above plus this project's observed behaviour; not directly confirmed.
- **[UNVERIFIED]** — plausible but not checked, usually because checking would mean probing AO3.

---

## 1. What the client actually sends

From `ao3.koplugin/main.lua`:

| Item | Current behaviour |
|---|---|
| Endpoints | `GET /works`, `/works/search?...`, `/tags/<tag>/works?page=N`, and `download.archiveofourown.org/downloads/<id>/work.html` |
| User-Agent | A desktop Chrome 142 UA string, not the app's own name |
| Cookies | Only `view_adult=true`; no cookie jar, no Cloudflare cookies |
| Pacing | Minimum 1.0 s between requests |
| `403` handling | Immediate retry once after 3 s, then a 5-minute block |
| `429` handling | Honours numeric `Retry-After`, otherwise 60 s minimum, then blocks |
| Transport | LuaSocket `socket.http` + `ltn12` (HTTP/1.1, OpenSSL), no JavaScript, no HTTP/2, no browser client hints |

The project's `spec/fixtures/challenge.html` is the Cloudflare interstitial (`<title>Just a moment...</title>` / “Enable JavaScript and cookies to continue”). The README records the observed split: browser succeeds; LuaSocket gets `403`; independent Windows/WSL `curl` gets `429`.

---

## 2. Bottom line

1. **These are edge/bot-management outcomes, not content permissions.** AO3 is not saying “this work is forbidden”; Cloudflare (and, separately, AO3's own Rack::Attack limiter) is deciding whether the *client* may reach the origin at all.
2. **The browser may succeed because it carries state and can run challenges.** Depending on AO3's current edge configuration it may hold `__cfwaitingroom`, `__cf_bm` or `cf_clearance`; we have not inspected the user's browser cookies or the rejected response headers. LuaSocket has none of these by default and cannot execute JavaScript challenges. A fresh `curl` also lacks browser session state; if a waiting room is involved, it may be treated as a new visitor each time.
3. **There is no supported native-client API.** AO3 says so explicitly. The supported machine-readable surfaces are **work downloads** (AO3 explicitly allows external services/scripts to download, subject to policy) and **tag RSS/Atom feeds**. The durable architecture for this plugin is therefore *user/browser-initiated download → local import → offline reading*, not a native HTTP scraper.
4. **Retrying is counter-productive.** A `403` challenge will not resolve by repeating the same request; a `429` is an explicit “slow down” signal. The current single 3-second retry on `403` should be removed.

---

## 3. Official AO3/OTW statements

### 3.1 Bots and scraping are conditionally allowed

> “The use of bots or scraping for spam, commercial promotion, or other purposes that violate our policies is forbidden. This includes scraping AO3 for the purposes of obtaining material for commercial generative AI or creating an app that hosts or paywalls AO3 content.
>
> The use of bots or scraping for purposes that do not violate our policies is generally allowed. However, we reserve the right to implement robots.txt or other protocols limiting what bots can do, or to notify you and ask you to discontinue if a bot or scraping program is causing problems for the site. At our discretion, we may also ban specific bots or other programs from accessing AO3.”

— AO3 Terms of Service FAQ, “Spam and Technical Integrity” **[OFFICIAL]** [S1]

Implication: a free, non-commercial, read-only reader is **not categorically forbidden**, but it is expressly subject to AO3's technical limits and to being asked to stop or banned. There is no “allowed because non-commercial” safe harbour.

### 3.2 Interference and commercial scraping are prohibited

The Terms of Service forbid using AO3:

> “to conduct any commercial activity, whether for direct or indirect commercial advantage, including (without limitation) making available any advertising, spam, or other solicitation, or scraping Content in order to commercialize it;”
>
> “to interfere with or disrupt AO3, any OTW-hosted Content, or any services, sites, servers, or networks connected to OTW sites;”

— AO3 Terms of Service I.F, effective 2024-11-19 **[OFFICIAL]** [S2]

Implication: no ads, paywalls, paid tiers, or resale of AO3 content; and request volume that degrades the service is itself a policy problem, not only a technical one.

The same section also forbids using AO3 “to forge or otherwise manipulate identifiers … in order to disguise the origin of any Content transmitted to or through any OTW sites, servers, networks, or services” **[OFFICIAL]** [S2]. A desktop-Chrome User-Agent sent by a LuaSocket client is not a cookie or a cryptographic identifier, but it is an identifier the client is misrepresenting. Even if it is not the strongest clause in the TOS, it weakens the “good-faith reader” position and gives AO3/Cloudflare a factual reason to distrust the client. An honest app User-Agent is the defensible choice.

### 3.3 AO3 rate-limits and does not exempt “good” crawlers

> “We've put in place certain technical measures to hinder large-scale data scraping on AO3, such as rate limiting, and we're constantly monitoring our traffic for signs of abusive data collection. We do not make exceptions for researchers or those wishing to create datasets. However, we don't have a policy against responsible data collection — such as those done by academic researchers, fans backing up works to Wayback Machine or Google's search indexing.”

— OTW, “AI and Data Scraping on the Archive,” 2023-05-13 **[OFFICIAL]** [S3]

Implication: there is no research/app allowlist to appeal to, and “responsible” is the standard. A single user tapping a page at human pace fits; prefetching, pagination loops, and retries do not.

### 3.4 There is no official API and no official app

> “Before we can have apps for the various mobile platforms, we need to have a public Application Program Interface (API). Without an API, no app would be able to access the Archive database in any useful way. Whilst creating an API is on our roadmap, it's still several major releases away…”

— AO3 About FAQ **[OFFICIAL]** [S4]

> “There is no official AO3 app. If you have come across or are using an app that looks like AO3, it is not official and is not owned by the OTW. These apps are made by third parties and are normally just specialized web browsers…”
>
> “Anyone charging you for access to AO3 in any way – whether by forcing you to view ads, pay to access works, or subscribe to enable additional features – is violating the AO3 Terms of Service.”

— OTW, “Why AO3 Doesn't Have an Official App,” 2026-07-24 **[OFFICIAL]** [S5]

Implication: this plugin is an unofficial third-party client. That is not banned, but it has no compatibility guarantee, no API contract, and must remain free and non-commercial. AO3 Support handles “reports about unofficial AO3 apps.”

### 3.5 External scripts may download works — with a cookie caveat

> “Can I download works from the Archive via external services or scripts?
>
> Yes. However, if a service or script doesn't support cookies or session login details, downloads of works restricted to Archive of Our Own (AO3) users or with adult content warnings will give you the login or adult content confirmation pages instead of the actual work.”

— AO3 Downloading Fanworks FAQ **[OFFICIAL]** [S6]

This is the most directly useful official statement for this project: a script that downloads public works is contemplated and permitted, but it must not expect restricted/adult works to work without a session. It does not override the rate limits, robots policy, or the ban on disruption.

### 3.6 Offline reading is an explicitly recommended path

> “You can also download works to access offline with an e-reader or similar app.”

— AO3 About FAQ **[OFFICIAL]** [S4]

> “If you want to access works offline, you can download works from AO3 directly onto your mobile device. We offer a variety of download formats to fit a range of programs and devices.”

— OTW, “Why AO3 Doesn't Have an Official App” **[OFFICIAL]** [S5]

Implication: AO3's own recommended answer for e-readers is the download button, not a native browser engine or a scraper.

### 3.7 Current incident status explains the timing

Official status updates:

- 2026-11-15: AO3 is back after the security incident, but “icons … external work importing … [are] unavailable, and works can only be downloaded in HTML format.”
- 2026-11-15: “Due to high traffic, you may experience a delay before AO3 loads. This is an intentional measure to help manage traffic. If you see the AO3 downtime page, please refresh and try again!”
- 2026-11-19 23:47 UTC (latest at time of writing): AO3 is back after a further maintenance window; the delay/traffic-management language remains. The 2026-11-17 update still listed non-HTML downloads and importing as disabled, and no later update restored them.

— OTW status page, incident “AO3 Down for Maintenance” **[OFFICIAL]** [S7]

Implication: as of 2026-11-23 AO3 is deliberately gating traffic and serving only HTML downloads. This alone makes `403`/`429` for a non-browser client expected. It is also temporary in principle, though OTW has not said when the gate will be removed.

### 3.8 AO3's robots.txt

Snapshot of `https://archiveofourown.org/robots.txt` (2024 capture; the 2026 third-party index still reports the same AI-crawler blocks) **[OFFICIAL]** [S8]:

```text
User-agent: *
Disallow: /works?          # "cruel but efficient"
Disallow: /autocomplete/
Disallow: /downloads/
Disallow: /external_works/
Disallow: /bookmarks/search?
Disallow: /people/search?
Disallow: /tags/search?
Disallow: /works/search?

User-agent: CCBot
Disallow: /
User-agent: GPTBot
Disallow: /
User-agent: ChatGPT-User
Disallow: /
User-agent: Slurp
Crawl-delay: 30
```

Relevant consequences:

- `/works` (the first “Latest works” page) is allowed; `/works?page=2` is **disallowed** by the `Disallow: /works?` prefix.
- `/works/search?…` is disallowed.
- `/tags/<tag>/works?page=N` is not covered by those rules and is allowed for `*`.
- `/downloads/` is disallowed on the main host. The project downloads from `download.archiveofourown.org`; whether that host serves the same `robots.txt` was **not checked** [UNVERIFIED].
- Robots rules are crawler directives, not a user-agent contract. A single user-initiated download is within AO3's FAQ [S6]; automated crawling of listings or bulk downloading is not.

### 3.9 AO3 still aims to work without JavaScript

AO3's Accessing Fanworks FAQ says the Archive's main functions should work without JavaScript, while some optional features will not **[OFFICIAL]** [S9]. That is about the *site*; Cloudflare's challenge/waiting room is a separate layer and **does** require JavaScript. A no-JS origin does not imply a no-JS path through the edge.

---

## 4. Why the three clients get different answers

**Attribution caveat.** OTW's status updates say “intentional measure to help manage traffic” and do not name Cloudflare [S7]. Cloudflare is strongly indicated by the project's `403` fixture (`Just a moment...`), Cloudflare's documented `cf-*` headers/cookies, and press reports describing a “Cloudflare waiting room” [secondary]. The mechanics below are backed by Cloudflare documentation, but the exact rules AO3 has configured are **[INFERENCE]** / **[UNVERIFIED]**.

### 4.1 Browser → working, per user report

- If challenged, it can execute the browser-side verification and receive `cf_clearance`; Cloudflare documents this cookie as proof of client-side verification, **tied to the specific visitor and device** **[VENDOR]** [S10]. We have not confirmed that this particular browser holds it.
- It may keep `__cf_bm`, which Cloudflare says smooths the bot score across a session **[VENDOR]** [S11].
- If AO3 uses a Cloudflare waiting room for this route, it may keep `__cfwaitingroom`; that cookie is mandatory while such a room is queueing **[VENDOR]** [S12]. AO3's exact configuration is unverified.
- Its TLS/HTTP fingerprint, header order, client hints, `Sec-Fetch-*` headers, HTTP/2, and real browser behaviour are all consistent with the UA it claims.

### 4.2 LuaSocket → 403

Likely chain **[INFERENCE]**:

1. The request presents a **Chrome UA** but none of the signals a Chrome browser would present (no `Sec-CH-UA`, no `Sec-Fetch-*`, no HTTP/2, different TLS stack, no JS). Cloudflare's Browser Integrity Check explicitly challenges “visitors without a user agent or with a non-standard user agent,” and its ML bot score uses headers, session characteristics and browser signals **[VENDOR]** [S13][S11]. Cloudflare also lists IP reputation, bot detection and BIC among the reasons a legitimate-looking visitor can be challenged **[VENDOR]** [S19][S20].
2. It has no `cf_clearance`, no `__cf_bm`, and no waiting-room cookie, so it cannot inherit the browser's pass.
3. Cloudflare serves the challenge page — an HTML response with `cf-mitigated: challenge`, commonly HTTP `403` — and LuaSocket cannot execute it **[VENDOR]** [S14].
4. The plugin retries the identical request after 3 s. The challenge is deterministic for that client, so the retry cannot succeed and only adds traffic.

The UA spoof is not the sole cause, but it makes the client *maximally inconsistent*: it claims to be the one kind of client it is least like.

### 4.3 curl → 429

`429` has at least three possible producers here; without response headers they cannot be distinguished [UNVERIFIED]:

| Producer | Why it fits | Documented signal |
|---|---|---|
| Cloudflare Waiting Room | `curl` sends no `__cfwaitingroom`; Cloudflare says a request without the cookie is treated as a **new user** and placed at the **end of the queue**. Queueing status is operator-configurable and **may be `429`**. | `__cfwaitingroom`, `cf-ray`; body is the waiting-room page/JSON [S12][S15] |
| Cloudflare rate limiting | Independent requests from the same IP/bot fingerprint can trip an edge rate-limit rule. | `429`, often `Retry-After`, `cf-ray` [S16] |
| AO3 Rack::Attack | AO3's own middleware throttles **300 requests / 300 s per IP** by default and enables `Retry-After` on throttle responses. | `429`, `Retry-After`; no Cloudflare challenge marker [S17] |

The waiting-room explanation is the strongest for a *first* `curl` request that follows browser use **[INFERENCE]**: the browser got in because it held a queue cookie; `curl` arrived with no cookie and was treated as a new arrival. Every fresh `curl` process repeats that, so it can remain stuck in the queue even at trivial request volume.

Cloudflare does document a JSON-friendly waiting room intended for native apps **[VENDOR]** [S15]. It is not a client-side workaround: the site operator must enable it, the client must still persist and resend `__cfwaitingroom`, and it disables Turnstile for those requests. There is no evidence that AO3 has enabled it [UNVERIFIED], so it is not an option this plugin can adopt on its own.

### 4.4 Why browser works but the others do not — one-line summary

**The observed split is consistent with browser session/verification state and AO3's traffic management, not a work-level content restriction. The exact cause of the browser's success and the two different rejection statuses has not been established from response headers.**

---

## 5. What not to build

These would “work” in the narrow sense and are exactly what this investigation must not recommend:

- Solving or farming Cloudflare challenges in a headless browser, then replaying `cf_clearance`/`__cf_bm` into LuaSocket.
- Copying cookies out of the user's browser or asking the user to paste them.
- Rotating IPs, proxies, VPNs, Tor, or cloud egress to get a “clean” reputation.
- Randomising User-Agent/header order/TLS fingerprints to impersonate a browser.
- Retry loops, parallel prefetching, or crawling pagination to “get past” `429`.
- Bulk-downloading works or building a mirror.

Why: these are bypasses of an access-control decision, they violate the spirit (and plausibly the letter) of AO3's reserved right to limit bots [S1], they risk the user's IP/account, and they are fragile — Cloudflare changes the rules faster than the plugin can chase them. The project's own README already states the right principle: it does not replay Cloudflare cookies because they are bound to the client that earned them.

---

## 6. Feasible, supported options

### Option A — Browser-mediated download + local import (recommended)

**What:** The user opens AO3 in the device/desktop browser, taps **Download → HTML** (the only format currently enabled [S7]), and the plugin opens/imports the saved file. Optionally support a file-picker or “share to KOReader” flow.

**Why it is supported:** AO3 explicitly recommends downloading works for offline e-reader reading [S4][S5], and the Downloading FAQ documents HTML as an e-reader-compatible format [S6]. No bot defence is bypassed; the browser does what browsers do.

**Limits:** manual step per work; during the incident only HTML is offered; multi-chapter/updated works need re-download; restricted works require the user's own logged-in browser; the plugin cannot discover new works this way.

### Option B — Lean into the offline fandom index and local library (already implemented)

**What:** Keep the shipped 77,535-fandom snapshot, offline search, and saved-work library as the primary experience. Make online fetching an optional enhancement, clearly labelled.

**Why:** It is policy-neutral, works during outages, and matches AO3's “download for offline” guidance. The index is a point-in-time copy, so tag renames still 404 — already documented.

**Limits:** no new works, no fresh summaries, no search across the live archive.

### Option C — Official tag RSS/Atom feeds for discovery

**What:** AO3 officially provides feeds for canonical tags (fandom, character, relationship; not freeform/additional tags), intended for personal feed readers. The feed URL is typically `/tags/<tag>/feed.atom`; the “RSS Feed” button is on the tag page.

**Why:** It is a documented, machine-readable, low-volume surface rather than HTML scraping [S18]. One request can surface the latest works for a tag.

**Limits:** canonical tags only (not freeform/additional tags); feeds are unfiltered; they report new works, not updates; there is no search and no full text; archive-locked works are not visible (inference from feed behaviour, not stated in the FAQ); and feed readers still pass through the same Cloudflare edge, so this is **not** a guaranteed way around the current `403`/`429`. It is a better-shaped request, not an exemption.

### Option D — Polite direct fetch as a fallback, with hard limits

If the plugin keeps any online fetch, constrain it to what AO3's policy can tolerate:

- One request per explicit user action; **no** automatic pagination, prefetch, refresh loops, or background sync.
- No retry on `403`; treat it as “blocked/challenged” and stop.
- Honour `429` + `Retry-After`; cap total requests per session well below AO3's default 300/5 min per IP; prefer ≥5–10 s between requests, not 1 s.
- Cache aggressively; use `If-None-Match`/`If-Modified-Since`; never re-fetch an unchanged page.
- Respect `robots.txt`: do not fetch `/works?page=N`, `/works/search?`, `/autocomplete/`, or crawl `/downloads/`.
- Identify the client honestly: `AO3Reader/<version> (+project URL or contact)`, not a Chrome UA. This may *increase* blocking under current settings; that is an acceptable cost of not impersonating a browser, and it gives AO3 a way to contact/allow the client rather than guessing.
- Detect `cf-mitigated: challenge` and show a clear “AO3 is queueing/verifying traffic; open in your browser or try later” message instead of a generic HTTP error [S14].

**Limits:** during the current waiting-room regime this may still always fail. It is a correctness/ethics baseline, not a fix.

### Option E — Ask AO3/OTW, once, with details

AO3 Support handles technical support and reports about unofficial apps [S5]. A single, non-demanding message describing: the app, its read-only nature, no ads/paywall, request volume, honest UA, contact URL, and the observed `403`/`429` — asking whether they have guidance for e-reader clients — is legitimate. Do **not** ask for a rate-limit exemption or an allowlist as an entitlement; AO3 says it does not make exceptions [S3]. Realistically the answer may be “use downloads/RSS”.

### Option F — Wait out the recovery

Check the OTW status page rather than probing AO3. The 2026-11-19 update still describes intentional delays; the waiting room may be removed when traffic normalises. Any client should treat `403`/`429` as “come back later”, not as a bug to engineer around [S7].

---

## 7. Concrete changes this analysis supports

1. **Remove the 3-second retry on `403`.** A Cloudflare challenge is not transient for a non-JS client. Keep the cooldown, but make the first `403` terminal for that action.
2. **Replace the Chrome UA with an honest app UA** containing name/version and a contact/project URL. Do not add headers solely to mimic Chrome.
3. **Surface the distinction** between “AO3 content problem” (`404`, restricted) and “edge/queue problem” (`403`, `429`, `cf-mitigated`, `Retry-After`) in user-facing text, with a “Open in browser / download manually” action.
4. **Default to offline/local.** Make live browse opt-in; do not auto-refresh listings; do not add pagination prefetch.
5. **Do not add a Cloudflare cookie jar.** Keep `view_adult=true` only if it is actually needed; it is not a bot cookie.
6. **Document the manual download/import path prominently** in the README, including that during the incident only HTML downloads are available.
7. **If RSS is added, label its limits** (canonical tags, new works only, no search, no restricted works) and fetch it only on user request.

None of these require AO3 to change anything, and none attempt to defeat the edge.

---

## 8. Open questions / what would need a real AO3 response

- Which producer sent the `429`: waiting room, Cloudflare rate limit, or AO3 Rack::Attack? Distinguishable from `cf-ray`, `cf-mitigated`, `Retry-After`, and body, but only by making a request — deliberately not done here.
- Is `robots.txt` on `download.archiveofourown.org` the same as the main host? Not checked.
- Does AO3's production Rack::Attack use the public default 300/300 s, or a different deployed value? The public config says 300/300; production may override [S17].
- Will the waiting room be removed, and will the `403`/`429` pattern persist afterwards? The status page is the authority.
- Would AO3 consider an honest, user-initiated e-reader client acceptable at all, or prefer downloads/RSS only? Only AO3 can answer; the ToS FAQ leaves room but reserves the right to say no [S1].

---

## 9. Sources

Canonical URLs are given for citation. AO3 pages were read via Wayback snapshots, not fetched from AO3.

| ID | Source | URL |
|---|---|---|
| S1 | AO3 Terms of Service FAQ — bots/scraping | https://archiveofourown.org/tos_faq (snapshot: https://web.archive.org/web/2026/https://archiveofourown.org/tos_faq) |
| S2 | AO3 Terms of Service (I.F, effective 2024-11-19) | https://archiveofourown.org/tos (snapshot: https://web.archive.org/web/2026/https://archiveofourown.org/tos) |
| S3 | OTW — “AI and Data Scraping on the Archive” (2023-05-13) | https://www.transformativeworks.org/ai-and-data-scraping-on-the-archive/ (snapshot: https://web.archive.org/web/20261016203512/https://www.transformativeworks.org/ai-and-data-scraping-on-the-archive/) |
| S4 | AO3 About the Archive FAQ — no API / e-reader downloads | https://archiveofourown.org/faq/about-the-archive?language_id=en |
| S5 | OTW — “Why AO3 Doesn't Have an Official App” (2026-07-24) | https://www.transformativeworks.org/why-ao3-doesnt-have-an-official-app |
| S6 | AO3 Downloading Fanworks FAQ — external scripts | https://archiveofourown.org/faq/downloading-fanworks?language_id=en |
| S7 | OTW status — “AO3 Down for Maintenance” (updates 2026-11-15 … 2026-11-19) | https://otwstatus.org/incidents/g12jnxck9g6h |
| S8 | AO3 robots.txt | https://archiveofourown.org/robots.txt (snapshot: https://web.archive.org/web/20240101000000id_/https://archiveofourown.org/robots.txt); 2026 secondary index: https://tools.yukai.uk/ai-crawler-index/site/archiveofourown.org |
| S9 | AO3 Accessing Fanworks FAQ — JavaScript / compatibility | https://archiveofourown.org/faq/accessing-fanworks?language_id=en |
| S10 | Cloudflare — Clearance / `cf_clearance` | https://developers.cloudflare.com/cloudflare-challenges/concepts/clearance/ |
| S11 | Cloudflare — Bot scores (headers, session, browser signals; `__cf_bm`) | https://developers.cloudflare.com/bots/concepts/bot-score/ |
| S12 | Cloudflare — Waiting Room cookies (`__cfwaitingroom` mandatory) | https://developers.cloudflare.com/waiting-room/reference/waiting-room-cookie/ |
| S13 | Cloudflare — Browser Integrity Check | https://developers.cloudflare.com/waf/tools/browser-integrity-check/ |
| S14 | Cloudflare — Detect a Challenge Page (`cf-mitigated: challenge`) | https://developers.cloudflare.com/cloudflare-challenges/challenge-types/challenge-pages/detect-response/ |
| S15 | Cloudflare — Waiting Room JSON/non-browser traffic; no cookie = new user/end of queue | https://developers.cloudflare.com/waiting-room/how-to/json-response/ |
| S16 | Cloudflare — Error 429 | https://developers.cloudflare.com/support/troubleshooting/http-status-codes/4xx-client-error/error-429/ |
| S17 | OTW Archive source — `rack_attack.rb` and `config.yml` defaults (300 req / 300 s per IP, Retry-After) | https://github.com/otwcode/otwarchive/blob/master/config/initializers/rack_attack.rb ; https://github.com/otwcode/otwarchive/blob/master/config/config.yml |
| S18 | AO3 Subscriptions and Feeds FAQ — tag RSS/Atom | https://archiveofourown.org/faq/subscriptions-and-feeds?language_id=en |
| S19 | Cloudflare — Error 403 causes (WAF, Security Level, BIC) | https://developers.cloudflare.com/support/troubleshooting/http-status-codes/4xx-client-error/error-403/ |
| S20 | Cloudflare — Challenges troubleshooting (IP reputation, bot detection, BIC) | https://developers.cloudflare.com/cloudflare-challenges/troubleshooting/ |
| S21 | Cloudflare — Waiting Room configuration (`queueing_status_code`, JSON response) | https://developers.cloudflare.com/waiting-room/reference/configuration-settings/ |

**Secondary press confirmation** (not policy, but corroborates the waiting room): File 770, “Archive of Our Own Restores Service, With Some Limitations,” 2026-11-15 — https://file770.com/archive-of-our-own-restores-service-with-some-limitations/ ; The Mary Sue, 2026-11-16 — https://www.themarysue.com/after-17-days-in-the-dark-ao3-is-finally-back-online-with-limited-features-and-fandoms-are-more-than-ready-to-start-reading-again .
