# Project conventions

Working rules for agents changing this plugin.

## UI

- Native KOReader widgets only: no WebView, no embedded browser, no hand-drawn
  bitmaps for controls.
- **Hide menu shortcut boxes by default** on touchscreen devices
  (`is_enable_shortcut = false`). This includes KOReader-owned menus that the
  plugin customises, such as the table of contents. Do not rely on
  `Device:hasKeyboard()`: the emulator reports a keyboard and draws the
  Q/W/E shortcut column even though the target device is a touchscreen.
- Work cards: bold title, author, up to three summary lines, one separator per
  card, no per-row shortcut boxes.
- The AO3 entry sits directly on the Tools tab, at the bottom
  (`sorting_hint = "tools"`), not nested under More tools.
- After any user-visible change, demonstrate it in the local Kindle emulator
  and save a capture under `screenshots/`. Tests alone are not enough.

## Downloaded works

- The table of contents is the work's chapters only: drop AO3's hidden
  "Preface" metadata heading and the work-title wrapper, then flatten. A flat
  TOC opens fully expanded. Show three fewer rows per page than KOReader's
  default so entries have some breathing room.
- Opening a work from the plugin must return to the plugin screen (Back key,
  reader menu and end-of-document dialog), not to KOReader's file manager.

## Account

- Sign-in is three requests: `GET /token_dispenser.json`, the single
  `POST /users/login`, then one confirmation load. Never post credentials
  twice, and never verify a session on startup.
- Use the Firefox header set (`UA` in `main.lua`) for AO3 requests. With the
  old Chrome UA, `/token_dispenser.json` returned `403 cf-mitigated: challenge`
  on the same network; the Firefox set returned `200`.
- Store only AO3's `_otwarchive_session`, `remember_user_token` and the
  `user_credentials` marker, never the password and never Cloudflare cookies.
  AO3 redirects a logged-in request without `user_credentials` to
  `/lost_cookie`; send `user_credentials=1` for saved sessions that predate
  it. Keep the cookie jar scoped to `archiveofourown.org` and
  `download.archiveofourown.org`.
- Follow redirects manually so the session cookie is recomputed per host;
  refuse an HTTPS → HTTP downgrade. `LuaSocket`'s automatic redirect copies
  the original `Cookie` header to the new URL.
- Treat a redirect as success only after loading the destination and seeing
  AO3's logged-in greeting. A failed sign-in can still set an anonymous
  session cookie.
- AO3 rotates the session cookie during sign-in. Ignore cookies whose
  `max-age` is 0 or whose expiry is 1970; they must not overwrite the live
  session, whichever order the headers arrive in.
- Log out removes both `settings/ao3.lua` and its `.old` backup.
- Work actions (kudos, bookmark, subscribe, Marked for Later) are the website's
  own form posts, only on tap. Read state, the bookmark pseud/id and the
  subscription id from one work-page load. Get the CSRF token from
  `/token_dispenser.json` and cache it until the session cookie changes: a
  work page's embedded token is form-scoped and was rejected for kudos in a
  live test. Never retry a form post: a retried 403 would leave duplicate
  kudos or bookmarks.
- Opening a signed-in work page reads its action state once, silently, so the
  four buttons start with accurate checkmarks. Failures are not shown; a tap
  reports its own error.

## Updates

- Releases come from `.github/workflows/release.yml`: a versioned zip plus a
  manifest with the version and SHA-256. `_meta.lua` must match the tag.
- `updater.lua` only swaps a new tree in after the checksum and the archive's
  own `_meta.lua` version both pass; the running code is never modified.
  Keep the previous tree as `ao3.koplugin.bak` for **Restore previous
  version**.
- `Updater.currentVersion` reads `_meta.lua`; do not execute plugin code to
  find the version. Keep the manifest URLs on HTTPS and reject path traversal
  and absolute paths in archive entries.

## Network

- Do not send requests to AO3 unless the user asks. No probing, no retries
  after a 429, no crawling.
- The Firefox header set avoids the `403 cf-mitigated: challenge` observed on
  2026-11-23. It is not a rate-limit exemption: a genuine `429` still applies,
  and `Retry-After` is still honoured.
- One page per tap; honour `Retry-After`; validate a download before replacing
  a cached copy.
