# KO3 — an AO3 browser for KOReader

A deliberately small browser for [Archive of Our Own](https://archiveofourown.org)
that runs inside KOReader on Kindle (and other e-readers).

It does **not** embed a WebView and never renders AO3's site. AO3 is only a
data source: pages are fetched, parsed, and rebuilt as a native KOReader
`Menu`; a work's HTML download is handed to crengine when you tap **Read**.

- Optional AO3 sign-in for your own bookmarks, marked-for-later, history and
  subscriptions
- Optional kudos, bookmark, subscribe and Marked for Later from a work page
- No images
- No comments, no work posting, no third-party service
- One page fetched per tap; only opened works are saved
- Self-updating from GitHub Releases (checksum-verified, with rollback)

## Screenshots

Taken from the KOReader emulator (600×800, grayscale). The work-list and
author-tab shots render real AO3 markup captured offline; the other
browse/detail shots use the plugin and embedded fandom data, with the
details captured from a live work.

| | |
|---|---|
| ![KO3 in the Tools menu](screenshots/01-menu.png) | ![Home](screenshots/02-home.png) |
| ![Fandoms by media](screenshots/03-fandoms.png) | ![Fandom index](screenshots/04-letters.png) |
| ![A letter's fandoms](screenshots/05-fandom-list.png) | ![Works with symbols, tags and numbers](screenshots/06-works.png) |
| ![Work details](screenshots/07-work-details.png) | ![Reading a work](screenshots/08-reading.png) |
| ![Author entry](screenshots/09-author-dialog.png) | ![Author dashboard](screenshots/10-author-dashboard.png) |
| ![Author series](screenshots/11-author-series.png) | ![Author bookmarks](screenshots/12-author-bookmarks.png) |
| ![Author works](screenshots/13-author-works.png) | ![Author works, later page](screenshots/38-author-works-page2.png) |
| ![An author with nothing on a shelf](screenshots/39-author-empty.png) | ![Update row](screenshots/29-update-home.png) |
| ![Update prompt](screenshots/30-update-dialog.png) | ![Update changelog](screenshots/37-update-changelog.png) |
| ![Report row](screenshots/31-report-home.png) | ![Report editor](screenshots/32-report-editor.png) |
| ![Log consent](screenshots/33-report-consent.png) | ![Report sent](screenshots/36-report-sent.png) |
| ![Work summary expanded](screenshots/18-work-summary.png) | ![Work tags expanded](screenshots/19-work-tags.png) |
| ![Tag box open in the list](screenshots/40-work-list-tags.png) | ![Settings](screenshots/41-settings.png) |
| ![Back from a work returns to the listing's page](screenshots/42-listing-page-restored.png) | ![Every fandom containing "cyber" in a letter](screenshots/43-fandom-search.png) |
| ![The older, simpler work card](screenshots/44-legacy-work-list.png) | ![Sign in on the landing page](screenshots/24-home-signed-out.png) |
| ![Account on the landing page](screenshots/25-home-signed-in.png) | ![Work account actions](screenshots/26-work-account-actions.png) |
| ![Work actions while signed out](screenshots/27-work-actions-signed-out.png) | ![Account page](screenshots/28-account.png) |
| ![Chapter-only TOC](screenshots/14-reader-toc.png) | ![Back to AO3 in menu](screenshots/15-reader-back-to-ao3.png) |
| ![Back to AO3 at end](screenshots/16-end-dialog-back.png) | ![Back on the AO3 screen](screenshots/17-back-on-ao3-screen.png) |
| ![KO3 on the first Tools page](screenshots/34-tools-menu.png) | |

## Install

The quickest way is the release zip:

1. Download the `ao3.koplugin-<version>.zip` asset from
   [the latest release](https://github.com/hemil2005/KO3/releases/latest).
2. Unzip it into `koreader/plugins/` on the device (the archive already
   contains the `ao3.koplugin` folder).
3. Restart KOReader.
4. Open **Tools → KO3**.

Or copy the `ao3.koplugin` folder yourself. Either way, the layout should be:

```
koreader/
  plugins/
    ao3.koplugin/
      _meta.lua
      main.lua
      account.lua
      accountpage.lua
      authorpage.lua
      homepage.lua
      settingspage.lua
      preferences.lua
      workpage.lua
      uikit.lua
      updater.lua
      bugreport.lua
      assets/ao3-logo.png
      assets/ao3-logo.svg
      assets/icons/*.svg
      fandompages.lua
      data/fandoms/index.lua
      data/fandoms/<category>/<letter>.tsv.z
```

Once installed, later versions arrive through **Update KO3** (below), so
the zip only has to be copied once.

## Use

One menu entry opens the whole app. The landing page leads with the AO3 mark
and name (the native title bar is left empty, so the wordmark is the only
identity), with a settings gear at the right edge of that line, then one solid
**Search works** bar. Everything else is an icon
tile grouped under **Browse**, **Library** and **Plugin**. Each tile keeps its
name beside the icon, with a one-line hint underneath:

| Tile or bar | What it does |
|---|---|
| **Search works** (solid bar) | Work title, author or keyword |
| **Latest works** | Newest works across the archive (`/works`) |
| **Fandoms** | Categorized fandom index, shipped with the plugin |
| **Author** | An author's name or profile URL — their works list |
| **Tag** | A tag name, or paste a full `/tags/.../works` URL |
| **Account** | Sign in to AO3, then your bookmarks, marked-for-later, history and subscriptions |
| **Downloads** | Works already saved on this device |
| **Open work** | Paste `https://archiveofourown.org/works/1234567` or just `1234567` |
| **Update KO3** | Check GitHub Releases for a newer version |
| **Report a bug** | Write what happened; optionally attach a diagnostic log |

Fandoms are browsed media category → letter → fandom, the same way AO3's
own index is organised. Choosing a category opens the whole alphabet as one
index above the list: three shelves of nine (A–I, J–R, S–Z and `#`), with the
open letter inverted. The index stays on screen while you page through a
letter, so changing letters never means paging back. A fandom's name may run
to two lines and is then elided; its work count keeps the right-hand column.
Large letters load in local windows of up to 100 fandoms. **Find in this
letter…**, marked with a magnifier, lists every fandom in the letter whose name
contains the term — any part of a name matches, in any case, and the list is
navigable with the same paging rows. A search with no matches says so and leaves
the reader where they were; a search that finds something sits on top of the
letter page, so Back returns to the page being browsed. Tapping a fandom
fetches only its 20-work page. On the AO3 screens, the letter shortcut boxes
are hidden so the text gets the full touchscreen width.

Each work is one selectable card. Beside the title sits AO3's own required-tag
strip as a 2×2 grid of ink symbols: the rating letter (G/T/M/E), a warning
mark, the category's symbol, and a check for a finished work. The bold title
shares its line with the byline ("by …") when both fit; a title that needs the
whole width keeps its line and the byline drops beneath it. Fandoms and
relationships share one grey line when they fit, and take a line each when
they do not. Then come the tag box, up to three lines of summary, and the
record's numbers — words, chapters and the last update. The tag box stays to
one line, ending in "+N more"; tapping it opens that work's tags in place (up
to six lines) without opening the work. The work's details page still carries
the complete tag list.

**Settings** (the gear beside the AO3 name) has two options. **Expanded tags:**
**On** or **Off** — Off is the default and keeps every tag box to one line; On
starts each listing with the boxes open. **Work cards:** **Modern** or
**Legacy** — Modern is the default, with the AO3 symbols, fandom and
relationships, the tag box and the word/chapter numbers; Legacy is the simpler
card the plugin started with, a bold title, the author and the first three
lines of the summary. Both choices are stored in `settings/ao3_prefs.lua`,
separately from the AO3 session, so Log out does not reset them.

Tap a result to drill in; tap a work for its details. The work screen leads
with the title, author and fandom, then **Read** (the solid bar, which
fetches the work and opens it in the KOReader reader) and **Refresh** (the
outlined one), a four-number strip (words, chapters, kudos, hits) and a small
table for rating, warnings, category, status and date. **Summary** and
**Tags** stay folded until tapped; a summary too long for one page is elided
and opens in full from **Read full summary**. Each author's name opens the
author page (co-authors each get a row; Anonymous stays plain text).

The author page has four tabs in one pill-shaped bar — a rounded strip split
by three hairlines into equal options — and that bar is the page's whole
navigation. Every tab opens on the same masthead — the author's
name, with AO3's "Author on AO3" qualifier in grey beneath it — and a quiet
count line names the shelf above the records:

| Tab | What it shows |
|---|---|
| **Dashboard** (default) | The fandoms the author has written in, with work counts. Tapping one opens that author's works in that fandom (AO3's own author-scoped fandom links). |
| **Works** | All of the author's works as the same card listing. |
| **Series** | The author's series, with work counts, as index rows; tapping one opens the series' works. |
| **Bookmarks** | Works (and series) the author has bookmarked, as cards. |

Each tab is fetched at most once per author visit, so switching back and
forth does not re-request AO3. Back (the footer
arrow, the hardware Back key, the X, or a downward swipe) goes one level up
instead of dropping you into the file manager.

Signing in is optional and only unlocks the personal lists. **Account → Sign
in** takes an AO3 username (or email) and password. The password is posted
once, directly to AO3, and is never written to disk. What is kept is AO3's own
session cookie (`_otwarchive_session`, plus `remember_user_token` when AO3 sets
it) in `settings/ao3.lua`; **Log out** removes that file and its backup.
Cloudflare cookies are never stored or replayed. Sign-in is three ordinary
requests: fetch AO3's JSON CSRF token, submit the form, and load one page to
confirm the logged-in greeting. A redirect alone is not treated as success,
because the anonymous form cookie would otherwise look like a session.

Two details matter for AO3's edge. The login page (`/users/login`) is
challenged for this client, so the token comes from
`/token_dispenser.json` instead. The request also uses the Firefox header set
that AO3 accepts; a specific Chrome UA is refused with `cf-mitigated:
challenge` on the same request. AO3 rotates the session cookie during
sign-in, sometimes alongside a deletion cookie, so an expired cookie is
ignored rather than allowed to overwrite the live session.

After sign-in, **Account** lists:

| Row | Opens |
|---|---|
| **Bookmarks** | Works and series you bookmarked |
| **Marked for Later** | Your reading queue |
| **History** | Works you opened |
| **Subscriptions** | Works, series and authors you follow |
| **Works by you** | Your own author page, with the usual tabs |
| **Log out** | Clears the session cookie |

Each row fetches one page on tap and uses the same work cards as the rest of
the app. If AO3 stops accepting the session, the plugin says so, clears the
cookie and returns Home to **Sign in** instead of showing an empty list.

A signed-in work page can also leave kudos, bookmark the work, subscribe to
it, and add it to Marked for Later. These are the website's own form posts,
sent only when you tap them; nothing is posted on startup or in the background.
Loading the work page once supplies the current state (bookmarked, subscribed,
on the read-later list) and the pseud or subscription id needed to undo the
action. The form token comes from `/token_dispenser.json` and is cached until
the session cookie changes; the tokens embedded in a work page belong to their
forms, so they are not reused for a different action. A form post is never
retried, so a 403 cannot leave two kudos or two bookmarks behind.

The first read downloads the whole work (usually 200 KB–1 MB); after that the
cached copy opens instantly, offline. **Refresh** downloads and validates the
latest version before replacing the saved copy, so a failed request leaves
the offline book available.

Inside the reader, a work opened from AO3 has three ways back to the screen
you left, instead of KOReader's file manager:

- **Back to AO3** at the bottom of the reader menu's Navigation tab, on its
  first page.
- The Back key / Back gesture (its usual "go to file browser" exit is
  redirected for AO3 works).
- **Back to AO3** in the end-of-the-work dialog, alongside the standard
  choices. The stock **File browser** button still opens the file manager.

The table of contents is the work's chapters only. AO3's download file adds
hidden "Preface" and title headings for Calibre, which crengine turned into
two collapsed top-level entries. Those are filtered out and the chapter list
is flattened, so the index opens fully expanded and contains no metadata
heading.

### Updating KO3

**No computer is needed after the first install.** Open
**Tools → KO3 → Update KO3**:

1. It asks GitHub for the latest release and shows the current version, the
   new version and the release notes (`manifest.json` is the fallback).
2. **Update** downloads the versioned zip, verifies its SHA-256, unpacks it
   next to the installed copy, and checks that the archive really contains
   the plugin and the version it claims.
3. It swaps the new tree in only after all of that passes, then offers to
   restart KOReader. The running code is never modified mid-flight.

The previous version is kept as `ao3.koplugin.bak`; **Restore previous
version** appears on the home screen after an update and swaps it back.
Updates are ~2.7 MB and come straight from `github.com`, so no Storefront
or other plugin is required.

GitHub serves release assets from its asset CDN
(`release-assets.githubusercontent.com`), a different host from the one that
answers the update check. Some Kindle networks reach the API but not that
host; the download then stalls until it times out. KO3 follows the redirect
itself and retries a stalled transfer from the bytes already saved. If the
CDN still cannot be reached, it falls back to the tag's source archive on
`codeload.github.com`, which carries the same `ao3.koplugin` tree; the staged
`_meta.lua` version is checked before installing.

Because the fallback lives in the new code, a device whose current updater
cannot reach the asset CDN needs this version copied once by hand (the zip on
the release page is on `github.com`). Later updates then work in place.

### Reporting a bug

**Tools → KO3 → Report a bug** opens a text field. After you describe what
happened, a consent dialog asks whether to attach the diagnostic log and
states that the report and log are sent to the project's issue tracker, and
that the log is used only to find the cause. Choosing **Without log** sends
the description alone.

**Attach log is the last step.** The report is POSTed to the KO3 relay
(`relay/worker.js`, a small Cloudflare Worker), which files the issue with a
fine-grained GitHub token that never ships in the plugin. The relay accepts
10 reports per IP per day. No GitHub account is needed.

If the relay cannot be reached, the report is still saved on the device as
`koreader/ao3/reports/bug-<timestamp>/report.md` plus `log.txt`, ready to
attach to [a new issue](https://github.com/hemil2005/KO3/issues/new).

What the log contains:

- plugin version, KOReader revision, device model, screen size and time;
- each request's host and path with its HTTP status, download outcomes and
  error text.

What it never contains: your AO3 password (the plugin stores none), cookies,
search text, work titles or work text. Query strings and fragments are
stripped before anything is written.

The log itself lives at `koreader/ao3/logs/ao3.log`, is capped at 256 KB
(one rotation to `ao3.log.1`) and is only read when you create a report.

`settings/ao3_report_token` (a fine-grained token with **Issues: write**)
bypasses the relay for the maintainer's device. The relay's deployment and
token rotation are documented in `relay/README.md`.

## How it works

```
Browse (offline, data ships with the plugin):
  data/fandoms/index.lua        10 media categories, counts, letters
  data/fandoms/<n>/<L>.tsv.z    one zlib file per category per letter
    77,535 fandoms, 2.6 MB on disk; only the opened letter is decompressed,
    and at most 100 entries become menu rows at once

Listing:
  GET https://archiveofourown.org/works                 (latest works)
  GET https://archiveofourown.org/works/search?work_search[query]=...
  GET https://archiveofourown.org/tags/<tag>/works?page=N
    -> parse <li class="work blurb group"> into 20 selectable work cards

Author page (four tabs):
  GET /users/<name>?expand_fandoms=true       Dashboard: fandoms + counts
  GET /users/<name>/works                     Works
  GET /users/<name>/series                    Series
  GET /users/<name>/bookmarks                 Bookmarks
  GET /users/<name>/works?fandom_id=<id>      one fandom, author-scoped

Account (only after Sign in):
  GET  /token_dispenser.json                  JSON CSRF token
  POST /users/login                           user[login], user[password]
  GET  /users/<name>/bookmarks                Bookmarks
  GET  /users/<name>/marked_for_later         Marked for Later
  GET  /users/<name>/readings                 History
  GET  /users/<name>/subscriptions            Subscriptions

Work actions (only after Sign in; one form post per tap):
  GET  /works/<id>                            state, pseud, bookmark/subscription ids
  POST /kudos.js                              kudo[commentable_id]
  POST /works/<id>/bookmarks                  bookmark[pseud_id] + optional notes/tags
  POST /bookmarks/<bookmark_id>               _method=delete
  POST /users/<name>/subscriptions.json       subscription[subscribable_id]
  POST /users/<name>/subscriptions/<id>.json  _method=delete
  POST /works/<id>/mark_for_later             _method=patch
  POST /works/<id>/mark_as_read               _method=patch

Reading:
  GET https://download.archiveofourown.org/downloads/<work_id>/work.html
    -> AO3's own HTML download, saved and opened by crengine

Bug reports (only on tap, after consent):
  POST https://ko3-reports.ko3-reports.workers.dev/report
    -> relay files a GitHub issue with a fine-grained token
```

The fandom snapshot is generated from AO3 with `tools/build_fandoms.py`:

```sh
# Save https://archiveofourown.org/media as 00_media.html, then each
# /media/<category>/fandoms page as 01.html … 10.html in one directory:
python3 tools/build_fandoms.py fandom_pages ao3.koplugin/data/fandoms
```

"Uncategorized Fandoms" is skipped by default: it is ~80,000 unwrangled tags
that would double the snapshot size (`--include-uncategorized` keeps it).

The work file is stored as:

```
koreader/ao3/<work title> [<work id>].html
```

The ID suffix is what the cache lookup uses; the title is there so the file
is readable in the file manager too. Delete the file to force a re-download.

## What was verified

Tested in the KOReader emulator with a native HTTP client (no browser):

- The embedded snapshot: 77,535 fandoms across 10 media categories,
  browsable offline as category → letter → bounded 100-entry windows.
- A live fandom listing (`/tags/Harry Potter .../works`) returned a full
  page with the count and working page navigation.
- Work lists render one selectable card per work: AO3's rating, warning,
  category and completion symbols in a 2×2 ink grid; the bold title sharing
  its line with the byline; fandoms and relationships sharing a line when they
  fit; a one-line tag box that opens in place on a tap; the blurb clamped to
  three lines; and words, chapters and the last update. Cards are measured
  from their content, so an opened tag box moves the records below rather than
  clipping them. Three works fit on a 600×800 page with the tags folded.
  Captured in `screenshots/06` and `40`.
- With **Work cards: Legacy**, the same lists render the 0.x card instead: a
  bold title, the author's plain name and a three-line summary, with no
  symbols, classifications, tags or numbers. They are measured and paged at
  their own, shorter height, so a page of them neither clips the last card nor
  leaves an empty band. Captured in `screenshots/44`.
- Settings has two options, each a label and its value — **Expanded tags:** On
  or Off and **Work cards:** Modern or Legacy — stored in
  `settings/ao3_prefs.lua`, separately from the AO3 session. A tap flips the
  choice, the row redraws with its new value, and every work list already on
  the back stack is restyled from its own rows, so returning to it shows the
  new design without fetching the page again. Captured in `screenshots/41`.
- The work screen is one page, not a key/value list: title/author/fandom,
  Read and Refresh, a four-number strip, an aligned metadata table, four
  account actions (Kudos, Bookmark, Subscribe, Mark for later), and folded
  Summary and Tags sections. A summary longer than a page is elided and opens
  in full; expanding lands on the text it revealed. Captured in
  `screenshots/07`, `18`–`19` and `26`–`27`.
- The landing page: AO3 logo lockup with the settings gear at the right edge
  of the masthead line, one solid Search bar, then Browse, Account, Library
  and Plugin groups of icon tiles (clock, grid, person, tag, login, download,
  file, refresh). The Account tile is the login symbol while signed out and
  becomes the reader's own name with the user symbol once signed in. The logo
  is OTW's official PNG plus a traced SVG; the tile symbols and the gear are
  authored 24x24 SVGs, so no build falls back to a missing-icon glyph.
  Captured in `screenshots/02`, `24` and `25`.
- The account page is a contents page for AO3's four lists (Bookmarks,
  Marked for later, History, Subscriptions), the reader's author page, and
  an outlined Log out with the note that saved works stay on the device.
  Captured in `screenshots/28`. Sign-in, the four lists and the work actions
  are connected to real AO3 requests; the page only fetches a list when its
  row is tapped.
- The author page (Dashboard / Works / Series / Bookmarks) is built from the
  exact live AO3 markup captured on 2026-11-23, including author-scoped
  fandom links, series stats, work bookmarks and series bookmarks. Every tab
  opens the same way: the title bar names the shelf (Fandoms for Dashboard),
  the author's name sits at display size with AO3's "Author on AO3" qualifier
  in grey beneath it, then one pill-shaped bar holding the four tabs, split by
  three hairline dividers, the current one carrying a checkmark. That bar is
  the whole navigation: no solid bar duplicates a tab, so nothing on the page
  moves when the shelf changes. A quiet count line names the shelf
  ("6 fandoms", "535 works"),
  fandom and series records are two-line index rows with their count on the
  first line, works are the usual summary card, and an empty shelf is a single
  grey sentence. A shelf longer than one page pages in place
  (`screenshots/10`–`13`, `38`–`39`).
- Opening a work downloaded 467 KB `work.html` and rendered it in crengine
  (1/427 pages), with the file saved under `koreader/ao3/`.
- Works opened from AO3 return to the plugin from the Back key, the reader
  menu and the end-of-work dialog. The TOC lists only the work's chapters and
  opens fully expanded.
- The account screens render in the emulator: the Account tile on the
  landing page signed out and signed in, the sign-in form with a masked
  password field, the signed-in Account page, the work actions, and the
  signed-out work page (`screenshots/24`–`25`, `27`–`28`). The action and
  account captures use a local demo session and make no AO3 request.
- The sign-in flow completed against live AO3 on 2026-11-23 and saved AO3's
  session and remember-me cookies to `settings/ao3.lua`; the saved data has no
  password field.
- A signed-in work page loaded successfully and the parser read its CSRF
  token, bookmark pseud and existing bookmark/subscription ids.
- All four actions were exercised against live AO3: a kudos returned `201`;
  a bookmark, a subscription and a Marked for Later entry were each created
  and then removed, and a fresh work-page read showed all three off again.
- After AO3 began redirecting logged-in requests without its
  `user_credentials` marker to `/lost_cookie`, a signed-in download and a
  bookmark/unbookmark round-trip were repeated live on 2026-11-23. The
  download completed, the bookmark was created and removed, and the final
  work-page state showed it off. The plugin now sends the marker with a saved
  session and reports a lost-cookie page as an ended session.
- The sign-in handshake is covered offline. A successful POST must be
  confirmed by AO3's logged-in greeting; an anonymous cookie plus a redirect
  back to the form is rejected. Cloudflare cookies are dropped, the session
  is not attached to other hosts, an HTTPS → HTTP redirect is refused, and a
  rotated session cookie cannot be replaced by an expired deletion cookie.
- The inline updater: manifest validation, version comparison, path-traversal
  rejection, SHA-256 verification, staged install, failed-rename rollback and
  restore-previous; the update row, prompt and full changelog render in the
  emulator (`screenshots/29`–`30`, `37`).
- Bug reports: query stripping, consent-gated log inclusion, report bundle
  writing, relay submission and token handling; the four screens render in
  the emulator (`screenshots/31`–`33`, `36`). The relay was tested live end
  to end from `bugreport.lua` (issues #1 and #2, then closed).
- The KO3 entry is directly on the Tools tab, fourth from the top so it stays
  on page 1 even when later rows move to page 2 (`screenshots/34`), not nested
  under More tools.
- The author tabs: each of the four is its own tap target inside the pill,
  and tapping **Bookmarks** opens the author's bookmarked works
  (`screenshots/12`). The title bar's close target is trimmed to the bar so it
  no longer covers the rightmost tab.
- The updater's network path: manual redirect following, a refused HTTPS → HTTP
  downgrade, a stalled transfer resumed with a Range request, the retry budget,
  and the codeload source archive installing a real 3.7 MB tree on the
  emulator when the asset CDN is unreachable.
- The offline `busted` suite: 296 tests passing across parser, navigation,
  bounded-index, rendered-card interaction (including the symbol grid, the tag
  fold and its tap path), reader preferences, old-build compatibility,
  author-page, work-page, account-screen, home-page, reader-hook, updater and
  bug-report tests, including 51 account tests across token parsing, the
  three-request sign-in, cookie scoping/rotation, session persistence/logout,
  subscription parsing and work actions. The work-action tests cover the
  website's form bodies, reading the work page's bookmarked/subscribed/
  read-later state, one-time token reuse, bookmark and subscription ids
  returned by AO3, already-done duplicates and the refusal to post twice.

**Current connectivity (checked 2026-11-23 14:20):** AO3's edge accepts the
Firefox header set used for sign-in. `/token_dispenser.json` returned `200`
with the JSON token; the same request with a Chrome UA returned `403
cf-mitigated: challenge`. The public homepage also returned `200` from cache
earlier. Sign-in is still done only when you tap it: no startup request, no
background verification, no retry after a challenge, and no replay of
Cloudflare's cookies. AO3 remains in degraded mode (HTML downloads only, some
features disabled), so each screen still loads one page per tap.

This is **not** a rate-limit exemption. The header set avoids the bot
challenge observed on this connection, but AO3's own limits still apply: a
real `429` is still possible, still honoured with `Retry-After`, and never
retried. If AO3 is queueing traffic, stop and try later rather than tapping
through it.

If AO3 works in your browser but not here, use AO3's **Download → HTML**
button in the browser, transfer the file to your device, and open it from
KOReader's file browser. AO3 currently reports that other download formats
are temporarily disabled. This manual path does not require the plugin's
network client.

The plugin deliberately does not replay Cloudflare's bot cookies: they are
bound to the client that earned them, and sending them back from LuaSocket is
what made the 403 stick for the plugin while `curl` could still fetch pages.

## Limits

- **Personal lists need a session.** Signing in enables bookmarks,
  marked-for-later, history and subscriptions. Restricted works are requested
  with the session cookie; if AO3 still returns a login or warning page, the
  download is rejected and any cached copy is kept.
- **Adult-gated works** may return the warning page instead of the work.
  The plugin sends `view_adult=true`, but it is not guaranteed.
- **No comments or posting.** The only writes are the four work actions a
  signed-in user taps: kudos, bookmark, subscribe and Marked for Later. There
  is no comment box and no work editing.
- **The session cookie is stored locally.** It lives in plain text in
  `settings/ao3.lua`, like KOReader's other service settings. The password is
  never written. **Log out** deletes the session and its backup file; delete
  that file by hand if you want to be certain. Reader preferences (the tag
  default) live in `settings/ao3_prefs.lua` and are kept by Log out.
- **The list's tag box opens to six lines.** A work with more tags than that
  shows the first six in the list; the work's details page carries the
  complete tag list.
- **No images.** AO3's HTML download references images remotely, and the
  plugin does not fetch them.
- **Snapshot, not live.** The fandom list is a point-in-time copy; tag names
  that were renamed on AO3 after the snapshot will 404 until it is
  regenerated. "Find a tag…" resolves any current tag by name.
- **Simple search.** One query box. AO3's filter matrix (rating, warnings,
  completion, word count, sort) is not exposed. Apps commonly have it; it
  would need a filter screen and is intentionally out of scope here.
- **No infinite scroll.** 20 works per page.
- **Untested on a physical Kindle.** Parsers, UI and rendering were tested
  in the emulator; a real-device pass is still recommended.

## Development and tests

The plugin has a KOReader `busted` suite in `ao3.koplugin/spec/`. It runs
offline against saved AO3 pages and mocked HTTP responses:

```sh
ln -s /path/to/ao3.koplugin plugins/ao3.koplugin
for spec in plugins/ao3.koplugin/spec/ao3*_spec.lua; do
  ln -s "../../$spec" "spec/unit/$(basename "$spec")"
done
./kodev test --busted=--pattern=ao3_ front
```

See `ao3.koplugin/spec/README.md` for details.

### Releasing

Releases are tag-driven, so the plugin and its updater manifest can never
drift apart:

```sh
# bump version in ao3.koplugin/_meta.lua first
git tag v1.0.1
git push ko3 main --tags
```

`.github/workflows/release.yml` then:

1. refuses to build unless `_meta.lua`'s `version` matches the tag;
2. builds a changelog from the commits since the previous tag;
3. zips `ao3.koplugin/` (tests excluded);
4. computes the SHA-256 and writes `manifest.json` with the full changelog;
5. publishes both as release assets, with the same changelog as the body.

`.github/workflows/ci.yml` runs a Lua 5.1 syntax check on every push and
pull request. The updater reads
`releases/latest/download/manifest.json`, so no API token is involved.

### Demonstrating a change in the emulator

Every user-visible change is also shown in the local Kindle emulator
(600×800), not only tested. After the suite is green:

1. Launch the emulator (`kodev run` or the `wl_launch.sh` helper used here).
2. Exercise the real screen with taps/keys, or, when live AO3 is gated,
   render the screen offscreen from the real markup fixtures and write it
   with `Screen.bb:writePNG(...)` from a throwaway busted spec.
3. Save the captures to `screenshots/` and add or update them in the table
   at the top of this README.

Tests prove behaviour; the emulator capture shows the actual result.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| KOReader exits when opening AO3 | An older KOReader build lacking newer font APIs. Current plugin versions fall back automatically — reinstall the latest `ao3.koplugin` |
| `429` or a wait message | Cloudflare's bot layer (or AO3) is refusing the client. A **VPN or privacy browser can trigger this**; wait the time shown, or turn the VPN off and retry. Do not repeatedly tap or reinstall to bypass it. If AO3 sends `Retry-After`, the plugin honors it. |
| `403` or a wait message | AO3 or its edge refused this client. A recognized browser check is not retried; other 403s get one retry, then a five-minute cooldown. |
| `404` | Work deleted, restricted, or downloads disabled |
| “did not return a work file” | Restricted/adult/login page instead of the work |
| “Could not parse the AO3 page” | AO3 changed its HTML, or `htmlparser` failed |
| Nothing happens after tapping Read | Check Wi-Fi and that the Kindle is online |
| “Could not check for updates” | The device cannot reach `github.com`. Check Wi-Fi; the check is a single small request |
| “failed its checksum” | The download was truncated or altered; nothing was installed. Try again |
| “does not contain the plugin” | The release asset is wrong or incomplete; the installed copy was left untouched |
| Update installed but nothing changed | KOReader is still running the old code — use **Restart** in the prompt, or restart it yourself |
| “Report saved” but no issue was created | The relay was unreachable; attach `report.md` (and `log.txt`) to a new issue |
| “Could not send the report” | Token rejected or no network; the report is still saved in `ao3/reports/` |

If a work opens as a login page or an adult warning, the file is rejected
before it reaches the reader, so you should see an error rather than a
broken book.

## Credits and trademarks

- The Archive of Our Own name and logo are trademarks of the Organization for
  Transformative Works (OTW). `assets/ao3-logo.png` is copied byte-for-byte
  from the OTW's own repository (`public/images/ao3_logos/logo.png`), and
  `assets/ao3-logo.svg` is a vector trace of it. Both identify the service
  this plugin reads; this plugin is unofficial and is not affiliated with or
  endorsed by the OTW.
- AO3's required-tag symbols (rating, warnings, category, completion) are
  redrawn in monochrome in `assets/icons/`; the shapes follow AO3's own symbol
  set (also collected in `gin7uro/koreader-ao3-plus/icons`), and the colour is
  dropped for the e-ink palette.
- KOReader is made by the KOReader contributors.
