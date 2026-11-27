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
  round-trip, a non-boolean value, and its separation from the session file.
- The report flow is also exercised through the UI: the home row, the
  editor, the log-consent dialog and the saved bundle.
- The plugin loader test calls `load_plugin("ao3")`, so `_meta.lua` and
  `main.lua` are loaded through KOReader's own plugin loader.

`fixtures/work.html` is a minimal valid AO3 HTML download. `login.html`
and `challenge.html` cover the two common non-work responses.
`fixtures/account/work_actions_*.html` are trimmed copies of AO3's signed-in
work page forms: the first has nothing marked, the second has a bookmark,
subscription and read-later entry to remove.

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
