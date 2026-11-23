---
name: AO3 browser
description: AO3's works and fandoms, rebuilt as a printed catalogue in KOReader's native e-ink widgets.
colors:
  ink: "#000000"
  paper: "#ffffff"
  slate: "#888888"
  graphite: "#666666"
  hairline: "#555555"
typography:
  display:
    fontFamily: "smallinfofont"
    fontSize: "25px"
    fontWeight: 700
    lineHeight: 1.2
  headline:
    fontFamily: "smallinfofont"
    fontSize: "21px"
    fontWeight: 700
    lineHeight: 1.2
  title:
    fontFamily: "smallinfofont"
    fontSize: "19px"
    fontWeight: 700
    lineHeight: 1.2
  body:
    fontFamily: "smallinfofont"
    fontSize: "17px"
    fontWeight: 400
    lineHeight: 1.15
  meta:
    fontFamily: "smallinfofont"
    fontSize: "15px"
    fontWeight: 400
    lineHeight: 1.2
  hint:
    fontFamily: "smallinfofont"
    fontSize: "14px"
    fontWeight: 400
    lineHeight: 1.2
  action:
    fontFamily: "cfont"
    fontSize: "19px"
    fontWeight: 700
    lineHeight: 1.2
  action-small:
    fontFamily: "cfont"
    fontSize: "17px"
    fontWeight: 700
    lineHeight: 1.15
  micro:
    fontFamily: "smallinfofont"
    fontSize: "11px"
    fontWeight: 400
    lineHeight: 1.2
rounded:
  none: "0px"
  card: "7px"
spacing:
  gutter: "15px"
  gap: "10px"
  tight: "5px"
  hair: "2px"
  action: "46px"
  tile: "81px"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.paper}"
    typography: "{typography.action}"
    rounded: "{rounded.none}"
    height: "{spacing.action}"
    padding: "0 15px"
  button-secondary:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.action-small}"
    rounded: "{rounded.none}"
    height: "{spacing.action}"
    padding: "0 12px"
  tile-card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    rounded: "{rounded.card}"
    height: "{spacing.tile}"
    padding: "10px"
  work-card:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    rounded: "{rounded.none}"
    padding: "5px 15px 10px"
  section-header:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    rounded: "{rounded.none}"
    padding: "2px 15px 5px"
  stat-cell:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    padding: "0"
  tab:
    backgroundColor: "{colors.paper}"
    textColor: "{colors.ink}"
    typography: "{typography.title}"
    rounded: "{rounded.none}"
    padding: "2px 0"
---

# Design System: AO3 browser

## Overview

**Creative North Star: "The Printed Catalogue"**

This is a catalogue you enjoy opening, not a database you endure. Each screen reads like a page from a well-set library catalogue: a masthead (the AO3 mark and name), one decisive action, then entries — a bold title, a quiet byline, a blurb, a hairline between records. The interface is friendly because the hierarchy is obvious, and good-looking because the few elements it has are set with care: a solid ink bar is the only block of black, the logo is the only picture, and every grey is doing a specific job.

The system has no hue and no ornament. Its expressiveness comes from typographic contrast (bold nouns against small grey qualifiers), from rhythm (one gutter, one left edge, open between groups and tight inside them), and from the single inverted bar that tells you what the screen is for. Nothing is "minimal" by subtraction; the cards, the icon tiles, the stats strip and the tab strip all carry real information and real drawing. The result should feel considered and warm at arm's length on e-ink, never bare.

It is a native surface: stock KOReader widgets, KOReader's own fonts and scaling, no images beyond the AO3 trademark, no web rendering. The world lives inside the reader, so it borrows the reader's paper (white), ink (black), and patience (no motion).

**Key Characteristics:**
- Ink on paper only — no hue, no tinted fills, no colour accent.
- One solid black action bar per screen; everything else is outline, rule or text.
- A bold noun and a grey qualifier define every entry.
- One 15px gutter and one left edge across every screen.
- Flat: depth from hairlines, 1px borders and inverted bars, never from shadow.
- Square controls, gently rounded cards.
- Icon tiles and a logo lockup carry the warmth; grey rules carry the calm.

## Colors

A two-ink press: pure black and pure white, with three greys separating chrome from reading matter.

### Primary
- **Ink Black** (#000000): every title, every number, body text, icon strokes, 1px card borders, the fill of the one primary action bar, and the focus underline. It is also the "checked" signal on tabs and the only colour a tap ever produces.

### Neutral
- **Paper White** (#FFFFFF): the page. Also the label colour inside an inverted bar and the fill of outlined secondary buttons. There is no off-white or paper tint.
- **Slate Grey** (#888888): chrome and metadata — section labels ("Browse", "Library"), the "by …" line under a work title, fandom line, stat captions, the +/− glyph, and the 1px separators between menu rows.
- **Graphite Grey** (#666666): the quieter tier inside a record — a work card's author and three-line blurb, and a tile's hint. This is the lightest grey allowed to carry a sentence.
- **Hairline Grey** (#555555): the 1px rules that divide blocks inside the details page (under the hero, under the stats strip). It is a divider, never a text colour.

### Named Rules
**The Ink-and-Paper Rule.** No hue, ever. Every surface is black, white, or a value of grey, so the system renders identically on grayscale and colour e-ink. A change that needs colour to be understood is the wrong change.

**The One Inverted Bar Rule.** Exactly one solid ink bar per screen, for the action the screen exists for: "Search works" on the landing page, "Read" (or "Open saved copy") on a work. Everything else is outlined or plain text. Two black bars on one screen is a bug.

**The Two Greys Rule.** Slate is for the frame and Graphite is for the record. A work card's author and blurb are Graphite; a section label, stat caption or row separator is Slate. Never swap them, and never lighten text past Graphite.

## Typography

**Display Font:** KOReader `smallinfofont` (Noto Sans in the reference emulator)
**Body Font:** KOReader `smallinfofont` (the same face, at text sizes)
**Action Font:** KOReader `cfont` bold (button labels and the +/− section glyph)

**Character:** One sans face, used at a tight range of sizes, with bold reserved for nouns and numbers. The bookishness comes from spacing and rules, not from a serif; the reader's own KOReader font settings still govern the downloaded work itself. All sizes are offsets from KOReader's menu font size (19 in the 600×800 reference), not frozen pixels — the reader's font scaling and DPI carry through.

### Hierarchy
- **Display** (bold, menu size +6 → 25px, 1.2): the work title on the details page. Wraps; never truncates.
- **Headline** (bold, +2 → 21px, 1.2): the AO3 name in the landing-page lockup, and the native menu title bar.
- **Title** (bold, 0 → 19px, 1.2): card titles, section headers, tile names, stat values.
- **Body** (regular, −2 → 17px, 1.15): facts-table values and the folded Summary and Tags body.
- **Action** (bold, 0 → 19px, 1.2, `cfont`): primary bar labels; **Action Small** (bold, −2 → 17px, `cfont`): the secondary button's label.
- **Meta** (regular, −4 → 15px, 1.2): work-card author and blurb, facts-table labels, section labels, right-aligned row counts.
- **Hint** (regular, −5 → 14px, 1.2): the single grey hint under a tile's name ("Newest on AO3", "8 saved") — one step below the name, not a footnote.
- **Micro** (regular, −8 → 11px): the four stat captions (Words, Chapters, Kudos, Hits).

### Named Rules
**The Bold Noun Rule.** Every entry's name and every number is bold ink; everything that qualifies them — byline, blurb, caption, hint — is regular grey. If a line needs to be noticed, bold it; if it needs to be read once, grey it.

**The Measure Rule.** A work card's blurb stops at three lines (320 characters, 1.3 line spacing). Anything longer belongs behind a section header or in the dedicated full-text viewer, never in the list.

## Layout

One column, one left edge. The reference canvas is 600×800; content is inset 15px each side (`Size.padding.fullscreen`), leaving a 570px column, and every static panel uses that same inset so it lines up with native menu rows (which inset themselves).

Vertical rhythm is three steps: **20px** above a group label (two gutters), **5px** below it, **10px** between entries. Inside a card, title → byline is 2px, byline → blurb is 5px. Inside the details page, the hero opens with 5px, title → byline is 5px, byline → fandom is 2px, and a hairline closes the block.

- **Landing page:** logo lockup (84px-wide mark + name + subtitle), then the full-width solid Search bar, then three labelled groups. Browse and Library are two-up tile grids: two 280px tiles with a 10px gutter. A group with a single action (Update plugin, Restore) uses one full-width tile of the same construction.
- **Work listings:** full-width records, not a grid. Each card is as tall as its content needs (title line + byline + up to three blurb lines), closed by a 1px Slate separator inset to the gutter.
- **Work details:** hero, then an action row split 60/40 with a 10px gap (Read / Refresh), then a four-cell stats strip with 10px gaps, then a two-column facts table whose label column is 23% of the width, then folded Summary and Tags sections.
- **Paging is per item, not scroll.** The native menu header carries the screen title on one line (no subtitle band); the footer carries page arrows and "Page N of M". A page never clips a row.
- **No keyboard-shortcut columns** (`is_enable_shortcut = false`): the title, byline and blurb own the full width on a touchscreen.

### Named Rules
**The One Left Edge Rule.** Titles, bylines, labels, rules and separators all start at the 15px gutter. Nothing floats or centres except the title bar and the paging footer.

**The Open-Between Rule.** Groups are separated by air (20px + a quiet label); entries inside a group are separated by tightness first and a hairline second.

## Elevation & Depth

There are **no shadows, no gradients and no translucency** anywhere in the system. On e-ink a shadow reads as dirt, and a gradient banding as a printing fault. Depth is expressed with three flat devices: a 1px ink border (tiles), a 1px grey rule (hero, stats, list records), and inversion (the black action bar) or a glyph mark (the checked tab's checkmark). Focus is not a glow either: the menu's underline turns from 1px Slate to 5px solid ink on the focused row, and on touch it stays invisible.

### Named Rules
**The Flat Page Rule.** If a surface needs to stand out, it earns it with a border, a rule, or inversion — never with a shadow or a tinted fill.

## Shapes

The form language is a printed page, not a card app. Controls are **square** (0 radius): the primary bar, secondary buttons, the tab strip, the action row. Only the two-up content tiles are rounded, at 7px with a 1px ink border — they read as catalogue cards, not buttons. Nothing is pill-shaped, nothing has a coloured left border, nothing is clipped at an angle.

Icons are 24×24 vector strokes drawn at 26px, in the same weight as KOReader's own `mdlight` set; the AO3 mark is the official OTW artwork at 84px wide (57px tall). Both are the only graphics the system allows.

### Named Rules
**The Square Control, Rounded Card Rule.** A thing you press is square; a thing you read is a card. Never round an action bar, never square an icon tile.

## Components

### Buttons
- **Shape:** square (0 radius), no margin.
- **Primary:** solid Ink fill, Paper label, bold at menu size (19px), height 2.4× the menu size (46px at the reference), full column width on the landing page and 60% in the details action row. The inverted label is the point: KOReader's stock Button cannot express it, so the bar is a FrameContainer + TextWidget with a tap area.
- **Secondary:** Paper fill, 1.5px Ink border, bold Ink label one step smaller (17px), same height and column as the primary. Outlined, never greyed.
- **Pressed / Focus:** KOReader's own press feedback (fill darkens) plus the row underline; no hover state exists on the target device.

### Tiles (landing page)
- **Shape:** 7px radius, 1px Ink border, Paper fill, 10px padding.
- **Content:** 26px stroke icon, 10px, bold 19px name; 5px below, a 14px Graphite hint ("Newest on AO3", "By media", "8 saved"). The tile is two columns wide in the grid or one full-width tile for a lone action.
- **Height:** measured from its own content (81px at the reference), so the hint always fits.

### Work Cards (signature component)
- **Shape:** no box, no border. A record on paper, closed by a 1px Slate rule inset to the gutter.
- **Content:** bold 19px title on one line; 2px; 15px Graphite author (or "Anonymous"); 5px; a 15px Graphite blurb clamped to three lines with 1.3 line spacing and an ellipsis. Title, author and blurb are three separately styled widgets because a native Menu row only offers one font.
- **Behaviour:** the whole card is one tap target; the focus underline sits under the record, not under the text.

### Section Headers (folded content)
- **Style:** bold 19px Ink label at the left, a bold 21px Graphite "+" or "−" flush right; 2px above, 5px below.
- **Behaviour:** the row's focus underline doubles as the rule between sections. Summary and Tags start folded so the page stays one screen of decisions.

### Stats Strip
- **Style:** up to four equal cells with 10px gaps: a 11px Slate caption over a bold 19px Ink value. 5px above and below, then a 1px Hairline rule.
- **Behaviour:** empty values drop out entirely rather than leaving a gap; the remaining cells re-divide the width.

### Facts Table
- **Style:** two columns — a 23%-wide 15px Slate label, a 10px gutter, a wrapping 17px Ink value. 5px between rows.
- **Behaviour:** labels never truncate; values wrap to as many lines as they need.

### Tab Strip (author pages)
- **Style:** four equal, edge-to-edge segments (Dashboard / Works / Series / Bookmarks) with 0.5px Ink borders, bold 19px labels, Paper fill in every state.
- **State:** the current tab is marked with a "✓" after its label, not with a fill. No inset: the strip is the only full-bleed element in the system.

### Menu Rows
- **Style:** native density — 19px title at the left, a right-aligned 15px grey value ("2,523 fandoms", "Author page"), 1px Slate separator inset to the gutter. No shortcut boxes, no chevrons, no pills.

## Do's and Don'ts

### Do:
- **Do** keep exactly one solid Ink bar per screen and let it name the screen's purpose.
- **Do** align everything to the 15px gutter; the left edge is the system's spine.
- **Do** bold the noun and grey the qualifier: title/number bold, byline/blurb/caption regular.
- **Do** use Graphite for sentences inside a record and Slate for chrome; keep contrast survivable in grayscale.
- **Do** build tiles and actions from their content (icon + name + hint; 2.4× font height) so nothing clips.
- **Do** close each work record with a single hairline and keep the blurb to three lines.
- **Do** keep the AO3 mark and name as the only masthead identity, and leave the native title bar empty on the landing page.
- **Do** verify every screen in the 600×800 emulator and save the capture under `screenshots/`.

### Don't:
- **Don't** introduce hue, tinted backgrounds, gradients, or a second accent — Refresh stays black-and-white too.
- **Don't** add shadows or lift anything off the page; borders, rules and inversion are the only depth cues.
- **Don't** round buttons, bars or the tab strip; 7px belongs to tiles only.
- **Don't** wrap a work card in an outline box or add a cover thumbnail; cards are paper records.
- **Don't** centre body text, float section labels, or let a label drift away from the gutter.
- **Don't** use more than three blurb lines, a "show more" ellipsis inside a row, or any infinite scroll.
- **Don't** put two primaries on one screen, grey out a secondary action, or make a disabled state by lowering contrast below Graphite.
- **Don't** display the keyboard-shortcut column, breadcrumbs, chips or pagination dots; the catalogue voice has no web furniture.
