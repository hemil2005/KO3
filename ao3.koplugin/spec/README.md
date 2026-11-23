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
- The plugin loader test calls `load_plugin("ao3")`, so `_meta.lua` and
  `main.lua` are loaded through KOReader's own plugin loader.

`fixtures/work.html` is a minimal valid AO3 HTML download. `login.html`
and `challenge.html` cover the two common non-work responses.

## Build environment notes

A full `make base` is the heavy part. On current Debian/Ubuntu images the
build also needs `meson`, `ninja`, `cmake`, `ccache`, and the X11/Wayland
development headers. If a third-party release asset from
`release-assets.githubusercontent.com` times out, the file can be fetched
through a GitHub mirror and placed in the matching
`base/thirdparty/<lib>/build/downloads/` directory. That is a network
workaround, not a plugin dependency.
