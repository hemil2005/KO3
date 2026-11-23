# Product

<!-- impeccable:product-schema 1 -->

## Platform

native-eink

## Users

AO3 readers who read on a Kindle. They are already holding the device they
read books on and do not want to fetch a laptop, open a browser, or fight
AO3's layout on a slow e-ink screen. The maintainer is the first user; the
plugin is published on GitHub Releases and advertised to Kindle AO3 readers,
so a wider audience is hoped for rather than assumed. Support continues while
there is demand.

## Product Purpose

Read Archive of Our Own works on the e-reader, natively. Browsing, searching
and reading a work should take a few taps on a touchscreen, survive a weak or
absent connection, and leave the reader in KOReader's own reading experience.
Success is a work open in crengine, from a cold start, without a browser and
without losing a previously saved copy.

## Positioning

AO3 is a data source, never a rendered site. The plugin lives inside
KOReader, parses AO3's HTML and rebuilds it with stock KOReader widgets, then
hands AO3's own work download to crengine. No WebView, no embedded browser,
no third-party service, no account. The offline fandom index (77,535 fandoms
across 10 media categories, shipped with the plugin) means browsing still
works when AO3 refuses the device.

## Operating Context

- Target: Kindle e-readers running KOReader. The reference renders are
  600×800; colour Kindles are supported and screens must not assume
  grayscale, but black-and-white devices remain the majority and every screen
  has to stay legible there.
- E-ink and touch: slow refresh, no keyboard, no hover, one hand. KOReader's
  own font scaling, DPI and page-turn gestures apply.
- Installation: unzip `ao3.koplugin` into `koreader/plugins/`, then update in
  place from the plugin's own **Update plugin** screen (GitHub Releases,
  SHA-256 verified, previous version kept as `ao3.koplugin.bak`).
- Network: indirect HTTPS through KOReader's LuaSocket/LuaSec client. AO3 can
  refuse the device with 403/429 from Cloudflare; the offline index and saved
  works are the fallback, and the README documents the manual
  browser-download path.
- Development loop: KOReader emulator for visual proof, offline `busted`
  specs against captured fixtures, captures saved under `screenshots/`.

## Capabilities and Constraints

Confirmed surfaces: landing page; latest works and search; the shipped fandom
index (media category → letter → bounded 100-entry windows, with offline
"Find in this letter"); tag listings; work cards (bold title, author, up to
three summary lines); work details (title, author, fandom, Read/Refresh,
four-number strip, metadata table, folded Summary and Tags); author page with
Dashboard / Works / Series / Bookmarks tabs; Downloads; open by URL or work
ID; self-update and restore-previous.

Hard constraints:

- Lua 5.1 inside KOReader; stock KOReader widgets only. No WebView, no
  embedded browser, no hand-drawn bitmaps for controls.
- Read-only and public: no login, no session, no kudos, comments, bookmarks or
  subscriptions; no images; adult-gated works may be refused.
- One page per tap, 20 works per page, no infinite scroll, no crawling;
  `Retry-After` honoured; a download is validated before it replaces a cached
  copy.
- Simple search only: one query box. AO3's filter matrix (rating, warnings,
  completion, word count, sort) is not exposed.
- The fandom list is a point-in-time snapshot; renamed tags 404 until the
  snapshot is regenerated. "Find a tag…" resolves current tags by name.
- Untested on physical Kindle hardware; parsers and UI are verified in the
  emulator.

Scope is a current stage, not a permanent vow: login, filters or comments may
be considered later, but only if the one-screen, low-tap model can carry them.
Do not widen scope as a side effect of a design task; confirm it first.

## Brand Commitments

- Name: **AO3 browser**, full name "AO3 browser", description "Browse, search
  and read works from Archive of Our Own."
- Unofficial. AO3's name and logo are OTW trademarks; `assets/ao3-logo.png` is
  copied byte-for-byte from OTW's repository, `assets/ao3-logo.svg` is a trace
  of it. Attribution and the disclaimer stay visible in the README.
- Voice: plain, specific, honest about limits. No invented users, benchmarks,
  affiliations or roadmap promises.
- Identity on screen: the AO3 mark and name are the only header identity; the
  native title bar is left empty.

## Evidence on Hand

- `README.md` — the user-facing source of truth: capabilities, verification
  record, limits, troubleshooting.
- `AGENTS.md` — working rules for UI, downloaded works and network behaviour.
- `screenshots/` — emulator captures of every current screen (01–19), used as
  visual-regression evidence.
- `ao3.koplugin/spec/` — 130 offline tests plus real AO3 markup captured on
  2026-11-23 (`fixtures/`, including author dashboard/works/series/bookmarks).
- `research/ao3-access-policy.md`, `research/koreader-network-options.md`,
  `research/kindle-crash-candidates.md` — access, networking and
  old-build-compatibility findings.

Absences future work must not paper over: no physical-Kindle verification, no
user counts or testimonials, no performance benchmarks, no official AO3 API
or affiliation.

## Product Principles

1. Reading first. The path from open to reading a chapter is the shortest one
   the screen allows; secondary actions stay secondary.
2. Native or nothing. Stock KOReader widgets, native fonts and scaling; a
   screen that cannot be built natively is not built.
3. Polite by default. One request per tap, honour `Retry-After`, never retry
   a refusal, never crawl or probe, keep working offline when AO3 says no.
4. Never lose a book. Cached works and the installed plugin are only replaced
   after the new copy validates; rollback stays available.
5. Legible before decorative. Bold titles, one left edge, generous touch
   targets, contrast that survives grayscale and colour e-ink alike.
6. Say what happened. Errors name the cause and the next step; documentation
   separates verified behaviour from untested claims.

## Accessibility & Inclusion

- Touch-only, small-screen use: large tap targets, full-width rows, no
  keyboard-shortcut columns (the emulator reports a keyboard the target device
  does not have).
- Text uses KOReader font faces with `Screen:scaleBySize`, so the reader's own
  font size and DPI settings carry into every plugin screen.
- Colour Kindles: colour may be used where it carries meaning, but every
  screen must stay legible in grayscale and at low contrast.
- All user-facing strings go through `gettext`; no hard-coded English in new
  UI where the surrounding code translates.
