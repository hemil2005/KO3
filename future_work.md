# Future Work

Planned improvements and feature ideas for KO3, aligned with the native-widget, low-tap, polite-client design in `PRODUCT.md` and `DESIGN.md`.

## Improvements to Existing Features

### Reader "Work details" from the reader
- **Problem:** Finishing a work leaves the reader with **Back to AO3**, which returns to the listing or Downloads it was opened from, not that work's **Work details**. The landing page's **Continue reading** row reopens the copy, but leaving kudos, a bookmark or a subscription still takes a trip through the listing.
- **Idea:** Record the work ID alongside the active reader path and add **Work details** to the reader menu and end-of-document dialog, jumping straight to `openWorkDetails(id)`.

### Settings cache info
- **Problem:** `Settings` still exposes only **Expanded tags** and **Work cards**. The installed version is on the **Update KO3** tile, but there is no place to see how much space the saved works take or to clear them.
- **Idea:** A small local-storage summary (count and bytes under `koreader/ao3`) with a **Clear saved works** action, without adding prose or a third display option to the settings page.

---

## New Features

### 1. Pinned Tags
- **Description:** Fandoms can now be pinned to the **Favourites** shelf by holding their index row. Tags cannot: pinning an arbitrary tag (a pairing, a trope, an additional tag) would need the same hold gesture on a tag listing and the same `settings/ao3_prefs.lua` record shape, with the tag's own works URL.

### 2. Completion Filter on Tag and Fandom Listings
- **Description:** Sorting now covers every listing that has a filter screen, and a keyword search already filters by completion. Tag and fandom listings still cannot narrow to completed works: AO3's sidebar does not ship that dimension, so it would be written as a bare `work_search[complete]=T` alongside the include/exclude facets, with the same pending-until-Apply rule.

### 3. Series Order on the Series Listing
- **Description:** A work's **Series** row now opens the series' works, but those cards do not say where each work sits. The series page carries the order; surfacing "Part 3" on the card (or sorting by it) would make following a long series easier.
