# Development

How KO3 talks to AO3, what has been verified, how the tests run, and how
releases are cut. User-facing documentation is in the [user guide](USER-GUIDE.md).

---

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
    -> parse <form id="work-filters"> into the listing's include/exclude facets
  Filters (on Apply only; AO3's own page links keep them while paging):
  GET ...?include_work_search[rating_ids][]=10&exclude_work_search[fandom_ids][]=17
  Typed tags (suggestion on pause, one request; Apply writes names, not ids):
  GET /autocomplete/<fandom|character|relationship|freeform|tag>?term=<text>
  GET ...?work_search[other_tag_names]=Hannibal%20(TV),Hurt%2FComfort

Search results (no #work-filters on the page; fixed lists from the edit form):
  GET .../works/search?work_search[rating_ids][]=10&archive_warning_ids[]=16
      &category_ids[]=23&complete=T&crossover=F&other_tag_names=...
      &work_search[query]=...
  GET .../users/<name>/bookmarks?include_bookmark_search[tag_ids][]=55001
  Bookmarker's typed tags: bookmark_search[other_bookmark_tag_names]=...

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

Saved-work watch (silent; one work per tick, at most once a day per work):
  GET /works/<id>/navigate                    chapter list only, not the work
  GET /users/<login>/subscriptions            the signed-in reader's list,
                                              one page per tick, once a day

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

## Verification record

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
- Settings has three options, each a label and its value — **Expanded tags:** On
  or Off, **Work cards:** Modern or Legacy, and **Subscribed works:** On or
  Off — stored in
  `settings/ao3_prefs.lua`, separately from the AO3 session. A tap flips the
  choice, the row redraws with its new value, and every work list already on
  the back stack is restyled from its own rows, so returning to it shows the
  new design without fetching the page again. Captured in `screenshots/41`.
- The listing filter, built from AO3's own `#work-filters` sidebar in the same
  response as the works: a funnel at the top-left of the title bar, opposite
  the close button, opens an **Include** / **Exclude** screen whose fourteen
  dimension rows, two quiet group labels and its Clear/Apply row fit one
  600×800 page; a dimension opens its facets with work counts and KOReader's
  checkmark. Ticking changes only local state; Apply makes the single request
  and replaces the listing at page 1, AO3's paging links keep the filters, and
  leaving the listing clears them. Captured in `screenshots/46`–`47`.
- Bookmark listings reuse that screen against `#bookmark-filters`: eight
  dimensions in both groups (the work dimensions plus **Bookmarker's Tags**),
  emitted as `bookmark_search[...]`, with the dimension rows one notch tighter
  so the same Clear/Apply bar still closes the form on one page. The funnel is
  absent everywhere else. Captured in `screenshots/51`–`52`.
- Downloads has no AO3 page, so its filter is local: a magnifier row over the
  saved files opens a native input box whose every keystroke narrows the list
  by title or `#id`, and clearing it restores the shelf without a request. The
  storage-folder row and the empty state are unchanged. Captured in
  `screenshots/53`.
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
- The four new surfaces render together on the merged tree (600×800): the
  Favourites shelf with four tiles and **All favourites**, **Continue reading**
  under Library, the filter screen as a Sort tile plus seven dimension tiles,
  one dimension's Include/Exclude switch, the Sort by page, a work details page
  showing "2 new chapters · 3/7 → 5/7" and two series rows, and the Downloads
  actions with **Check for updates** (`screenshots/63`–`72`). The demo seeds a
  local preferences file and a saved preface; it makes no AO3 request.
- The subscriptions list is parsed from a copy of AO3's real definition-list
  markup, so a work ("by Author One"), a series and a user each get a row and
  the byline is not mistaken for the subscription (`screenshots/73`). A work
  opened from a listing paints immediately and then grows its **Series** group
  from one page read; the capture shows both series in place
  (`screenshots/74`). The demo stubs only the transport.
- The quiet watch's screens render from local facts, with no AO3 request: the
  landing page with the bell's filled dot beside the gear
  (`screenshots/75`), **Updates** listing two works that grew ("2 new ·
  3/7 → 5/7") and one AO3 no longer serves (`screenshots/76`), and the
  Downloads rows carrying "#51358966 · 2 new" (`screenshots/77`). The demo
  seeds saved prefaces and the check entries the watcher would have written.
- The watch was then run against a real work end to end: `/works/57085603`
  downloaded through the plugin (4.36 MB), its saved `Chapters: 159/159`
  lowered to `1/159` in the preface, and one quiet check made a single
  `GET /works/57085603/navigate` (200, 39,548 bytes) that parsed **159**. The
  bell took its dot, the row read "158 new · 1/159 → 159/159"
  (`screenshots/78`), and the Downloads row said "#57085603 · 158 new". This
  run also found that AO3's own download has no `dd.chapters` cell at all —
  the parser now reads the Stats row, which is what a real save contains.
- The subscription side was run against the same real work: a followed entry
  with a stored baseline of 150 chapters, one quiet check making a single
  `GET /works/57085603/navigate` (200, 39,522 bytes) that parsed **159**, so the
  bell took its dot and Updates listed "9 new · 150 → 159"
  (`screenshots/79`). The subscription list itself was not read live — the
  emulator is signed out and the earlier live sign-in hit AO3's 429 — so its
  parser stays pinned to AO3's real definition-list markup and its paging to
  the controller's `will_paginate`. The settings switch is captured in
  `screenshots/41`.
- A subscription entry is not a blurb, and its card used to paint details from
  the entry alone: the screen was empty. `parseSubscriptions` now marks work
  entries `brief`, and `workRow` opens them through `openWorkDetails`, which
  reads the work page once. The page used for the capture is the real signed-in
  page of work 91979691, saved from the browser and replayed to the parser;
  the details show 15/?, the tags, the summary and "Part 1 of Shan'Dur"
  (`screenshots/80`).
- AO3's download edge serves the generated file by URL and can stay behind the
  newest chapter. Work 91979691 read 15/? on the site but its plain
  `/downloads/91979691/work.html` returned 14/?; adding `?v=<epoch>` returned
  15/? immediately, and the plugin's refresh downloaded a save whose preface
  says 15. A refresh now appends that query; a first download keeps the plain
  URL.
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
- The background update check: the 15-minute offline retry and the 24-hour
  cadence are a pure function, a failed check logs instead of drawing, the
  prompt appears only when the plugin menu is the top window (never over the
  reader), and Update, Remind later, Dismiss and Changelog each keep their own
  state. Captured in `screenshots/48`–`49`.
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
- The offline `busted` suite: 551 tests passing across parser, navigation,
  bounded-index, rendered-card interaction (including the symbol grid, the tag
  fold and its tap path), reader preferences, old-build compatibility,
  author-page, work-page, account-screen, home-page, reader-hook, updater,
  listing-filter, tag-autocomplete, search-filter, bookmark-filter,
  Downloads-filter, search-history, background-update-check, bug-report,
  favourite-fandom, series-navigation, filter-sort and saved-work-update tests,
  including 53 account tests across token parsing, the three-request
  sign-in, cookie
  scoping/rotation, session persistence/logout, subscription parsing and work
  actions. The subscription tests run against AO3's real definition-list
  markup (`dl.subscription dt`, the "(Work)" suffix and byline in the same
  cell), so a work, a series and a user each become the right row without the
  byline link being mistaken for the subscription. The work-action tests cover
  the website's form bodies, reading the
  work page's bookmarked/subscribed/read-later state, one-time token reuse,
  bookmark and subscription ids returned by AO3, already-done duplicates and
  the refusal to post twice. The filter tests cover facet parsing (ids, names,
  counts, radio vs checkbox), the apply URL's include/exclude params,
  pre-selected filters, the tile root and its two-column grid, the Include /
  Exclude switch on a dimension page, checkmarks, paging with filters, the
  button's visibility and active state, and the reset on leaving the
  listing; the bookmark-filter tests repeat that against `#bookmark-filters`,
  including the `tag` dimension and the absence of `work_search` params, and
  the Downloads-filter tests cover case-insensitive title and `#id` matching,
  clearing, the unchanged empty and storage rows, and that filtering makes no
  request. The sort tests pin AO3's columns and directions, the URL round trip,
  adopting a sorted URL, Apply writing exactly one pair, paging keeping the
  sort, and clearing facets without losing it. The favourite tests cover the
  preference round trip and normalisation, hold-to-pin, the heart on an index
  row, and the home shelf's four-tile cap and **All favourites** row. The
  series tests cover the `dd.series` shapes (one series, several, the
  `span.series` fallback), the details rows and the guarded open. The saved-work
  update tests cover the chapter parser, the bounded preface read (both the
  website's `dd.chapters` shape and the plain Stats row AO3's own download
  writes), the comparison and its messages, the one-request Downloads check,
  and the zero-request details row. The watch tests cover the chapter menu
  parser and
  its link fallback, the daily interval, WIP-only planning, the budget and
  oldest-first order, pruning a deleted file's entry, the badge recomputed from
  the saved preface, the 404 "gone" answer, stopping at a refusal, the manual
  run over every WIP, the bell's dot and the Updates rows. The update-check
  tests cover the once-a-day policy,
  the 15-minute offline retry, prompt gating on the top window, and the Update
  / Remind later / Dismiss / Changelog actions. The autocomplete tests cover the
  per-type request URL and its encoding, the JSON name list truncated to ten,
  a gzipped answer, a dropped stale generation, the names written to
  `other_tag_names`/`excluded_tag_names`, embedded-name de-duplication, and the
  quiet back-off after a 429 or malformed answer.

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


## Tests

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

## Releasing

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

## Demonstrating a change in the emulator

Every user-visible change is also shown in the local Kindle emulator
(600×800), not only tested. After the suite is green:

1. Launch the emulator (`kodev run` or the `wl_launch.sh` helper used here).
2. Exercise the real screen with taps/keys, or, when live AO3 is gated,
   render the screen offscreen from the real markup fixtures and write it
   with `Screen.bb:writePNG(...)` from a throwaway busted spec.
3. Save the captures to `screenshots/` and add or update them in
   [SCREENSHOTS.md](SCREENSHOTS.md). The README's tour GIF and grayscale
   plates are derived from these captures into `docs/images/`.

Tests prove behaviour; the emulator capture shows the actual result.


## Repository layout

The installed plugin is one folder:

```
koreader/
  plugins/
    ao3.koplugin/
      _meta.lua
      main.lua
      account.lua
      accountpage.lua
      authorpage.lua
      autocomplete.lua
      filterpage.lua
      fandompages.lua
      homepage.lua
      searchfilters.lua
      searchhistory.lua
      settingspage.lua
      preferences.lua
      workpage.lua
      workupdate.lua
      workwatch.lua
      uikit.lua
      updater.lua
      bugreport.lua
      assets/ao3-logo.png
      assets/ao3-logo.svg
      assets/icons/*.svg
      data/fandoms/index.lua
      data/fandoms/<category>/<letter>.tsv.z
```

## Why Cloudflare cookies are never replayed

The plugin deliberately does not replay Cloudflare's bot cookies: they are
bound to the client that earned them, and sending them back from LuaSocket is
what made the 403 stick for the plugin while `curl` could still fetch pages.

