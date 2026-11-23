# Kindle crash candidates — remaining frontend APIs used by `ao3.koplugin/main.lua`

Status: root cause already found from the device `crash.log` and fixed — `TextWidget.getTextHeight`
(missing before 2026-11-13) now has a cached probe-widget fallback at `main.lua:471-489`, and
`Menu:mergeTitleBarIntoLayout` is guarded at `main.lua:790-794`. This file lists **only what is
still unguarded**.

Audited: `E:\ao3 plugin\ao3.koplugin\main.lua` (1502 lines, mtime 2026-11-23 15:45) and
`fandompages.lua` (306 lines, mtime 2026-11-23 13:15).
Reference checkout: `~/koreader` @ `1294bb3d377c` (2026-11-21, shallow — no local history).
Recency was therefore established from GitHub: release tags `v2023.10 … v2026.07.2` were fetched
and diffed, and `koreader/koreader` commit history was queried per file.

Verification base: for each symbol below, "absent in releases" means the symbol does not occur
anywhere in `frontend/ui/widget/menu.lua`, `focusmanager.lua`, `container/underlinecontainer.lua`,
`ui/size.lua` or `widget/textwidget.lua` of tags `v2024.03, v2024.11, v2025.10, v2026.07,
v2026.07.2`.

---

## Ranked remaining candidates

### 1. `Size.line.focus_row` — newest symbol still used unguarded (hard error only on debug builds)

- Call site: `main.lua:617` — `focus_linesize = Size.line.focus_row` inside `Ao3MenuItem:init`.
- Added to KOReader: **2026-09-03**, commit `64dfa3102b` "Size: settle the focus underline on one
  thickness (#15988)"; also touched by `be181acfa2` (2026-08-15).
- Present in checkout: `frontend/ui/size.lua:71` (`focus_row`); `focus_indicator` is at `size.lua:68`.
- Absent in: **every release through v2026.07.2** (checked all five files in all five tags).
- Impact today: on a normal release build `Size.line.focus_row` is simply `nil` — the extra
  `UnderlineContainer` option is ignored by old builds, so this is cosmetic, **not a crash**.
  It *is* a crash on any build with `dbg.is_on` (debug logging / debug build), because `size.lua`
  installs an `__index` metatable that raises `Size: this property does not exist:
  Size.line.focus_row` (`frontend/ui/size.lua:91-108`).
- Safe fallback (one line):
  `focus_linesize = rawget(Size.line, "focus_row") or rawget(Size.line, "thick")`
  (`rawget` also avoids the debug-metatable error).

### 2. Variable-height `Menu` machinery (`items_max_lines`, `setupItemHeights`, `available_height`, `page_items`, `getPageNumber`)

- Call sites: `main.lua:692-697` (`items_max_lines = 4`), `main.lua:700-733`
  (`Ao3WorkMenu:setupItemHeights`, uses `self.available_height` at `:723` and
  `self.item_dimen.h` at `:715`), `main.lua:737-750` (`getPageNumber`), `main.lua:752-801`
  (`updateItems` override, reads `self.page_items` at `:761`).
- Added to KOReader: `2024-05-07` (`c47d3b3177`), `2024-05-16` (`6b192c346a`), final shape
  `2024-06-01` (`b06272592d` "Annotation list: flexible item heights (#11918)"). First release
  with it: **v2024.07**. Checkout: `menu.lua:625, 678-679, 1255-1300, 1239-1253, 671-677`.
- Absent in: `v2023.10`, `v2024.03` (`_recalculateDimen` there has no `items_max_lines` branch and
  no `available_height`, and `switchItemTable` computes the page itself with `math.ceil`).
- Impact: **no crash, but a blank AO3 screen** on builds older than 2024.07 — the base
  `_recalculateDimen` never calls `setupItemHeights`, so `self.page_items` stays `nil` and the
  plugin's `updateItems` renders zero rows (the `nil`-safe guard at `main.lua:761` hides it).
  Worth knowing because a Kindle user may report "AO3 opens but the list is empty".
- Safe fallback (one line each):
  in `updateItems`, `if not self.page_items then self:setupItemHeights() end` before reading it, and
  in `setupItemHeights`, `local budget = self.available_height or (self.item_dimen.h * (self.perpage or 1))`.

### 3. `UnderlineContainer` focus-indicator API (latent — dead code on every release)

- Call sites: `main.lua:614-623` (`focus_linesize`, `background`, `vertical_align` options),
  `main.lua:672-674` (`getFocusIndicatorRegion` → `self._underline_container:getFocusIndicatorRegion()`),
  `main.lua:676-678` (`repaintFocusIndicator`), `main.lua:680-690` (`onFocus`/`onUnfocus` set
  `self._underline_container.focused`).
- Added to KOReader: `2026-08-15` (`be181acfa2`) and `2026-08-29` (`65e9b1e1bb` "FocusManager:
  repaint the focus indicator, not the whole window (#15897)"). Checkout:
  `frontend/ui/widget/container/underlinecontainer.lua:15-30, 44, 84`;
  `frontend/ui/widget/focusmanager.lua:328-360` (`canFastRepaint` / `_repaintFocusChange`).
- Absent in: **every release through v2026.07.2**. In those builds `FocusManager` never calls
  `item:getFocusIndicatorRegion` / `repaintFocusIndicator` at all, and unknown constructor options
  are ignored — so this cannot crash today. It becomes a crash only if a future/backported build
  gains the caller without the `UnderlineContainer` methods.
- Safe fallback (one line each):
  `if self._underline_container.getFocusIndicatorRegion then return self._underline_container:getFocusIndicatorRegion() end`
  and the same guard for `repaintFocusIndicator` (return `nil`/`false` otherwise — that is exactly
  what new `FocusManager` treats as "fall back to a full repaint").

### 4. Not a risk, for the record

- `Menu:getItemShortCutIcon` — added 2025-03-19 (`5463ab641e`), missing in ≤v2024.11, but the plugin
  sets `is_enable_shortcut = false` (`main.lua:1057`) and never calls it. No action needed.
- `Menu:mergeTitleBarIntoLayout` — present since at least v2023.10 (`menu.lua:1162`); already guarded.
- `Menu:switchItemTable` (`main.lua:1103,1115,1122,1138`), `item_table_stack`
  (`main.lua:1076-1112`), `Menu.onClose` (`main.lua:1084`), `page_return_arrow:enableDisable`
  (`main.lua:1089,1106,1117`), `updatePageInfo`, `_recalculateDimen`, `item_dimen`, `show_parent`:
  all present in **v2023.10 and every later tag**.
- `is_enable_shortcut`, `items_mandatory_font_size`, `handle_hold_on_hold_release`,
  `Menu:onMenuSelect/onMenuHold`: present in every tag checked (v2023.10+).
- `TextWidget:new`/`:getSize()`/`:getWidth()`/`:free()` (the current fallback at `main.lua:482-485`):
  present in every tag; `getSize` = `textwidget.lua:292`, `free` = `:406`.
- `TextBoxWidget` options `height_adjust`, `height_overflow_show_ellipsis`, `line_height = 0.3`
  (`main.lua:536-545`): present since v2023.10 (`textboxwidget.lua:48,53,54,151`).
- `InputDialog:onShowKeyboard` (`main.lua:1319,1415,1445,1480`), `getInputValue`,
  `is_enter_default`, `description`: present in every tag (`inputdialog.lua:640,587`).
- `KeyValuePage` rows with a plain string separator (`main.lua:874`, `keyvaluepage.lua:727`):
  present in every tag.
- `Trapper:wrap/info/reset` (`main.lua:415-429, 991-1001`; `trapper.lua:42,85,125`),
  `NetworkMgr:runWhenOnline/afterWifiAction` (`main.lua:414,431,990,1003`;
  `network/manager.lua:698,621`), `socketutil:set_timeout/reset_timeout`
  (`main.lua:203,214,920,936`; `socketutil.lua:53,66`), `ffi/zlib.zlib_uncompress`
  (`fandompages.lua:39,101`; `base/ffi/zlib.lua:25`), `htmlparser` (`main.lua:41,305`;
  shipped in `common/`), `util.htmlToPlainTextIfHtml/htmlEntitiesToUtf8/urlEncode/getSafeFilename`
  (`main.lua:82-83,334-335,955,961,963,1361,1376`; `util.lua:1295,1251,1443,973`),
  `Font:getFace` + `face.size` (`main.lua:493-494`; `font.lua:269,343`),
  `Blitbuffer.COLOR_GRAY_6` (`main.lua:533,544`; `blitbuffer.lua:2985`),
  `DataStorage:getFullDataDir` (`main.lua:119`; `datastorage.lua:85`),
  `readerui:showReader` (`main.lua:986,1006,1331`), `lfs` (`main.lua:120-128,1023-1028`):
  all long-stable, present in v2023.10.

---

## Load-time safety (checked, no action needed)

- Plugin loading is **pcalled**: `frontend/pluginloader.lua:244` `pcall(dofile, mainfile)` and
  `:480` `pcall(plugin.new, plugin, attr)`. A load-time error in `main.lua` (or in the
  `dofile(fandompages.lua)` at `main.lua:369`) cannot crash startup; it logs
  "Error when loading …" and the plugin simply does not appear. Same in v2023.10–v2026.07.2.
- `main.lua:368-369`: `debug.getinfo(1,"S").source:sub(2)` yields the path **as passed to
  `dofile`** — `plugins/ao3.koplugin/main.lua` for the default plugin dir
  (`DEFAULT_PLUGIN_PATH = "plugins"`, `pluginloader.lua:24,208`), or an absolute path when the
  plugin lives in `extra_plugin_paths`. `gsub("main%.lua$", "fandompages.lua")` is therefore
  correct in both forms, and the `dofile` is relative to KOReader's cwd (the install dir).
- Consequence for diagnosis: if `fandompages.lua` is missing or corrupt, the symptom is a
  **missing AO3 menu entry**, not a crash. Runtime errors in tap handlers (e.g. the old
  `TextWidget.getTextHeight` call) are the ones that reach `UIManager` and restart the reader.

## Suggested next step on the device

Check `koreader/crash.log` for `attempt to call field 'focus_row'` / `Size.line.focus_row`
(only plausible if debug logging is enabled) and confirm the KOReader version with
`Help → About`; anything ≤ v2026.07.2 needs candidate 1 guarded, and anything < v2024.07 needs
candidate 2's blank-list fallback.
