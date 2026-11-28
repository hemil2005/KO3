# Tests

These are KOReader `busted` specs. They run inside a KOReader checkout, so
the plugin is exercised against the same LuaJIT and frontend modules the
device uses.

From the root of a KOReader checkout:

```sh
# Link the plugin where KOReader's plugin loader can see it.
ln -s /path/to/ao3.koplugin plugins/ao3.koplugin

# Link the specs into the frontend unit suite.
for spec in plugins/ao3.koplugin/spec/ao3*_spec.lua; do
  ln -s "../../$spec" "spec/unit/$(basename "$spec")"
done

# Run the AO3 suites.
./kodev test --busted=--pattern=ao3_ front
```

The tests are offline:

- URL parsing and URL building are pure functions.
- `parseListing` runs against `fixtures/search.html`, a real AO3 search
  results page saved on 2026-11-22.
- The fandom tests build a tiny zlib-compressed letter file in a temp
  directory and read it back through the same `ffi/zlib` path the device
  uses; `ao3_fandompages_spec.lua` also covers bounded paging, cache
  eviction, malformed files and exact tag URLs.
- `fetchHtml` and `downloadWork` replace `socket.http.request` with a mock
  that streams fixture bytes into the same sinks the real client uses.
- `ao3_updater_spec.lua` covers version comparison, manifest rejection,
  traversal-safe entry planning, staged install, failed-rename rollback,
  restore-previous and checksum verification, with no network or real zip.
- `ao3_updatecheck_spec.lua` covers the background check: its 15-minute offline
  retry and daily cadence as a pure function, the prompt's dismissal and
  remind-later guards, the four choices (including the changelog viewer), and
  the rule that it never draws while the reader is on top.
- `ao3_bugreport_spec.lua` covers URL sanitising, log tails, consent-gated
  report bodies, bundle writing, token handling and relay submission
  (success, rate limit, missing configuration).
- `ao3_ui_spec.lua` builds the real work cards and checks their anatomy: the
  AO3 symbol grid, the title sharing its line with the byline (and the
  fallback when a long title needs its own), fandoms and ships (and their
  two-line fallback), the numbers, and the tag fold — including the gesture
  path that lets a tap on the box open it without opening the work.
- `ao3_preferences_spec.lua` covers the reader-preferences file: defaults, a
  round-trip, a non-boolean value, its separation from the session file, and
  the favourite-fandom list's normalisation (malformed entries, duplicate
  url/name, the twelve-item cap).
- `ao3_filters_spec.lua` covers the listing filter against
  `fixtures/filters.html`, a realistic work page carrying AO3's
  `form#work-filters` sidebar: facet ids, names, counts and radio/checkbox
  controls; the include/exclude apply URL; pre-selected filters from a URL;
  the tile root, its two-column grid and the selected-count hints; the
  dimension page's Include/Exclude side switch and checkmarks; paging with
  filters; the funnel's visibility and active state; the author Works tab; and
  the reset when the listing is popped.
- `ao3_sort_spec.lua` covers sorting inside the filter screen: columns and
  directions parsed from `filters.html` and `bookmark_filters.html`, the fixed
  search list (`_score`, `authors_to_sort_on`, `title_to_sort_on`,
  `created_at`, `revised_at`, `word_count`, `hits`, `kudos_count`,
  `comments_count`, `bookmarks_count`), the URL round trip, adopting a sorted
  URL, Apply writing exactly one column/direction pair, paging keeping it,
  clearing facets without losing it, and the funnel lighting for a non-default
  sort. It also measures the work, bookmark and search roots at 600×800 so the
  Apply bar stays on one page.
- `ao3_autocomplete_spec.lua` covers typed tag filtering: the
  `/autocomplete/<type>` URL and its encoding, the JSON name list (truncated to
  ten), a gzipped response, the generation token that drops a stale answer, the
  `work_search[other_tag_names]`/`excluded_tag_names` apply URL, de-duplication
  against embedded facets, and the quiet back-off after a 429 or a malformed
  body. `fixtures/autocomplete/` holds representative AO3 answers.
- `ao3_bookmarkfilter_spec.lua` repeats the filter contract against
  `fixtures/bookmark_filters.html`, a bookmark page carrying
  `form#bookmark-filters`: all eight dimensions (including the extra `tag`) as
  tiles, the `bookmark_search` apply URL with no `work_search` params, the
  bookmark dialog, paging, the author Bookmarks shelf, and reset on leave. Its
  typed-tag tests cover the add-tag row on the work and bookmarker dimensions,
  the two separate name fields, and adopting both from a pasted URL; its sort
  tests pin `created_at`/`bookmarkable_date`/`word_count` with no direction.
- `ao3_downloadsfilter_spec.lua` covers the local Downloads filter: title and
  `#id` matching in any case, narrowing and clearing on screen, the unchanged
  empty/storage rows, and that no request is made.
- `ao3_searchfilters_spec.lua` covers the search funnel, which has no sidebar:
  the search-URL test, every static id and name pinned to
  `fixtures/search_form.html` (a trimmed copy of AO3's live edit-search form),
  the include-only fixed rows, applying `work_search[...]` params beside the
  query, adopting a pasted filtered search, paging, and the funnel's life on a
  search listing.
- `ao3_searchhistory_spec.lua` covers the recent-searches picker: the keyboard
  is hidden before the picker opens and restored after a pick or a dismissal,
  the text is set once with the caret at the end, and a pick does not
  double-restore the keyboard.
- `ao3_favourites_spec.lua` covers pinned fandoms: storing and reloading the
  list, toggling from an index row (heart in place, page repaint), the home
  shelf's four-tile cap and **All favourites** row, and the hold gesture that
  unpins. No request is made.
- `ao3_series_spec.lua` covers the work page's `dd.series` shapes (one series,
  several `span.position` blocks, the `span.series` fallback, a malformed or
  absent dd), the details rows and their carried entry, the guarded
  `/series/<id>` open, and the series listing's blurbs and pagination with no
  filter funnel. It also covers the listing gap: a work opened from a card has
  no series, so one work-page read fills it and repaints in place, offline
  stays quiet, the answer is remembered, and a signed-in reader borrows the
  action-state page instead of making a second request.
- `ao3_workwatch_spec.lua` covers the quiet saved-work watch: AO3's chapter
  menu (`ol.chapter.index`, the link fallback, a login page), the per-work
  daily interval, WIP-only planning, the budget and oldest-first order, pruning
  entries for deleted files, the badge count recomputed from the saved
  preface, the 404 "gone" answer, stopping at a refusal, the manual run over
  every WIP, the bell's dot and the Updates screen's rows.
- `ao3_workupdate_spec.lua` covers saved-work update checks: the chapter
  parser (`3/7`, `3/?`, a bare number), the bounded preface read, the
  comparison and its messages, the WIP rule (unknown total or fewer chapters
  than total), the single-request Downloads check with its confirmation before
  `readWork(..., true)`, and the zero-request details row.
- The report flow is also exercised through the UI: the home row, the
  editor, the log-consent dialog and the saved bundle.
- The plugin loader test calls `load_plugin("ao3")`, so `_meta.lua` and
  `main.lua` are loaded through KOReader's own plugin loader.

`fixtures/work.html` is a minimal valid AO3 HTML download. `login.html`
and `challenge.html` cover the two common non-work responses.
`fixtures/account/work_actions_*.html` are trimmed copies of AO3's signed-in
work page forms: the first has nothing marked, the second has a bookmark,
subscription and read-later entry to remove.
`fixtures/account/subscriptions.html` follows AO3's real subscriptions page:
a `dl.subscription` with one `dt` per entry, the "(Work)"/"(Series)" suffix
and byline in the same cell, and the unsubscribe form in the `dd`.

Live checks are separate from this suite. A repo-root `.env` may hold test
credentials as `EMAIL` and `PASSWORD`; it is gitignored, and its values must
never be printed, logged or committed. Use it only for a deliberate signed-in
check, then remove anything the check created on AO3.

## Build environment notes

A full `make base` is the heavy part. On current Debian/Ubuntu images the
build also needs `meson`, `ninja`, `cmake`, `ccache`, and the X11/Wayland
development headers. If a third-party release asset from
`release-assets.githubusercontent.com` times out, the file can be fetched
through a GitHub mirror and placed in the matching
`base/thirdparty/<lib>/build/downloads/` directory. That is a network
workaround, not a plugin dependency.
