--[[--
Author page tabs and parsers for the AO3 browser.

The real author page has Dashboard / Works / Series / Bookmarks tabs (this
plugin skips Profile, which has no reader value). The Dashboard tab groups
the author's works by fandom; tapping a fandom opens that author's works in
that fandom, using AO3's own author-scoped `?fandom_id=` links.

The tab strip is a horizontal row of native Buttons. There is no TabBar
widget in older KOReader builds, and Buttons are long-stable everywhere,
so the strip works on the same range of devices as the rest of the plugin.
The active tab is marked with the native checkmark.

Parsers here read the exact live AO3 markup (captured 2026-11-23):

    Dashboard  div.fandom.listbox.group > ol.index.group li a[?fandom_id=]
    Series     li.series.blurb.group, h4.heading a -> /series/<id>, dl.stats
    Bookmarks  li.bookmark.blurb.group (work or series bookmark)
    Works      li.work.blurb.group (shared with Ao3:parseListing)
]]

local Button = require("ui/widget/button")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local Size = require("ui/size")
local Screen = require("device").screen
local htmlparser = require("htmlparser")
local util = require("util")
local _ = require("gettext")

local AuthorPage = {}

local BASE_URL = "https://archiveofourown.org"

local function trim(s)
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
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

AuthorPage.TABS = {
    { id = "dashboard", label = _("Dashboard") },
    { id = "works", label = _("Works") },
    { id = "series", label = _("Series") },
    { id = "bookmarks", label = _("Bookmarks") },
}

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

-- One row of tabs, each the same width, with the current tab checked.
function AuthorPage.tabStrip(current, on_select, width)
    local group = HorizontalGroup:new{}
    local count = #AuthorPage.TABS
    local tab_width = math.floor((width or Screen:getWidth()) / count)
    for _, tab in ipairs(AuthorPage.TABS) do
        group[#group + 1] = Button:new{
            text = tab.label,
            width = tab_width,
            margin = 0,
            padding = Size.padding.small,
            bordersize = Size.border.thin,
            focusable = false,
            checked_func = function() return tab.id == current end,
            callback = function() on_select(tab.id) end,
        }
    end
    return group
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

    local tags = {}
    for _, a in ipairs(node:select("ul.tags.commas a.tag")) do
        local name = plain(a)
        if name ~= "" then table.insert(tags, name) end
    end

    local function stat(class_name)
        return plain(first(node:select("dd." .. class_name)))
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
        summary = plain(first(node:select("blockquote.summary"))),
        rating = rating,
        warnings = warnings,
        category = category,
        complete = complete,
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

function AuthorPage.parseBookmarks(html)
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
    return { items = items, count = count, next_url = pag.next_url, prev_url = pag.prev_url }
end

return AuthorPage
