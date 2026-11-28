# User guide

Every screen, filter, setting and account action in KO3. For install and
the tour, see the [README](../README.md).

---

## The app

One menu entry opens the whole app. The landing page leads with the AO3 mark
and name (the native title bar is left empty, so the wordmark is the only
identity), with a settings gear at the right edge of that line, then one solid
**Search works** bar. Pinned fandoms follow as a **Favourites** shelf, then the
icon tiles grouped under **Browse**, **Account**, **Library** and **Plugin**.
Each tile keeps its name beside the icon, with a one-line hint underneath. A
**Continue reading** row appears under the Library shelf once a saved work has
been opened; it reopens that copy at the position KOReader stored.

| Tile or bar | What it does |
|---|---|
| **Search works** (solid bar) | Work title, author or keyword |
| **Favourites** | Fandoms pinned by holding their row in the fandom index; a tap opens that fandom's works, a hold on a tile unpins it. Four tiles show at once, with **All favourites** beyond |
| **Latest works** | Newest works across the archive (`/works`) |
| **Fandoms** | Categorized fandom index, shipped with the plugin |
| **Author** | A name searches AO3's people directory: an exact name opens that author, a partial one lists the accounts it matched. A profile URL opens directly |
| **Tag** | A tag name, or paste a full `/tags/.../works` URL |
| **Account** | Sign in to AO3, then your bookmarks, marked-for-later, history and subscriptions |
| **Downloads** | Works already saved on this device |
| **Continue reading** | The saved work opened most recently, when the file is still on the device |
| **Open work** | Paste `https://archiveofourown.org/works/1234567` or just `1234567` |
| **Update KO3** | Check GitHub Releases for a newer version |
| **Report a bug** | Write what happened; optionally attach a diagnostic log |

Fandoms are browsed media category → letter → fandom, the same way AO3's
own index is organised. Choosing a category opens the whole alphabet as one
index above the list: three shelves of nine (A–I, J–R, S–Z and `#`), with the
open letter inverted. The index stays on screen while you page through a
letter, so changing letters never means paging back. A fandom's name may run
to two lines and is then elided; its work count keeps the right-hand column.
Large letters load in local windows of up to 100 fandoms. **Find in this
letter…**, marked with a magnifier, lists every fandom in the letter whose name
contains the term — any part of a name matches, in any case, and the list is
navigable with the same paging rows. A search with no matches says so and leaves
the reader where they were; a search that finds something sits on top of the
letter page, so Back returns to the page being browsed. Tapping a fandom
fetches only its 20-work page. Holding a fandom row pins or unpins it in
**Favourites**: the heart at the start of the row marks a pinned fandom, a
short message confirms the change, and the row repaints in place without
losing your place in the letter. On the AO3 screens, the letter shortcut boxes
are hidden so the text gets the full touchscreen width.

Every search dialog — works, author, tag, fandom letter and **Open work** —
keeps its own ten most recent terms. The clock button beside the field opens
**Recent searches**; tapping a term fills the field for editing before the
search, then the keyboard comes back. The picker is shown with the keyboard
hidden so it can always be tapped.

Each work is one selectable card. Beside the title sits AO3's own required-tag
strip as a 2×2 grid of ink symbols: the rating letter (G/T/M/E), a warning
mark, the category's symbol, and a check for a finished work. The bold title
shares its line with the byline ("by …") when both fit; a title that needs the
whole width keeps its line and the byline drops beneath it. Fandoms and
relationships share one grey line when they fit, and take a line each when
they do not. Then come the tag box, up to three lines of summary, and the
record's numbers — words, chapters and the last update. The tag box stays to
one line, ending in "+N more"; tapping it opens that work's tags in place (up
to six lines) without opening the work. The work's details page still carries
the complete tag list.

**Settings** (the gear beside the AO3 name) has three options. **Expanded
tags:** **On** or **Off** — Off is the default and keeps every tag box to one
line; On starts each listing with the boxes open. **Work cards:** **Modern** or
**Legacy** — Modern is the default, with the AO3 symbols, fandom and
relationships, the tag box and the word/chapter numbers; Legacy is the simpler
card the plugin started with, a bold title, the author and the first three
lines of the summary. **Subscribed works:** **On** or **Off** — whether the
quiet check may also watch the works you follow on AO3 while signed in. All
three choices are stored in `settings/ao3_prefs.lua`, separately from the AO3
session, so Log out does not reset them.

On a work listing — search results, a tag, a fandom, or an author's **Works**
tab — a funnel at the top-left of the title bar, opposite the close button,
opens the filters AO3 already puts on that page. The screen is a printed form,
not a settings list: a **Sort by** tile, a two-column grid of dimension tiles
(rating, archive warning, category, fandom, character, relationship,
additional tags), then the Apply bar. Each tile carries the dimension's name
and one quiet line saying what is chosen — "2 included · 1 excluded",
"1 included", "None yet". Tapping a tile opens its facets with their work
counts and a **Show** switch at the top: **Include** and **Exclude** are the
same dimension page, with the active side ticked, so moving between them never
means going back. Rating is single-select on the include side, as it is on
AO3. Fandom, character, relationship and additional tags also end with
**Search for a tag…**: type at least two characters and AO3's autocomplete
answers with canonical tags to tap. The typed name joins the same pending
selection as the checkboxes (never the network). A 429, a dropped connection
or no network only costs the suggestions; **Add** still takes the typed name,
and Apply is unaffected.

**Sort by** opens the columns AO3's own page offers for that listing — Date
Updated, Kudos and Hits on a tag page, the full set on a search — with a
Direction group only when the source has one (bookmarks are always newest
first). A pick stays pending like a tick. **Apply filters** is the only network
action: it refetches page 1 with the chosen facets and sort together, and
nothing is requested while you tick or sort. The funnel fills while filters or
a non-default sort are active. Paging keeps both, and leaving the listing
clears them. **Default sort** at the foot of the sort page restores the page's
own order.

A keyword search is the exception: AO3 renders no filter sidebar on its results
page, so the funnel is built from the advanced search form's own fixed lists
instead — rating, archive warnings, categories, completion and crossovers —
plus typed tags on both sides, and the full search sort list (Best Match,
Creator, Title, Date Posted, Date Updated, Word Count, Hits, Kudos, Comments,
Bookmarks) with Ascending/Descending. Applying writes bare `work_search[...]`
parameters and keeps the query, so the result stays the search you made.

The same funnel sits on a bookmark listing — your **Bookmarks**, **Marked for
Later** and **History**, or an author's **Bookmarks** shelf. AO3 renders a
bookmark sidebar there instead, so the dialog offers the same tiles plus
**Bookmarker's Tags**, the tags the bookmarker added rather than the work's
own. Applying builds `bookmark_search[...]` parameters instead of
`work_search[...]`; ticking, paging and leaving behave exactly as on a work
listing. Its eight dimensions still fit one 600×800 page. Typed tags work here
too: **Search for a tag…** sits under each tag dimension, work tags go to
`bookmark_search[other_tag_names]`, and a bookmarker's tag goes to
`bookmark_search[other_bookmark_tag_names]`.

**Downloads** lists only files already on the device, so its filter is local:
a search row at the top opens a small input box and narrows the list by title
or work number as you type. Clearing it — or emptying the box — restores every
saved work. It never makes a request, and the storage-folder row stays put.

A quiet check watches the saved works that can still grow. It asks AO3 for the
chapter menu — `/works/<id>/navigate`, a kilobyte or so of chapter titles, not
the work — one work at a time, at most once a day per work, and remembers the
answer in `settings/ao3_prefs.lua`. When it finds a chapter the copy on disk
lacks, the **bell** beside the gear on the landing page takes its filled dot,
the Downloads row says "#51358966 · 2 new", and **Updates** lists the work as
"2 new · 3/7 → 5/7". Nothing downloads until that row is confirmed. The list
also names a work AO3 no longer serves, and its first row, **Check for updates
now**, runs the same light check over every saved WIP on demand.

Signed in, and with **Subscribed works:** on in Settings, the same watch also
follows your **work subscriptions**: it reads the subscriptions list once a
day, a page per tick and up to five pages, then asks each work the same cheap
question. A first check only records where the work stands, so subscribing to
a 150-chapter fic does not raise 150 notifications; after that, a row appears
when chapters are added. The gap clears when you download the work. Series and
user subscriptions are not checked.

Tap a result to drill in; tap a work for its details. The work screen leads
with the title, author and fandom, then **Read** (the solid bar, which
fetches the work and opens it in the KOReader reader) and **Refresh** (the
outlined one), a four-number strip (words, chapters, kudos, hits) and a small
table for rating, warnings, category, status and date. When the saved copy has
fallen behind the live page, a quiet row under those facts says how far — "2
new chapters · 3/7 → 5/7" — and tapping it refreshes. A work that belongs to
one or more series gets a **Series** group below the account actions: each row
reads "Part 2 of Series Name" and opens that series' work listing, so Back
returns to the work. **Summary** and **Tags** stay folded until tapped; a
summary too long for one page is elided and opens in full from **Read full
summary**. Each author's name opens the author page (co-authors each get a row;
Anonymous stays plain text).

**Author** on the landing page takes a profile URL or a name. A name is
searched in AO3's people directory rather than guessed at: a name that is an
exact account or pseud opens that author straight away, and anything shorter
lists every account AO3 matched, with the same paging rows as the other
shelves. The list sits over the landing page, so Back returns there, and the
search row at its top repeats the term and reopens the dialog to refine it.
A pasted profile URL skips the search.

The author page has four tabs in one pill-shaped bar — a rounded strip split
by three hairlines into equal options — and that bar is the page's whole
navigation. Every tab opens on the same masthead — the author's
name, with AO3's "Author on AO3" qualifier in grey beneath it — and a quiet
count line names the shelf above the records:

| Tab | What it shows |
|---|---|
| **Dashboard** (default) | The fandoms the author has written in, with work counts. Tapping one opens that author's works in that fandom (AO3's own author-scoped fandom links). |
| **Works** | All of the author's works as the same card listing. |
| **Series** | The author's series, with work counts, as index rows; tapping one opens the series' works. |
| **Bookmarks** | Works (and series) the author has bookmarked, as cards. |

Each tab is fetched at most once per author visit, so switching back and
forth does not re-request AO3. Back (the footer
arrow, the hardware Back key, the X, or a downward swipe) goes one level up
instead of dropping you into the file manager.

Signing in is optional and only unlocks the personal lists. **Account → Sign
in** takes an AO3 username (or email) and password. The password is posted
once, directly to AO3, and is never written to disk. What is kept is AO3's own
session cookie (`_otwarchive_session`, plus `remember_user_token` when AO3 sets
it) in `settings/ao3.lua`; **Log out** removes that file and its backup.
Cloudflare cookies are never stored or replayed. Sign-in is three ordinary
requests: fetch AO3's JSON CSRF token, submit the form, and load one page to
confirm the logged-in greeting. A redirect alone is not treated as success,
because the anonymous form cookie would otherwise look like a session.

Two details matter for AO3's edge. The login page (`/users/login`) is
challenged for this client, so the token comes from
`/token_dispenser.json` instead. The request also uses the Firefox header set
that AO3 accepts; a specific Chrome UA is refused with `cf-mitigated:
challenge` on the same request. AO3 rotates the session cookie during
sign-in, sometimes alongside a deletion cookie, so an expired cookie is
ignored rather than allowed to overwrite the live session.

After sign-in, **Account** lists:

| Row | Opens |
|---|---|
| **Bookmarks** | Works and series you bookmarked |
| **Marked for Later** | Your reading queue |
| **History** | Works you opened |
| **Subscriptions** | Works, series and authors you follow |
| **Works by you** | Your own author page, with the usual tabs |
| **Log out** | Clears the session cookie |

Each row fetches one page on tap and uses the same work cards as the rest of
the app. If AO3 stops accepting the session, the plugin says so, clears the
cookie and returns Home to **Sign in** instead of showing an empty list.

A signed-in work page can also leave kudos, bookmark the work, subscribe to
it, and add it to Marked for Later. These are the website's own form posts,
sent only when you tap them; nothing is posted on startup or in the background.
Loading the work page once supplies the current state (bookmarked, subscribed,
on the read-later list) and the pseud or subscription id needed to undo the
action. The form token comes from `/token_dispenser.json` and is cached until
the session cookie changes; the tokens embedded in a work page belong to their
forms, so they are not reused for a different action. A form post is never
retried, so a 403 cannot leave two kudos or two bookmarks behind.

The first read downloads the whole work (usually 200 KB–1 MB); after that the
cached copy opens instantly, offline. **Refresh** downloads and validates the
latest version before replacing the saved copy, so a failed request leaves
the offline book available.

A saved work in progress can be checked without downloading it again:
**Check for updates** in the Downloads actions makes one work-page request,
compares the saved chapter count with AO3's live one, and either says
"Up to date · 3/7" or offers **Get new chapters** with "2 new chapters ·
3/7 → 5/7" before replacing the copy. The comparison reads the saved file's
own preface, so opening Work details costs no request at all. Finished
multi-chapter saves and one-shots keep only **Refresh from AO3**.

Inside the reader, a work opened from AO3 has three ways back to the screen
you left, instead of KOReader's file manager:

- **Back to KO3** at the bottom of the reader menu's Navigation tab, on its
  first page.
- The Back key / Back gesture (its usual "go to file browser" exit is
  redirected for AO3 works).
- **Back to KO3** in the end-of-the-work dialog, alongside the standard
  choices. The stock **File browser** button still opens the file manager.

The table of contents is the work's chapters only. AO3's download file adds
hidden "Preface" and title headings for Calibre, which crengine turned into
two collapsed top-level entries. Those are filtered out and the chapter list
is flattened, so the index opens fully expanded and contains no metadata
heading.

## Updating KO3

**No computer is needed after the first install.** Open
**Tools → KO3 → Update KO3**:

1. It asks GitHub for the latest release and shows the current version, the
   new version and the release notes (`manifest.json` is the fallback).
2. **Update** downloads the versioned zip, verifies its SHA-256, unpacks it
   next to the installed copy, and checks that the archive really contains
   the plugin and the version it claims.
3. It swaps the new tree in only after all of that passes, then offers to
   restart KOReader. The running code is never modified mid-flight.

The previous version is kept as `ao3.koplugin.bak`; **Restore previous
version** appears on the home screen after an update and swaps it back.
Updates are ~2.7 MB and come straight from `github.com`, so no Storefront
or other plugin is required.

**KO3 also looks for a release on its own.** While the plugin is open, a
one-shot timer re-arms itself and asks GitHub at most once a day; offline, or
after a failed request, it waits fifteen minutes and tries again. A check
downloads nothing and draws nothing — it only notes the newer version. The
prompt then appears the next time you are in the plugin (the landing page, or
the screen **Back to KO3** returns you to), never over a book you are reading.
It offers **Update**, **Remind later** (ask again in a day), **Dismiss**
(never ask for that release again; the next one does) and **Changelog** (the
release notes in a native scrollable viewer, so long ones page). The check can
run while
a work opened from the plugin is in the reader, but its result stays silent
until the plugin is the visible screen. Closing the plugin cancels the timer
and opening it again re-arms it, so no network work happens once you leave.
The last check time and a dismissed version live in `settings/ao3_prefs.lua`
with the display choices, and a failed check is only written to the log.

GitHub serves release assets from its asset CDN
(`release-assets.githubusercontent.com`), a different host from the one that
answers the update check. Some Kindle networks reach the API but not that
host; the download then stalls until it times out. KO3 follows the redirect
itself and retries a stalled transfer from the bytes already saved. If the
CDN still cannot be reached, it falls back to the tag's source archive on
`codeload.github.com`, which carries the same `ao3.koplugin` tree; the staged
`_meta.lua` version is checked before installing.

Because the fallback lives in the new code, a device whose current updater
cannot reach the asset CDN needs this version copied once by hand (the zip on
the release page is on `github.com`). Later updates then work in place.

## Reporting a bug

**Tools → KO3 → Report a bug** opens a text field. After you describe what
happened, a consent dialog asks whether to attach the diagnostic log and
states that the report and log are sent to the project's issue tracker, and
that the log is used only to find the cause. Choosing **Without log** sends
the description alone.

Reports become public GitHub issues, so do not put personal details in the
description.

**Attach log is the last step.** The report is POSTed to the KO3 relay
(`relay/worker.js`, a small Cloudflare Worker), which files the issue with a
fine-grained GitHub token that never ships in the plugin. The relay accepts
10 reports per IP per day. No GitHub account is needed.

If the relay cannot be reached, the report is still saved on the device as
`koreader/ao3/reports/bug-<timestamp>/report.md` plus `log.txt`, ready to
attach to [a new issue](https://github.com/hemil2005/KO3/issues/new).

What the log contains:

- plugin version, KOReader revision, device model, screen size and time;
- each request's host and path with its HTTP status, download outcomes and
  error text.

What it never contains: your AO3 password (the plugin stores none), cookies,
search text, work titles or work text. Query strings and fragments are
stripped before anything is written.

The log itself lives at `koreader/ao3/logs/ao3.log`, is capped at 256 KB
(one rotation to `ao3.log.1`) and is only read when you create a report.

`settings/ao3_report_token` (a fine-grained token with **Issues: write**)
bypasses the relay for the maintainer's device. The relay's deployment and
token rotation are documented in `relay/README.md`.
