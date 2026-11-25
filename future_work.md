# Future Work

Planned improvements and feature ideas for KO3, aligned with the native-widget, low-tap, polite-client design in `PRODUCT.md` and `DESIGN.md`.

## Improvements to Existing Features

### Reader "Back to AO3" / Post-Read Work Actions
- **Problem:** When a reader opens a cached work from `Downloads` or `Open work` and finishes reading it, there is no direct shortcut from the reader's end-of-document dialog or reader menu to that work's **Work details** page to leave kudos, bookmark, subscribe, or toggle Marked for Later.
- **Idea:** Record the work ID alongside the active reader path so the reader menu / end-of-document flow can offer a direct jump to **Work details** (`openWorkDetails(id)`).

### Settings Discoverability & Local Cache Info
- **Problem:** `Settings` currently exposes only `Expanded tags` and `Work cards`, leaving no place to see the installed plugin version or manage local storage.
- **Idea:** Show the installed `_meta.lua` version in `Settings` (or on the `Update KO3` row) and consider a local cache/downloads summary row.

---

## New Features

### 1. Pinned / Favorite Fandoms & Tags (Offline-First)
- **Description:** Navigating `Fandoms → Media → Letter → Window → Fandom` or retyping a tag every session takes multiple taps. Allow readers to pin/favorite fandoms or tags locally (persisted in `settings/ao3_prefs.lua` or a separate local file, toggled via long-press on a fandom or tag listing) so they appear in a quick-access section on the Home or Browse screen.

### 2. Lightweight Sort & Completion Filter
- **Description:** While `PRODUCT.md` intentionally excludes AO3's full filter matrix, adding a minimal **Sort by** (Date Updated, Kudos, Word Count, Hits) and **Completed only** option on Search and Tag listings would fit in a small native dialog and still fetch only one page per tap.

### 3. Series Navigation on Work Details
- **Description:** `authorpage.lua` already parses series listings, but `workpage.lua` does not yet surface series membership for a work (e.g., *Part 2 of Series Name*). Adding a tappable series link on the Work Details screen would let readers jump directly to the series' work list and follow multi-part stories.

### 4. Update Check for Downloaded WIPs
- **Description:** For multi-chapter works-in-progress saved in `Downloads`, offer a manual **Check for updates** action (or show the cached chapter count alongside the live count when refreshed) so readers can tell when an in-progress fic has new chapters without blindly re-downloading.
