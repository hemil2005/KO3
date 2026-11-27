---
name: KO3
description: KO3 — AO3's works and fandoms, rebuilt as a printed catalogue in KOReader's native e-ink widgets.
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
  pill: "half the control's height"
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
    rounded: "{rounded.pill}"
    padding: "2px 0"
---

# Design System: KO3

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
- AO3's required tags become a 2×2 symbol grid beside each work title.

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

**The One Inverted Bar Rule.** Exactly one solid ink bar per screen, for the action the screen exists for: "Search works" on the landing page, "Read" (or "Open saved copy") on a work. Everything else is outlined or plain text. Two black bars on one screen is a bug. A screen that is itself a contents page — the account screen, the author page — carries none: its rows or its tab strip are the action, and a bar added beside them would be a second control for one destination.

**The Two Greys Rule.** Slate is for the frame and Graphite is for the record. A work card's byline, fandoms, ships, tag text and blurb are Graphite; the tag fold's border and its +/− glyph, a section label, stat caption or row separator is Slate. Never swap them, and never lighten text past Graphite.

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
- **Meta** (regular, −4 → 15px, 1.2): work-card byline, fandoms, ships, tag box and blurb, facts-table labels, section labels, right-aligned row counts. A record's numbers use the same size in bold (Words, Chapters, Updated).
- **Hint** (regular, −5 → 14px, 1.2): the single grey hint under a tile's name ("Newest on AO3", "8 saved") — one step below the name, not a footnote.
- **Micro** (regular, −8 → 11px): the four stat captions (Words, Chapters, Kudos, Hits).

### Named Rules
**The Bold Noun Rule.** Every entry's name and every number is bold ink; everything that qualifies them — byline, blurb, caption, hint — is regular grey. If a line needs to be noticed, bold it; if it needs to be read once, grey it.

**The Measure Rule.** A work card's blurb stops at three lines (320 characters, 1.3 line spacing). Anything longer belongs behind a section header or in the dedicated full-text viewer, never in the list.

**The Two-Line Index Rule.** A fandom's name in the letter index runs to at most two lines and then ends with an ellipsis; its work count sits in a right-aligned column that never wraps. Only the second line is paid for when the name needs it, so a short name keeps a one-line row.

## Layout

One column, one left edge. The reference canvas is 600×800; content is inset 15px each side (`Size.padding.fullscreen`), leaving a 570px column, and every static panel uses that same inset so it lines up with native menu rows (which inset themselves).

Vertical rhythm is three steps: **20px** above a group label (two gutters), **5px** below it, **10px** between entries. Inside a card, title → byline is 2px, byline → blurb is 5px. Inside the details page, the hero opens with 5px, title → byline is 5px, byline → fandom is 2px, and a hairline closes the block.

- **Landing page:** logo lockup (84px-wide mark + name + subtitle), with the settings gear as a 44px tap target at the right edge of that masthead line; then the full-width solid Search bar, then four labelled groups: Browse, Account, Library, Plugin. Browse and Library are two-up tile grids: two 280px tiles with a 10px gutter. Account and Plugin each use one full-width tile of the same construction; Account swaps its symbol and name with the session (login → Sign in, user → the reader's name). A label always travels with the first row of its group, so paging never leaves a label alone at the foot of a page.
- **Work listings:** full-width records, not a grid. Each card is as tall as its content needs (title block + fandoms + ships + tag fold + up to three blurb lines + numbers), closed by a 1px Slate separator inset to the gutter.
- **Fandom list:** the letter index band (about 135px, three shelves) is pinned above a full-width index: a bold name of one or two lines and a right-aligned count, closed by the same 1px Slate separator. The search row follows the band; paging rows close the list.
- **Work details:** hero, then an action row split 60/40 with a 10px gap (Read / Refresh), then a four-cell stats strip with 10px gaps, then a two-column facts table whose label column is 23% of the width, then the four account actions in a 2×2 grid, then folded Summary and Tags sections.
- **Paging is per item, not scroll.** The native menu header carries the screen title on one line (no subtitle band); the footer carries page arrows and "Page N of M". A page never clips a row.
- **No keyboard-shortcut columns** (`is_enable_shortcut = false`): the title, byline and blurb own the full width on a touchscreen.

### Named Rules
**The One Left Edge Rule.** Titles, bylines, labels, rules and separators all start at the 15px gutter. The one inset is the work card's symbol margin: its title and body hang from a second left edge at 72px (15px gutter + 47px grid + 10px gap), so the grid reads as a classification mark before the record. Nothing else floats or centres; the title bar and the paging footer are the only centred text.

**The Open-Between Rule.** Groups are separated by air (20px + a quiet label); entries inside a group are separated by tightness first and a hairline second.

## Elevation & Depth

There are **no shadows, no gradients and no translucency** anywhere in the system. On e-ink a shadow reads as dirt, and a gradient banding as a printing fault. Depth is expressed with three flat devices: a 1px ink border (tiles), a 1px grey rule (hero, stats, list records), and inversion (the black action bar) or a glyph mark (the checked tab's checkmark). Focus is not a glow either: the menu's underline turns from 1px Slate to 5px solid ink on the focused row, and on touch it stays invisible.

### Named Rules
**The Flat Page Rule.** If a surface needs to stand out, it earns it with a border, a rule, or inversion — never with a shadow or a tinted fill.

## Shapes

The form language is a printed page, not a card app. Controls are **square** (0 radius): the primary bar, secondary buttons, the action row, every row. Exactly two rounded forms exist: the two-up content tiles at 7px with a 1px ink border (catalogue cards, not buttons), and the author page's tab strip as a full pill whose ends are half its own height, so the shape scales with the reader's font (see "Tab Strip"). The pill is a switching control — one bar divided into the views it holds — and nothing else may take the rounded form. Nothing has a coloured left border, nothing is clipped at an angle.

Icons are 24×24 vector strokes drawn at 26px, in the same weight as KOReader's own `mdlight` set: the row icons at 26px, the settings gear at 24px, and the category symbols at 14px inside their 22px cells (drawn with a heavier stroke so they keep the same optical weight when shrunk). The AO3 mark is the official OTW artwork at 84px wide (57px tall). These are the only graphics the system allows.

### Named Rules
**The Square Control, Rounded Card Rule.** A thing you press is square, and a thing you read is a card — with one documented exception, the author page's tab strip, which is a single pill. Tabs are the one control that reports which view you are in rather than doing something to the page, so the pill is a selection device, not an action: every button, bar, row and card stays square or 7px, and never round an action bar or square an icon tile.

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
- **Account tile:** the one tile that reflects state. Signed out it is the login symbol and "Sign in" with "Kudos, bookmarks and subscriptions"; signed in it is the user symbol and the reader's AO3 name with "Bookmarks, marked for later, history, subscriptions". Position, size and hint size never change with the session.

### Work Actions (account)
- **Style:** a 2×2 grid of Secondary buttons under the facts table, each half the column width plus a 10px gutter, 2.4× font height (46px). A quiet "Your AO3" group label sits 20px above, 5px below.
- **Labels:** Kudos, Bookmark, Subscribe, Mark for later. They never change position or width with state.
- **State:** KOReader's own checkmark appended after the label ("Bookmark  ✓"), the same mark the tab strip uses. No fill, no grey-out: an action that is on is still a full-contrast action.
- **Signed out:** the same four buttons at full contrast, with one 14px Graphite line beneath: "Sign in to your AO3 account to use these." Read stays the page's only solid bar.

### Account Screen
- **Shape:** a contents page, not a settings form. Bold display name (+6) with "Signed in to AO3" in Meta beneath, a hairline, then a "Lists" label and four native rows (Bookmarks, Marked for later, History, Subscriptions) with right-aligned hints.
- **Order:** the four lists, then an "Author" group with "Works by <name>", then Log out after two gutters of air.
- **Log out:** one full-width outlined Secondary button, not a solid bar — leaving is not the screen's purpose — with 14px Graphite reassurance below ("Saved works stay on this device.").
- **Why rows, not a tab strip:** the four labels do not fit a 600px strip ("Marked for later" alone is wider than a quarter), and a contents page scans vertically.

### Work Cards (signature component)
- **Shape:** no box, no border. A record on paper, closed by a 1px Slate rule inset to the gutter.
- **Top block:** a 2×2 symbol grid in the left margin (22px cells, 3px apart), then the text column: bold 19px title on one line, 2px, a 15px Graphite "by <author>" flush right. The grid sets the block's height, so the title and byline cost no extra air.
- **Record lines:** 5px under the block, the fandoms in 15px Graphite (one line, elided); 2px, the relationships in the same grey; 5px, the tag fold; 5px, the blurb clamped to three lines with 1.3 line spacing and an ellipsis; 5px, the numbers.
- **Numbers:** Words, Chapters and Updated on one line: 15px Slate labels, bold ink values, a Slate "·" between facts. A fact that will not fit is dropped, never wrapped.
- **Behaviour:** the whole card is one tap target; the tag fold is the only nested target and consumes its own tap; the focus underline sits under the record, not under the text.

### Symbol Grid (AO3 required tags)
- **Style:** four square cells in a 2×2 grid, 1px ink border, paper fill, one mark centred in each: the rating letter (G / T / M / E / ?), the warning mark ("!", "!?", "↗", or blank for none), the category's symbol (a 14px drawn SVG), and a check for a finished work (the no-entry mark for a work in progress).
- **Order:** AO3's own strip, read left to right: rating, warnings, category, completion.
- **Ink only:** AO3's symbols are coloured on the website; here they are redrawn as monochrome marks. The shape carries the meaning, because the device has no hue.
- **Behaviour:** the grid appears only when AO3 supplied at least one required tag; a work without them starts at the title.

### Tag Fold
- **Style:** a 1px Slate border, paper fill, 5px padding. Closed: one line of whole tags, then "+N more" when some do not fit, with the section headers' bold Slate "+" in the top-right corner. Open: the full list, up to six lines with an ellipsis, and a "−" in the corner.
- **Behaviour:** tapping the box opens or closes it in place; the work does not open. The menu re-measures the card so the records below move rather than clip. The work details page still carries the complete list.
- **Default:** closed. Settings → **Expanded tags:** can start every list open.

### Settings Screen
- **Style:** one native row: "Expanded tags:" at the left, **On** or **Off** in the 15px Slate right column. No heading, no description, no second control.
- **Behaviour:** the tap stores the choice and the row redraws with its new value; the next listing follows it. The choice lives in `settings/ao3_prefs.lua`, so Log out does not reset it.

### Filter Screen (work listings)
- **Entry:** a funnel at the left end of the native title bar, opposite Close, and only while a work listing is on screen. It is an outline with no applied filters and filled once the listing carries some; it never takes list space. It is hidden on Home, Settings, work details, the author page without its Works shelf, Fandoms, Downloads and the account lists.
- **Root:** two quiet group labels, **Include** and **Exclude**, then one native row per dimension the page offers, with its selected count in the right column. One action row closes the screen: outlined **Clear** beside the screen's solid **Apply filters** bar, or Apply alone when there is nothing to clear. Fourteen dimension rows, both labels and the action row fit one 600×800 page.
- **Dimension:** the title bar names group and dimension ("Include · Fandom"). Each facet is a native row: its name at the left, its work count at the right, and KOReader's checkmark prefixed to the count when chosen, so the states line up in one column and a long tag name never swallows its mark. Rating include is single-select; the other lists are sets.
- **Behaviour:** a tick is pending, not a request. Apply makes the one request and replaces the listing at page 1; paging keeps the applied set; Back out of the dialog drops pending ticks; leaving the listing clears everything.

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
- **Shape:** one pill, inset to the 15px gutter — a single rounded bar with 1px Ink border and Paper fill in every state. Its ends are half its own height, so the form scales with the reader's font instead of pinning a radius. A segmented control is the one form that means "these are views of one thing", and this is the one place the system rounds a control.
- **Dividers:** three hairline Ink rules at the bar's full interior height split it into four equal options (Dashboard / Works / Series / Bookmarks). Four options take three dividers: one bar cut into four, never four floating labels.
- **State:** the current tab is marked with a "✓" after its label, not with a fill, and nothing shifts when the mark moves: the mark is paid for inside its own segment.
- **Height:** the label's own line plus 5px above and below, measured from the bold face, so the bar grows with the reader's font. Each segment is its own tap target; the border and dividers are not.

### Author Page (masthead and shelves)
- **Masthead:** the author's name at Display (bold +6, 1.2), wrapping rather than truncating, then 2px, then a Slate "Author on AO3". All four tabs open on the same masthead: a page whose whole subject is one person says who that is on every shelf, and a pseud is the reader's own name.
- **Navigation:** the strip is the whole of it, so the author page carries no solid bar. The works list is a tab; a bar above the strip would be a second control for the same destination, and dropping it on Works (where it would do nothing) moved every tab 57px. The account screen sets the same precedent: a page whose tabs or rows are its actions needs no primary of its own.
- **Title bar:** the shelf's own name — "Fandoms" on the dashboard, then "Works", "Series", "Bookmarks" — not AO3's "Works by <name>" sentence. The bar names the shelf; the masthead names the author.
- **Count line:** the shelf's total as a bold Slate group label ("6 fandoms", "535 works", "1 bookmark"), two gutters of lead-in above and one small step below, left-pinned so the menu cannot centre it. It drops out when the shelf is empty.
- **Records:** fandoms and series use the two-line index record — bold Title name, ellipsis after two lines, right-aligned 15px ink count on the first line, regular so the bold name stays the only loud thing — rather than a card, because a name and a number is the whole record. Works and bookmarked works are the standard Work Card.
- **Empty shelf:** one Graphite sentence ("No series yet."), no icon, no box. An author with nothing on a shelf is quiet, not broken.
- **Paging:** native rows at the foot of a long shelf ("Next page →") swap that shelf in place and leave the reader on the tab.

### Letter Index (fandom list, signature component)
- **Style:** the whole alphabet as one printed thumb index above the fandom list — three shelves of nine (A–I, J–R, S–Z and `#`), inset to the 15px gutter. Each letter is a square cell: 0.5px Ink border, Paper fill, one bold 19px letter centred, height from the letter's line plus 5px above and below.
- **State:** the open letter is the one inverted cell (Ink fill, Paper letter). In a grid of single glyphs a "✓" would shout louder than the letter it marks, so the index carries the tab strip's checked signal as inversion instead; it is the only block of ink on the screen.
- **Behaviour:** the index is pinned above every page of the open letter (it is not paged away), so switching letters never means paging back to the top. A tap reloads that letter at its first window. Cells scale to a shorter alphabet rather than leaving a ragged last row.

### Menu Rows
- **Style:** native density — 19px title at the left, a right-aligned 15px ink value ("2,523 fandoms", "Author page") that carries its quieter weight rather than a lighter grey — KOReader greys it itself when a row is dimmed, which is the one exception — 1px Slate separator inset to the gutter. No shortcut boxes, no chevrons, no pills.

## Do's and Don'ts

### Do:
- **Do** keep exactly one solid Ink bar per screen and let it name the screen's purpose.
- **Do** align everything to the 15px gutter; the left edge is the system's spine. A work card's symbol margin is the one planned inset.
- **Do** bold the noun and grey the qualifier: title/number bold, byline/blurb/caption regular.
- **Do** use Graphite for sentences inside a record and Slate for chrome; keep contrast survivable in grayscale.
- **Do** build tiles and actions from their content (icon + name + hint; 2.4× font height) so nothing clips.
- **Do** close each work record with a single hairline and keep the blurb to three lines.
- **Do** draw AO3's required-tag symbols in ink, in AO3's order, and let their shapes carry the meaning.
- **Do** keep the tag fold closed by default and let a tap open it in place without leaving the list.
- **Do** keep the settings screen to the one option it owns: label on the left, On/Off on the right.
- **Do** keep the fandom letter index on screen while a letter's list is paged, and let a long fandom name take a second line before it is elided.
- **Do** open every author tab on the same masthead and name each shelf in the title bar, with the strip as the page's whole navigation: one control per destination, and a page whose tabs are its actions needs no bar of its own.
- **Do** let state be a KOReader checkmark and let the account tile keep its place while its symbol and name change with the session.
- **Do** keep the AO3 mark and name as the only masthead identity, and leave the native title bar empty on the landing page.
- **Do** verify every screen in the 600×800 emulator and save the capture under `screenshots/`.

### Don't:
- **Don't** introduce hue, tinted backgrounds, gradients, or a second accent — Refresh stays black-and-white too.
- **Don't** add shadows or lift anything off the page; borders, rules and inversion are the only depth cues.
- **Don't** round anything but the tiles (7px) and the author page's tab strip (a full pill); a rounded button, card or primary bar is not this world's form.
- **Don't** wrap a work card in an outline box or add a cover thumbnail; cards are paper records.
- **Don't** reproduce AO3's coloured rating and warning symbols; the device has no hue and the ink is the design.
- **Don't** put helper text, a heading or a second control on the settings page; the one option is the page.
- **Don't** centre body text, float section labels, or let a label drift away from the gutter.
- **Don't** use more than three blurb lines, a "show more" ellipsis inside a row, or any infinite scroll.
- **Don't** put two primaries on one screen, grey out a secondary action, or make a disabled state by lowering contrast below Graphite.
- **Don't** display the keyboard-shortcut column, breadcrumbs, chips or pagination dots; the catalogue voice has no web furniture.
