--[[--
The author page: one author's page, and the parsers behind it.

The real author page has Dashboard / Works / Series / Bookmarks tabs (this
plugin skips Profile, which has no reader value). The Dashboard tab groups
the author's works by fandom; tapping a fandom opens that author's works in
that fandom, using AO3's own author-scoped `?fandom_id=` links.

The screen follows the catalogue's own shape (DESIGN.md): a masthead naming
the author, the pill of four tabs, then a quiet count line and the records.
The four tabs are the same screen with a different shelf under them, so every
tab keeps the masthead — you always know whose page you are reading.

The strip is the page's only navigation. A solid "All works" bar was tried
above it and cut: the works list is a tab, so the bar and the strip were two
controls for one destination, and it had to be dropped on Works (where it
would do nothing) which moved the strip 57px and shifted every tab under the
reader's finger. One control per destination beats a primary the page does
not need the way the account page does not need one.

Records are the currency of the rest of the system rather than this screen's
invention: a fandom and a series are the letter index's record (bold name of
one or two lines, count in the right-hand column), and a bookmarked work is
the same card the work lists paint.

Parsers here read the exact live AO3 markup (captured 2026-11-23):

    Dashboard  div.fandom.listbox.group > ol.index.group li a[?fandom_id=]
    Series     li.series.blurb.group, h4.heading a -> /series/<id>, dl.stats
    Bookmarks  li.bookmark.blurb.group (work or series bookmark)
    Works      li.work.blurb.group (shared with Ao3:parseListing)
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local Screen = require("device").screen
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local htmlparser = require("htmlparser")
local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local SOURCE = debug.getinfo(1, "S").source:sub(2)
local Uikit = dofile((SOURCE:gsub("authorpage%.lua$", "uikit.lua")))

local AuthorPage = {}

local BASE_URL = "https://archiveofourown.org"

-- The two air steps the catalogue uses everywhere: a group starts two gutters
-- above its label, and a label sits one small step above its records.
local GROUP_GAP = Size.padding.large * 2

-- Single-line height for a face, so a control is measured from the text it
-- actually holds instead of from a font-size multiplier.
local function lineHeight(face, bold)
    if TextWidget.getTextHeight then
        local ok, h = pcall(TextWidget.getTextHeight, "Ag", face, bold)
        if ok and h then return h end
    end
    local probe = TextWidget:new{ text = "Ag", face = face, bold = bold }
    local h = probe:getSize().h
    if probe.free then probe:free() end
    return h
end

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "1 work" / "12 works". AO3 gives counts as strings, sometimes with a
-- thousands separator, so only the exact "1" takes the singular.
local function counted(count, singular, plural)
    local text = trim(tostring(count or ""))
    if text == "" then return nil end
    if text == "1" then return singular end
    return T(plural, text)
end

local function plain(node)
    if not node then return "" end
    local s = node:getcontent() or ""
    s = s:gsub("<br%s*/?>", " "):gsub("</p%s*>", " ")
    s = util.htmlToPlainTextIfHtml(s)
    s = util.htmlEntitiesToUtf8(s)
    return trim(s:gsub("%s+", " "))
end

local function first(nodes)
    if not nodes then return nil end
    for _, node in ipairs(nodes) do
        return node
    end
end

local function absoluteUrl(url)
    if not url or url == "" then return nil end
    if url:match("^https?://") then return url end
    return BASE_URL .. (url:sub(1, 1) == "/" and "" or "/") .. url
end

-- `label` is the strip's own word (AO3's tab names, so a reader who knows the
-- site recognises them); `title` names the shelf the tab holds, and is the one
-- line the native title bar carries.
AuthorPage.TABS = {
    { id = "dashboard", label = _("Dashboard"), title = _("Fandoms") },
    { id = "works", label = _("Works"), title = _("Works") },
    { id = "series", label = _("Series"), title = _("Series") },
    { id = "bookmarks", label = _("Bookmarks"), title = _("Bookmarks") },
}

local function tabEntry(tab_id)
    for _, tab in ipairs(AuthorPage.TABS) do
        if tab.id == tab_id then return tab end
    end
end

-- The native title bar's one line. The masthead already names the author and
-- the strip already shows the tab, so the bar names the shelf and nothing else.
function AuthorPage.tabTitle(tab_id)
    local tab = tabEntry(tab_id)
    return tab and tab.title or _("Author")
end

-- `profile` is the author's page without a sub-page, e.g.
-- https://archiveofourown.org/users/foo or /users/foo/pseuds/bar.
function AuthorPage.profileUrl(profile)
    if not profile or profile == "" then return nil end
    local url = (profile:gsub("/+$", ""))
    url = url:gsub("/works$", ""):gsub("/series$", ""):gsub("/bookmarks$", "")
    return url
end

function AuthorPage.tabUrl(profile, tab_id)
    local base = AuthorPage.profileUrl(profile)
    if not base then return nil end
    if tab_id == "works" or tab_id == "dashboard" then
        return base .. "/works"
    elseif tab_id == "series" then
        return base .. "/series"
    elseif tab_id == "bookmarks" then
        return base .. "/bookmarks"
    end
    return nil
end

-- The tab strip (DESIGN.md, "Tab Strip"): the four tabs as one pill — a single
-- rounded bar inset to the gutter, divided by three hairline ink rules, a bold
-- label in each equal segment, and the current tab marked with KOReader's own
-- checkmark rather than a fill.
--
-- It replaced a full-bleed band of four bordered cells. Edge to edge, that band
-- drew two long rules across the page and read as a table on a screen that
-- already has one; one rounded bar with internal dividers says "four views of
-- one thing" at a glance, which is what tabs are. The radius is half the bar's
-- own height, so the shape scales with the reader's font instead of pinning a
-- number of pixels.
--
-- Native Buttons were the first answer here: they carry their own padding and
-- a heavier border, and they cannot keep the segments exactly equal once a
-- checkmark widens one label. These segments are drawn with the same widgets
-- the rest of the designed screens use, and each is one tap target.
function AuthorPage.tabStrip(current, on_select, width, font_size)
    width = width or Screen:getWidth()
    font_size = font_size or 19
    local face = Font:getFace("smallinfofont", font_size)
    local border = Size.border.thin
    local count = #AuthorPage.TABS
    local inner_w = math.max(1, width - 2 * border)
    local inner_h = math.max(1, lineHeight(face, true) + 2 * Size.span.vertical_large)
    -- A pill's ends are half its own height, borders included.
    local radius = math.floor((inner_h + 2 * border) / 2)
    local segment_w = math.floor((inner_w - (count - 1) * border) / count)

    local strip = HorizontalGroup:new{ align = "center" }
    local segments = {}
    local left = inner_w
    for i, tab in ipairs(AuthorPage.TABS) do
        if i > 1 then
            -- The divider between two options: hairline ink at the pill's full
            -- interior height, so four labels read as one bar divided in four.
            strip[#strip + 1] = LineWidget:new{
                dimen = Geom:new{ w = border, h = inner_h },
                background = Blitbuffer.COLOR_BLACK,
            }
            left = left - border
        end
        -- The last segment takes the sub-pixel remainder so the bar closes
        -- flush inside its own border.
        local this_w = i == count and left or segment_w
        left = left - this_w

        local active = tab.id == current
        local label = TextWidget:new{
            text = active and (tab.label .. "  \u{2713}") or tab.label,
            face = face,
            bold = true,
            max_width = math.max(1, this_w - 2 * Size.span.horizontal_small),
        }
        local area = Uikit.tapArea(
            CenterContainer:new{
                dimen = Geom:new{ w = this_w, h = inner_h },
                label,
            },
            this_w, inner_h,
            function() on_select(tab.id) end)
        area.tab_id = tab.id
        segments[i] = area
        strip[#strip + 1] = area
    end

    local frame = FrameContainer:new{
        bordersize = border,
        -- The system's one pill (DESIGN.md, "Shapes"): tabs are a control for
        -- switching views, so they earn the rounded form nothing else may take.
        radius = radius,
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        padding = 0,
        margin = 0,
        strip,
    }
    frame.segments = segments
    return frame
end

-- The masthead: the author's name at display size, one honest quiet line
-- beneath it, and air before whatever the tab puts next. It wraps rather than
-- truncating — a long pseud is the reader's own name.
function AuthorPage.identity(name, width, font_size)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = TextBoxWidget:new{
        text = (name and name ~= "") and name or _("Author"),
        face = Font:getFace("smallinfofont", font_size + 6),
        bold = true,
        width = width,
        height_adjust = true,
        alignment = "left",
    }
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    group[#group + 1] = TextWidget:new{
        text = _("Author on AO3"),
        face = Font:getFace("smallinfofont", font_size - 4),
        fgcolor = Uikit.SECONDARY,
        max_width = width,
    }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.large }
    return group
end

-- A quiet group label carrying the shelf's size ("6 fandoms", "12 works"),
-- pinned to the gutter so the menu cannot centre it.
function AuthorPage.count_label(text, width, font_size)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = GROUP_GAP }
    group[#group + 1] = Uikit.label(text, width, font_size)
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = group:getSize().h },
        group,
    }
end

-- An empty shelf says so in one grey sentence. It keeps the group's air, so a
-- tab with nothing on it is quiet rather than broken-looking.
function AuthorPage.empty(text, width, font_size)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = GROUP_GAP }
    group[#group + 1] = TextBoxWidget:new{
        text = text,
        face = Font:getFace("smallinfofont", font_size - 2),
        fgcolor = Blitbuffer.COLOR_GRAY_6,
        width = width,
        height_adjust = true,
        alignment = "left",
    }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    return group
end

-- Every tab is the same screen with a different shelf under it. `o` carries
-- the session's data and the callbacks; `work_row(work)` is the plugin's work
-- card, so a bookmarked work stays the card the listings paint.
function AuthorPage.build(o)
    local width = o.width
    local font_size = o.font_size
    local tab = o.tab or "dashboard"
    local data = o.data or { items = {} }
    local items = data.items or {}
    local rows = {}

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(
            AuthorPage.identity(o.name, width, font_size)),
        role = "author_identity",
    }

    rows[#rows + 1] = {
        -- A pill inset to the gutter, not a full-bleed band: its rounded ends
        -- need paper beside them to read as rounded at all.
        ao3_tabs = AuthorPage.tabStrip(tab, o.on_tab, width, font_size),
        role = "author_tabs",
    }

    local count_text
    local empty_text
    if tab == "dashboard" then
        count_text = counted(#items, _("1 fandom"), _("%1 fandoms"))
        empty_text = _("No fandoms listed.")
    elseif tab == "works" then
        count_text = counted(data.count, _("1 work"), _("%1 works"))
        empty_text = _("No works found.")
    elseif tab == "series" then
        count_text = counted(data.count, _("1 series"), _("%1 series"))
        empty_text = _("No series.")
    else
        count_text = counted(data.count, _("1 bookmark"), _("%1 bookmarks"))
        empty_text = _("No bookmarks.")
    end

    if #items == 0 then
        rows[#rows + 1] = {
            ao3_static = Uikit.padded(
                AuthorPage.empty(empty_text, width, font_size)),
            role = "author_empty",
        }
        return rows
    end

    if count_text then
        rows[#rows + 1] = {
            ao3_static = Uikit.padded(
                AuthorPage.count_label(count_text, width, font_size)),
            role = "author_count",
            -- A page must not end on a count whose records are overleaf.
            keep_with_next = true,
        }
    end

    -- Translate outside the loop: `for _, item` shadows gettext `_`.
    local works_singular = _("1 work")
    local works_plural = _("%1 works")
    for _, item in ipairs(items) do
        if tab == "dashboard" then
            rows[#rows + 1] = {
                text = item.name,
                mandatory = counted(item.count, works_singular, works_plural),
                ao3_fandom = true,
                action = function() o.on_listing(item.url, item.name) end,
                role = "author_fandom",
            }
        elseif tab == "series" or item.kind == "series" then
            rows[#rows + 1] = {
                text = item.title,
                mandatory = counted(item.works, works_singular, works_plural),
                ao3_series = true,
                action = function() o.on_listing(item.url, item.title) end,
                role = "author_series",
            }
        else
            rows[#rows + 1] = o.work_row(item)
        end
    end

    -- Paging is AO3's own next/previous link, and it stays a native row: it is
    -- navigation, not a record.
    if data.next_url then
        rows[#rows + 1] = {
            text = _("Next page →"),
            action = function() o.on_page(data.next_url) end,
            role = "author_next",
        }
    end
    if data.prev_url then
        rows[#rows + 1] = {
            text = _("← Previous page"),
            action = function() o.on_page(data.prev_url) end,
            role = "author_prev",
        }
    end

    return rows
end

-- Shared work-blurb parser. Work listings, search results and bookmarks all
-- carry the same header/stats markup, so one parser serves all three.
function AuthorPage.parseWorkNode(node)
    local title_link
    for _, a in ipairs(node:select("h4.heading a")) do
        local href = a.attributes.href or ""
        local is_work_link = href:match("^/works/%d+")
            or href:match("^https?://[^/]+/works/%d+")
        if is_work_link and a.attributes.rel ~= "author" then
            title_link = a
            break
        end
    end

    local id = node.id and node.id:match("work_(%d+)")
    if not id and title_link then
        id = (title_link.attributes.href or ""):match("/works/(%d+)")
    end
    if not id then return nil end

    local authors, author_urls = {}, {}
    for _, a in ipairs(node:select("h4.heading a[rel='author']")) do
        local name = plain(a)
        if name ~= "" then
            table.insert(authors, name)
            local href = a.attributes.href or ""
            if href ~= "" then table.insert(author_urls, href) end
        end
    end

    local fandoms = {}
    for _, a in ipairs(node:select("h5.fandoms a.tag")) do
        local name = plain(a)
        if name ~= "" then table.insert(fandoms, name) end
    end

    -- The tags list mixes four kinds in one `ul`; the `li` class says which.
    -- Warnings and relationships already have a place of their own on a work
    -- card (the symbol grid and the ships line), so the card's tag box keeps
    -- the characters and freeform tags without repeating them.
    local tags, tag_list, relationships = {}, {}, {}
    local tag_kinds = { warnings = true, relationships = true,
        characters = true, freeforms = true }
    for _, li in ipairs(node:select("ul.tags.commas li")) do
        local a = first(li:select("a.tag"))
        local name = a and plain(a) or ""
        if name ~= "" then
            table.insert(tags, name)
            local kind
            for _, class_name in ipairs(li.classes or {}) do
                if tag_kinds[class_name] then kind = class_name break end
            end
            if kind == "relationships" then
                table.insert(relationships, name)
            elseif kind ~= "warnings" then
                table.insert(tag_list, name)
            end
        end
    end

    local function stat(class_name)
        return plain(first(node:select("dd." .. class_name)))
    end

    -- The required-tags strip carries the symbol state in its classes
    -- (`rating-teen`, `warning-choosenotto`, `category-slash`, ...). The
    -- human text is still read for the facts table.
    local function requiredKey(prefix)
        for _, span in ipairs(node:select("ul.required-tags span")) do
            for _, class_name in ipairs(span.classes or {}) do
                if class_name:sub(1, #prefix + 1) == prefix .. "-" then
                    return class_name
                end
            end
        end
    end

    local rating = plain(first(node:select("ul.required-tags span.rating")))
    local warnings = plain(first(node:select("ul.required-tags span.warnings")))
    local category = plain(first(node:select("ul.required-tags span.category")))
    local complete = first(node:select("ul.required-tags span.complete-yes")) and _("Complete")
        or (first(node:select("ul.required-tags span.complete-no")) and _("In progress") or "")

    return {
        id = id,
        title = title_link and plain(title_link) or T(_("Work %1"), id),
        authors = #authors > 0 and table.concat(authors, ", ") or _("Anonymous"),
        author_names = #authors > 0 and authors or nil,
        author_urls = #author_urls > 0 and author_urls or nil,
        fandoms = table.concat(fandoms, ", "),
        tags = table.concat(tags, ", "),
        tag_list = #tag_list > 0 and tag_list or nil,
        relationships = table.concat(relationships, " · "),
        relationship_list = #relationships > 0 and relationships or nil,
        summary = plain(first(node:select("blockquote.summary"))),
        rating = rating,
        rating_key = requiredKey("rating"),
        warnings = warnings,
        warning_key = requiredKey("warning"),
        category = category,
        category_key = requiredKey("category"),
        complete = complete,
        complete_key = first(node:select("ul.required-tags span.complete-yes")) and "complete-yes"
            or (first(node:select("ul.required-tags span.complete-no")) and "complete-no" or nil),
        updated = plain(first(node:select("p.datetime"))),
        words = stat("words"),
        chapters = stat("chapters"),
        comments = stat("comments"),
        kudos = stat("kudos"),
        bookmarks = stat("bookmarks"),
        hits = stat("hits"),
    }
end

--[[--
AO3's download file itself contains the extra headings this clean-up removes.
It hides `h2.toc-heading` elements for Calibre and puts the work title in an
`h1`, so crengine builds a two-level TOC:

    Preface
    <work title>
      Chapter 1
      Chapter 2

That is what the reader showed as two entries with subentries, collapsed by
default. The useful index is just the chapters, so drop the Preface entry and
the work-title wrapper, then flatten what is left. A flat TOC has no
subentries, so KOReader shows every chapter without expanding anything.
]]--
function AuthorPage.cleanToc(toc)
    if type(toc) ~= "table" then return toc end
    -- AO3 marks the metadata block with hidden headings for Calibre. Depending
    -- on the work they reach crengine as "Preface", nothing at all, or just a
    -- dash, so treat all three as the same metadata entry.
    local function is_metadata_title(label)
        local text = trim(label)
        if text == "" then return true end
        if text:lower() == "preface" then return true end
        return text:match("^[%-–—%s%.]+$") ~= nil
    end

    local cleaned = {}
    for _, item in ipairs(toc) do
        if type(item) == "table" then
            if not is_metadata_title(item.title or "") then
                local copy = {}
                for key, value in pairs(item) do copy[key] = value end
                cleaned[#cleaned + 1] = copy
            end
        end
    end

    -- After the Preface, the first entry that has children is the work title
    -- wrapping the chapter list. Removing it promotes the chapters to the top
    -- level. A single-entry TOC (a one-chapter work with no chapter heading)
    -- has no children, so its title is kept.
    if #cleaned >= 2 and (cleaned[2].depth or 0) > (cleaned[1].depth or 0) then
        table.remove(cleaned, 1)
    end

    for _, item in ipairs(cleaned) do
        item.depth = 0
    end
    return cleaned
end

-- Works and bookmark lists use pagy pagination; the series list still uses
-- the legacy markup. Accept both.
function AuthorPage.pagination(root)
    local next_link = first(root:select("ol.pagination a[rel='next']"))
        or first(root:select("ol.pagination li.next a"))
    local prev_link = first(root:select("ol.pagination a[rel='prev']"))
        or first(root:select("ol.pagination li.prev a"))
    return {
        next_url = next_link and absoluteUrl(util.htmlEntitiesToUtf8(next_link.attributes.href or "")),
        prev_url = prev_link and absoluteUrl(util.htmlEntitiesToUtf8(prev_link.attributes.href or "")),
    }
end

-- Dashboard: the fandom listbox on /users/<name>?expand_fandoms=true.
-- Counts are the number of the author's works in that fandom.
function AuthorPage.parseFandoms(html)
    local ok, root = pcall(htmlparser.parse, html, 5000)
    if not ok or not root then
        return nil, _("Could not parse the AO3 page.")
    end
    local items = {}
    local box = first(root:select("div.fandom.listbox.group"))
    if box then
        for _, li in ipairs(box:select("ol.index.group li")) do
            local a = first(li:select("a"))
            local href = a and a.attributes.href or ""
            if a and href:find("fandom_id=", 1, true) then
                local name = plain(a)
                if name ~= "" then
                    local count = plain(li):match("%(([%d,]+)%)%s*$")
                    items[#items + 1] = { name = name, url = href, count = count }
                end
            end
        end
    end
    return { items = items }
end

function AuthorPage.parseSeries(html)
    local ok, root = pcall(htmlparser.parse, html, 5000)
    if not ok or not root then
        return nil, _("Could not parse the AO3 page.")
    end
    local items = {}
    for _, li in ipairs(root:select("li.series.blurb")) do
        local link = first(li:select("h4.heading a"))
        local href = link and link.attributes.href or ""
        local id = (li.id and li.id:match("series_(%d+)")) or href:match("/series/(%d+)")
        if id then
            local function stat(class_name)
                return plain(first(li:select("dd." .. class_name)))
            end
            items[#items + 1] = {
                kind = "series",
                id = id,
                title = plain(link),
                url = "/series/" .. id,
                words = stat("words"),
                works = stat("works"),
                bookmarks = stat("bookmarks"),
                updated = plain(first(li:select("p.datetime"))),
            }
        end
    end
    local count
    for _, h in ipairs(root:select("h2.heading")) do
        count = plain(h):match("([%d,]+) Series")
        if count then break end
    end
    local pag = AuthorPage.pagination(root)
    return { items = items, count = count, next_url = pag.next_url, prev_url = pag.prev_url }
end

-- Bookmarks carry the bookmarked work's header directly, so the shared work
-- parser reads them. Series bookmarks (series-NNN) become series entries.
-- Subscriptions can point at a work, a series or a user. AO3 uses one
-- `li.subscription` per entry; the first heading link is the subscribed
-- thing. Work entries often carry the usual blurb header, so the shared work
-- parser can fill title/author/summary when it can.
function AuthorPage.parseSubscriptions(html)
    local ok, root = pcall(htmlparser.parse, html, 5000)
    if not ok or not root then
        return nil, _("Could not parse the AO3 page.")
    end
    local items = {}
    for _, li in ipairs(root:select("li.subscription")) do
        local link
        for _, heading in ipairs({ "h4.heading", "h3.heading", "h5.heading" }) do
            for _, a in ipairs(li:select(heading .. " a")) do
                local href = a.attributes.href or ""
                if a.attributes.rel ~= "author"
                    and (href:match("/works/%d+") or href:match("/series/%d+")
                        or href:match("/users/")) then
                    link = a
                    break
                end
            end
            if link then break end
        end

        if link then
            local href = link.attributes.href or ""
            local title = plain(link)
            local work_id = href:match("/works/(%d+)")
            local series_id = href:match("/series/(%d+)")
            local user = href:match("/users/([^/%?#\"]+)")
            local subscribed = plain(first(li:select("p.datetime")))
                or plain(first(li:select("dd.subscribed")))

            if work_id then
                local work = AuthorPage.parseWorkNode(li) or {}
                -- Subscription entries may keep the author link in h5 rather
                -- than the usual h4, so fill it in from any rel=author link.
                if not work.author_names then
                    local names, urls = {}, {}
                    for _, a in ipairs(li:select("a[rel='author']")) do
                        local name = plain(a)
                        if name ~= "" then
                            names[#names + 1] = name
                            local href = a.attributes.href or ""
                            if href ~= "" then urls[#urls + 1] = href end
                        end
                    end
                    if #names > 0 then
                        work.authors = table.concat(names, ", ")
                        work.author_names = names
                        work.author_urls = #urls > 0 and urls or nil
                    end
                end
                work.kind = "work"
                work.id = work_id
                work.title = title ~= "" and title or work.title
                items[#items + 1] = work
            elseif series_id then
                items[#items + 1] = {
                    kind = "series",
                    id = series_id,
                    title = title,
                    url = "/series/" .. series_id,
                    updated = subscribed,
                }
            elseif user then
                items[#items + 1] = {
                    kind = "user",
                    name = util.htmlEntitiesToUtf8(user),
                    title = title ~= "" and title or user,
                    subscribed = subscribed,
                }
            end
        end
    end

    local count
    for _, h in ipairs(root:select("h2.heading")) do
        count = plain(h):match("([%d,]+) Subscriptions?")
        if count then break end
    end
    local pag = AuthorPage.pagination(root)
    return { items = items, count = count, next_url = pag.next_url, prev_url = pag.prev_url }
end

-- AO3's own sort controls, read from the page already in hand. Listings carry
-- `select[name="<param>[sort_column]"]` and sometimes a matching
-- `sort_direction` select. The options are AO3's to choose (tag and fandom
-- sidebars print a different subset from the full search form), so nothing is
-- hard-coded here; the selected option, or the first one when AO3 marks none,
-- is the page's own current sort.
function AuthorPage.parseSortOptions(root, param)
    if not root then return nil end

    local function readSelect(name)
        local select = first(root:select('select[name="' .. name .. '"]'))
        if not select then return nil end
        local options, chosen = {}, nil
        for _, option in ipairs(select:select("option")) do
            local attrs = option.attributes or {}
            local value = attrs.value
            if value == nil then value = trim(plain(option)) end
            local label = trim(plain(option))
            options[#options + 1] = {
                value = value,
                label = label ~= "" and label or value,
            }
            if attrs.selected ~= nil then chosen = value end
        end
        if #options == 0 then return nil end
        return options, chosen or options[1].value
    end

    for _, candidate in ipairs(param and { param }
            or { "work_search", "bookmark_search" }) do
        local columns, column = readSelect(candidate .. "[sort_column]")
        if columns then
            local directions, direction =
                readSelect(candidate .. "[sort_direction]")
            return {
                param = candidate,
                columns = columns,
                directions = directions,
                column = column,
                direction = direction,
                -- The page's own default, so "Default sort" can restore it.
                default_column = column,
                default_direction = direction,
            }
        end
    end
end

-- `facet_parser` is optional: main.lua passes its bookmark-sidebar parser so
-- the same page parse yields the listing and its facets, with no second read.
function AuthorPage.parseBookmarks(html, facet_parser)
    local ok, root = pcall(htmlparser.parse, html, 5000)
    if not ok or not root then
        return nil, _("Could not parse the AO3 page.")
    end
    local items = {}
    for _, li in ipairs(root:select("li.bookmark.blurb")) do
        local series_link, work_link
        for _, a in ipairs(li:select("h4.heading a")) do
            local href = a.attributes.href or ""
            if not series_link and href:match("/series/%d+") then
                series_link = a
            elseif not work_link and href:match("/works/%d+")
                and a.attributes.rel ~= "author" then
                work_link = a
            end
        end
        if work_link then
            local work = AuthorPage.parseWorkNode(li)
            if work then
                work.kind = "work"
                items[#items + 1] = work
            end
        elseif series_link then
            local id = (series_link.attributes.href or ""):match("/series/(%d+)")
            if id then
                items[#items + 1] = {
                    kind = "series",
                    id = id,
                    title = plain(series_link),
                    url = "/series/" .. id,
                    works = plain(first(li:select("dd.works"))),
                    updated = plain(first(li:select("p.datetime"))),
                }
            end
        end
    end
    local count
    for _, h in ipairs(root:select("h2.heading")) do
        count = plain(h):match("([%d,]+) Bookmarks? by")
        if count then break end
    end
    local pag = AuthorPage.pagination(root)
    local result = {
        items = items,
        count = count,
        next_url = pag.next_url,
        prev_url = pag.prev_url,
        -- The bookmark sidebar's own sort select, so the filter screen can
        -- offer it without a second request.
        sort = AuthorPage.parseSortOptions(root, "bookmark_search"),
    }
    if facet_parser then
        result.bookmark_facets = facet_parser(root) or {}
    end
    return result
end

return AuthorPage
