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
- After any user-visible change, demonstrate it in the local Kindle emulator
  and save a capture under `screenshots/`. Tests alone are not enough.

## Downloaded works

- The table of contents is the work's chapters only: drop AO3's hidden
  "Preface" metadata heading and the work-title wrapper, then flatten. A flat
  TOC opens fully expanded.
- Opening a work from the plugin must return to the plugin screen (Back key,
  reader menu and end-of-document dialog), not to KOReader's file manager.

## Network

- Do not send requests to AO3 unless the user asks. No probing, no retries
  after a 429, no crawling.
- One page per tap; honour `Retry-After`; validate a download before replacing
  a cached copy.
