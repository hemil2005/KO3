--[[
AO3 browser for KOReader.

A deliberately small, read-only browser for archiveofourown.org:
search and tag listings are fetched as HTML, parsed into native
KOReader lists, and a work is fetched only when you tap Read.

No login, no kudos/comments, no images, no WebView.
]]

local Blitbuffer = require("ffi/blitbuffer")
local DataStorage = require("datastorage")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local KeyValuePage = require("ui/widget/keyvaluepage")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Menu = require("ui/widget/menu")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local UnderlineContainer = require("ui/widget/container/underlinecontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local ffiutil = require("ffi/util")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local http = require("socket.http")
local util = require("util")
local htmlparser = require("htmlparser")
local _ = require("gettext")
local T = ffiutil.template

local BASE_URL = "https://archiveofourown.org"
local DOWNLOAD_HOST = "https://download.archiveofourown.org"
local UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36"

local Ao3 = WidgetContainer:extend{
    name = "ao3",
}

-- ---------------------------------------------------------------------------
-- Small helpers
-- ---------------------------------------------------------------------------

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- UTF-8 safe truncation on whole characters, ending on a word boundary.
local function shorten(text, max_chars)
    text = trim((text or ""):gsub("%s+", " "))
    if text == "" then return "" end
    local out, count = {}, 0
    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        count = count + 1
        if count > max_chars then break end
        out[#out + 1] = char
    end
    if count <= max_chars then return text end
    local cut = table.concat(out)
    local at = cut:match(".*()%s")
    if at then cut = cut:sub(1, at - 1) end
    return cut .. "…"
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

local function httpErrorMessage(code, headers, status)
    if type(code) ~= "number" then
        -- http.request returns nil, "<error>"; socket.skip(1, ...) then
        -- leaves the error string in the first slot.
        return tostring(code or headers or status or _("Network error"))
    end
    if code == 403 then
        return _("AO3 or Cloudflare refused the request (403).")
    elseif code == 404 then
        return _("AO3 returned 404. The work may be deleted, restricted, or unavailable.")
    elseif code == 429 then
        return _("AO3 is rate-limiting requests (429). Wait a minute, then try again.")
    elseif code == 503 then
        return _("AO3 is busy (503). Try again in a minute.")
    end
    return T(_("HTTP %1"), code)
end

local function getDownloadDir()
    local dir = DataStorage:getFullDataDir() .. "/ao3"
    if lfs.attributes(dir, "mode") ~= "directory" then
        lfs.mkdir(dir)
    end
    return dir
end

local function findCachedWork(dir, id)
    local suffix = " [" .. id .. "].html"
    for entry in lfs.dir(dir) do
        if entry:sub(-#suffix) == suffix then
            return dir .. "/" .. entry
        end
    end
end

-- ---------------------------------------------------------------------------
-- Networking
-- ---------------------------------------------------------------------------

-- AO3 asks crawlers to be gentle and answers 429 (or sometimes 403) when
-- requests are bursty. One page per tap is already cheap; this keeps rapid
-- taps from tripping the gate.
--
-- Deliberately no cookie jar: Cloudflare's bot cookies are bound to the
-- client that earned them, and replaying them from LuaSocket is what started
-- returning 403. Only the adult-content preference is sent.
local MIN_REQUEST_INTERVAL = 1.0
local last_request_at = 0
local REQUEST_COOKIE = "view_adult=true"
local DEFAULT_BLOCK_SECONDS = 300

local function blockedMessage(code, seconds)
    if code == "challenge" then
        return _("AO3 requires a browser check that KOReader cannot complete. Open AO3 in a browser, or use saved works and try again later.")
    end
    return T(_("AO3's edge is refusing this client (%1). A VPN or privacy browser can trigger this; wait about %2 minute(s), or download the work in a normal browser."),
        code, math.max(1, math.ceil(seconds / 60)))
end

local function isBrowserChallenge(code, headers, chunks)
    if code ~= 403 then return false end
    if headers and headers["cf-mitigated"] == "challenge" then return true end
    local head = table.concat(chunks):sub(1, 4096)
    return head:find("<title>Just a moment", 1, true) ~= nil
        or head:find("Enable JavaScript and cookies to continue", 1, true) ~= nil
end

-- Sleep only if the previous request was very recent, so a normal
-- tap-per-page flow never waits.
local function throttle()
    local now = socket.gettime()
    local wait = MIN_REQUEST_INTERVAL - (now - last_request_at)
    if wait > 0 then
        socket.sleep(wait)
    end
    last_request_at = socket.gettime()
end

function Ao3:fetchHtml(url, timeout)
    local now = socket.gettime()
    if self.blocked_until and now < self.blocked_until then
        return nil, blockedMessage(self.blocked_code, self.blocked_until - now)
    end
    self.blocked_until = nil
    local chunks = {}
    local function attempt()
        throttle()
        return pcall(function()
            return socket.skip(1, http.request{
                url = url,
                method = "GET",
                headers = {
                    ["User-Agent"] = UA,
                    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    ["Accept-Language"] = "en-US,en;q=0.9",
                    ["Cookie"] = REQUEST_COOKIE,
                },
                sink = ltn12.sink.table(chunks),
                redirect = true,
            })
        end)
    end

    socketutil:set_timeout(timeout or 20, (timeout or 20) * 3)
    local ok, code, headers, status = attempt()
    local challenged = isBrowserChallenge(code, headers, chunks)
    if ok and code == 403 and not challenged then
        -- Retry a transient challenge once. A 429, particularly one with
        -- Retry-After, must not be retried immediately.
        socket.sleep(3)
        chunks = {}
        ok, code, headers, status = attempt()
        challenged = isBrowserChallenge(code, headers, chunks)
    end
    socketutil:reset_timeout()

    if not ok then
        return nil, tostring(code)
    end
    local body = table.concat(chunks)
    if code == 200 then
        return body
    end
    if code == 429 or code == 403 then
        local retry_after = code == 429 and tonumber(headers and headers["retry-after"])
        local delay = math.max(60, retry_after or DEFAULT_BLOCK_SECONDS)
        self.blocked_until = socket.gettime() + delay
        self.blocked_code = challenged and "challenge" or code
        return nil, blockedMessage(self.blocked_code, delay)
    end
    return nil, httpErrorMessage(code, headers, status)
end

-- ---------------------------------------------------------------------------
-- Listing parser
-- ---------------------------------------------------------------------------

local function parseWork(node)
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

    local authors = {}
    for _, a in ipairs(node:select("h4.heading a[rel='author']")) do
        local name = plain(a)
        if name ~= "" then table.insert(authors, name) end
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

function Ao3:parseListing(html)
    local ok, root = pcall(htmlparser.parse, html, 5000)
    if not ok or not root then
        return nil, _("Could not parse the AO3 page.")
    end

    local items = {}
    for _, node in ipairs(root:select("li.blurb")) do
        local is_group = false
        for _, class_name in ipairs(node.classes) do
            if class_name == "group" then is_group = true break end
        end
        if is_group then
            local work = parseWork(node)
            if work then table.insert(items, work) end
        end
    end

    if #items == 0 and (html:find("Just a moment", 1, true)
            or html:find("cf-challenge", 1, true)
            or html:find("Enable JavaScript and cookies", 1, true)) then
        return nil, _("Cloudflare wants a browser check. Try again in a minute.")
    end

    -- AO3 uses both the old rel=next markup and the newer pagy markup
    -- (`li.next > a`); accept either.
    local next_link = first(root:select("ol.pagination a[rel='next']"))
        or first(root:select("ol.pagination li.next a"))
    local prev_link = first(root:select("ol.pagination a[rel='prev']"))
        or first(root:select("ol.pagination li.prev a"))
    local next_url = next_link and absoluteUrl(util.htmlEntitiesToUtf8(next_link.attributes.href or ""))
    local prev_url = prev_link and absoluteUrl(util.htmlEntitiesToUtf8(prev_link.attributes.href or ""))

    local count
    for _, h in ipairs(root:select("h3.heading")) do
        local text = plain(h)
        count = text:match("([%d,]+) Found")
        if count then break end
    end
    if not count then
        for _, h in ipairs(root:select("h2.heading")) do
            local text = plain(h)
            count = text:match("of ([%d,]+) Works")
            if count then break end
        end
    end

    return {
        items = items,
        next_url = next_url,
        prev_url = prev_url,
        count = count,
    }
end

-- ---------------------------------------------------------------------------
-- Embedded fandom index
-- ---------------------------------------------------------------------------
--
-- The full fandom list is a ~30 MB set of pages online, so it ships with the
-- plugin instead: one zlib-deflated file per media category per letter, plus
-- a tiny index. Only the letter the user opens is read and decompressed.

local FANDOM_DATA_DIR = "data/fandoms"
local MAIN_SOURCE = debug.getinfo(1, "S").source:sub(2)
local FandomPages = dofile((MAIN_SOURCE:gsub("main%.lua$", "fandompages.lua")))

function Ao3:fandomDataDir()
    return (self.path or "plugins/ao3.koplugin") .. "/" .. FANDOM_DATA_DIR
end

function Ao3:loadFandomIndex()
    if self.fandom_index then return self.fandom_index end
    local ok, index = pcall(dofile, self:fandomDataDir() .. "/index.lua")
    if not ok or type(index) ~= "table" or #index == 0 then
        return nil
    end
    self.fandom_index = index
    return index
end

function Ao3:loadFandomLetter(category, letter, offset)
    local page = FandomPages.page(self:fandomDataDir(), category.index, letter, offset)
    if not page then return nil end
    local rows = {}
    for _, entry in ipairs(page.entries) do
        rows[#rows + 1] = {
            text = entry.name,
            mandatory = entry.count ~= "" and entry.count or nil,
            action = function()
                self:loadListing(BASE_URL .. entry.url, entry.name)
            end,
        }
    end
    return rows, page
end

function Ao3:findFandomOffset(category, letter, query)
    local offset, err = FandomPages.find(self:fandomDataDir(), category.index, letter, query)
    if not offset then return nil, err end
    return math.floor(offset / FandomPages.DEFAULT_PAGE_SIZE) * FandomPages.DEFAULT_PAGE_SIZE
end

-- ---------------------------------------------------------------------------
-- Listing UI
-- ---------------------------------------------------------------------------

-- Fetch a page, run it through `parse`, and hand the result to `on_success`.
-- Kept in one place so every screen shows the same spinner and error text.
function Ao3:fetchPage(url, parse, label, on_success)
    NetworkMgr:runWhenOnline(function()
        local Trapper = require("ui/trapper")
        local data, err
        Trapper:wrap(function()
            Trapper:info(label or _("Loading AO3…"))
            local ok, result, parse_err = pcall(function()
                local html, http_err = self:fetchHtml(url, 25)
                if not html then return nil, http_err end
                return parse(html)
            end)
            if ok then
                data, err = result, parse_err
            else
                err = tostring(result)
            end
            Trapper:reset()
        end)
        NetworkMgr:afterWifiAction()

        if data then
            on_success(data)
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Could not load AO3:\n%1"), err or _("unknown error")),
            })
        end
    end)
end

function Ao3:loadListing(url, fallback_title, replace)
    self:fetchPage(url, function(html)
        return self:parseListing(html)
    end, _("Loading works…"), function(listing)
        self:showListing(listing, fallback_title, replace)
    end)
end

-- ---------------------------------------------------------------------------
-- Work cards
-- ---------------------------------------------------------------------------
--
-- Native Menu items carry one font and a right-aligned `mandatory` string, so
-- title, author and blurb cannot share a single selectable row. This small
-- Menu subclass renders each work as one card: a bold title, a quieter author
-- line, and a summary clamped to three lines. Every other row (paging, the
-- home screen, empty states) stays a compact single-line row.

local AO3_CARD_SUMMARY_LINES = 3
local AO3_CARD_SUMMARY_CHARS = 320

local function ao3CardSizes(font_size, infont_size)
    local title_size = math.max(12, math.floor(font_size or 20))
    local info_size = math.max(11, math.min(infont_size or (title_size - 4), title_size - 2))
    local summary_size = math.max(11, math.min(info_size, title_size - 3))
    return title_size, info_size, summary_size
end

-- Some device builds (older Kindle releases among them) lack the newer
-- TextWidget.getTextHeight class helper. Measure a throwaway widget once
-- per (size, bold) pair instead, so menu building stays cheap everywhere.
local line_height_cache = {}
local function lineHeight(face, bold)
    local key = (face.size or 0) .. (bold and "b" or "n")
    local h = line_height_cache[key]
    if not h then
        if TextWidget.getTextHeight then
            h = TextWidget.getTextHeight("A", face, bold)
        else
            local probe = TextWidget:new{ text = "A", face = face, bold = bold }
            h = probe:getSize().h
            if probe.free then probe:free() end
        end
        line_height_cache[key] = h
    end
    return h
end

local function ao3CardMetrics(font_size, infont_size, linesize)
    local title_size, info_size, summary_size = ao3CardSizes(font_size, infont_size)
    local title_face = Font:getFace("smallinfofont", title_size)
    local info_face = Font:getFace("smallinfofont", info_size)
    local title_h = lineHeight(title_face, true)
    local author_h = lineHeight(info_face, false)
    -- TextBoxWidget computes its line height as (1 + line_height) * face.size.
    local summary_line_h = math.floor((1 + 0.3) * summary_size + 0.5)
    local summary_h = AO3_CARD_SUMMARY_LINES * summary_line_h
    local card_content_h = title_h + author_h + summary_h
        + Size.span.vertical_default + Size.span.vertical_large
    return {
        title_size = title_size,
        info_size = info_size,
        summary_size = summary_size,
        summary_h = summary_h,
        card_h = card_content_h + linesize,
        card_no_summary_h = title_h + author_h
            + Size.span.vertical_default + Size.span.vertical_large + linesize,
        compact_h = title_h + 2 * Size.span.vertical_default + linesize,
    }
end

local Ao3MenuItem = InputContainer:extend{
    linesize = Size.line.medium,
    line_color = Blitbuffer.COLOR_DARK_GRAY,
}

function Ao3MenuItem:buildCard(metrics)
    local width = self.content_width
    local author = trim(self.entry.mandatory or "")
    local summary = trim(self.entry.summary or "")

    self.title_widget = TextWidget:new{
        text = trim(self.entry.text or "") ~= "" and self.entry.text or _("Untitled"),
        face = Font:getFace("smallinfofont", metrics.title_size),
        bold = true,
        max_width = width,
    }
    self.author_widget = TextWidget:new{
        text = author ~= "" and author or _("Anonymous"),
        face = Font:getFace("smallinfofont", metrics.info_size),
        fgcolor = Blitbuffer.COLOR_GRAY_6,
        max_width = width,
    }
    self.summary_widget = TextBoxWidget:new{
        text = summary,
        face = Font:getFace("smallinfofont", metrics.summary_size),
        width = width,
        height = metrics.summary_h,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        alignment = "left",
        fgcolor = Blitbuffer.COLOR_GRAY_6,
    }

    local content = VerticalGroup:new{ align = "left" }
    content[#content + 1] = self.title_widget
    content[#content + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
    content[#content + 1] = self.author_widget
    content[#content + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    content[#content + 1] = self.summary_widget
    return content
end

function Ao3MenuItem:buildCompact(metrics)
    local title_face = Font:getFace("smallinfofont", metrics.title_size)
    local mandatory = self.entry.mandatory
    self.mandatory_widget = mandatory and TextWidget:new{
        text = tostring(mandatory),
        face = Font:getFace("infont", metrics.info_size),
        bold = self.entry.bold == true,
        fgcolor = self.entry.dim and Blitbuffer.COLOR_DARK_GRAY or nil,
    } or nil
    local mandatory_w = self.mandatory_widget and self.mandatory_widget:getWidth() or 0
    local gap = mandatory_w > 0 and Size.span.horizontal_default or 0
    self.title_widget = TextWidget:new{
        text = self.entry.text or "",
        face = title_face,
        bold = self.entry.bold == true,
        max_width = math.max(1, self.content_width - mandatory_w - gap),
    }

    local row = HorizontalGroup:new{ align = "center" }
    row[#row + 1] = self.title_widget
    if self.mandatory_widget then
        local spacer = math.max(0, self.content_width
            - self.title_widget:getWidth() - mandatory_w - gap)
        row[#row + 1] = HorizontalSpan:new{ width = gap + spacer }
        row[#row + 1] = self.mandatory_widget
    end
    return row
end

function Ao3MenuItem:init()
    self.content_width = math.max(1, self.dimen.w - 2 * Size.padding.fullscreen)
    local metrics = ao3CardMetrics(self.font_size, self.infont_size, self.linesize)
    self.ao3_metrics = metrics

    local content
    if self.entry.ao3_work then
        content = self:buildCard(metrics)
    else
        content = self:buildCompact(metrics)
    end
    self.content_group = content

    local content_h = math.max(1, self.dimen.h - self.linesize)
    local content_dimen = Geom:new{ x = 0, y = 0, w = self.content_width, h = content_h }
    -- Cards keep the title at a consistent top edge. Compact rows stay
    -- left-aligned like native menu rows and centre vertically.
    local content_holder
    if self.entry.ao3_work then
        content_holder = WidgetContainer:new{
            dimen = content_dimen:copy(),
            content,
        }
    else
        content_holder = LeftContainer:new{
            dimen = content_dimen:copy(),
            content,
        }
    end
    self._underline_container = UnderlineContainer:new{
        color = self.line_color,
        linesize = self.linesize,
        -- Older releases have no Size.line.focus_row, and debug builds raise
        -- on unknown Size.line keys; rawget keeps both cases safe.
        focus_linesize = rawget(Size.line, "focus_row")
            or rawget(Size.line, "thick"),
        background = Blitbuffer.COLOR_WHITE,
        vertical_align = "center",
        padding = 0,
        dimen = content_dimen:copy(),
        content_holder,
    }
    self._focus_indicator = self._underline_container

    self[1] = FrameContainer:new{
        bordersize = 0,
        padding = 0,
        HorizontalGroup:new{
            HorizontalSpan:new{ width = Size.padding.fullscreen },
            self._underline_container,
            HorizontalSpan:new{ width = Size.padding.fullscreen },
        },
    }

    self.ges_events = {
        TapSelect = {
            GestureRange:new{
                ges = "tap",
                range = self.dimen,
            },
        },
        HoldSelect = {
            GestureRange:new{
                ges = self.handle_hold_on_hold_release and "hold_release" or "hold",
                range = self.dimen,
            },
        },
    }
end

function Ao3MenuItem:getGesPosition(ges)
    local dimen = self[1].dimen
    return {
        x = (ges.pos.x - dimen.x) / dimen.w,
        y = (ges.pos.y - dimen.y) / dimen.h,
    }
end

function Ao3MenuItem:onTapSelect(arg, ges)
    if not self[1].dimen then return end
    self.menu:onMenuSelect(self.entry, self:getGesPosition(ges))
    return true
end

function Ao3MenuItem:onHoldSelect(arg, ges)
    if not self[1].dimen then return end
    self.menu:onMenuHold(self.entry, self:getGesPosition(ges))
    return true
end

function Ao3MenuItem:getFocusIndicatorRegion()
    if self._underline_container.getFocusIndicatorRegion then
        return self._underline_container:getFocusIndicatorRegion()
    end
end

function Ao3MenuItem:repaintFocusIndicator(bb)
    if self._underline_container.repaintFocusIndicator then
        return self._underline_container:repaintFocusIndicator(bb)
    end
    return false
end

function Ao3MenuItem:onFocus()
    self._underline_container.color = Blitbuffer.COLOR_BLACK
    self._underline_container.focused = true
    return true
end

function Ao3MenuItem:onUnfocus()
    self._underline_container.color = self.line_color
    self._underline_container.focused = false
    return true
end

-- Menu supports variable item heights through `items_max_lines`, but it
-- always creates its own MenuItem. Override just the two methods that decide
-- row heights and which widget class a row uses; paging, focus and the title
-- bar remain native Menu behaviour.
local Ao3WorkMenu = Menu:extend{
    items_max_lines = 4,
}

function Ao3WorkMenu:setupItemHeights()
    local metrics = ao3CardMetrics(
        self.font_size,
        self.items_mandatory_font_size or (self.font_size - 4),
        self.linesize
    )
    self.ao3_metrics = metrics
    self.page_items = {}
    if #self.item_table == 0 then
        self.page_items[1] = {}
        return
    end

    -- Rows that are not work cards keep the native menu density: one row per
    -- slot on a full page. Cards take as much height as their text needs.
    local compact_h = math.max(self.item_dimen.h, metrics.compact_h)
    -- Builds older than 2024.07 never set available_height; fall back to the
    -- height of a full native page so the list still gets rows.
    local budget = self.available_height
        or ((self.item_dimen and self.item_dimen.h or 0) * (self.perpage or 1))
    local items, used = {}, 0
    for index, item in ipairs(self.item_table) do
        if item.ao3_work then
            item.height = item.summary and metrics.card_h or metrics.card_no_summary_h
        else
            item.height = compact_h
        end
        if #items > 0 and used + item.height > budget then
            self.page_items[#self.page_items + 1] = items
            items = { index }
            used = item.height
        else
            items[#items + 1] = index
            used = used + item.height
        end
    end
    self.page_items[#self.page_items + 1] = items
end

-- switchItemTable resolves the page before updateItems recalculates heights,
-- so an empty or stale page_items table must not compare against a nil index.
function Ao3WorkMenu:getPageNumber(item_number)
    if #self.item_table == 0 or item_number == 0 then
        return 1
    end
    if self.page_items then
        for page, items in ipairs(self.page_items) do
            if #items > 0 and item_number <= items[#items] then
                return page
            end
        end
        return math.max(1, #self.page_items)
    end
    return math.ceil(math.min(item_number, #self.item_table) / (self.perpage or 1))
end

function Ao3WorkMenu:updateItems(select_number, no_recalculate_dimen)
    local old_dimen = self.dimen and self.dimen:copy()
    self.layout = {}
    self.item_group:clear()
    self.page_info:resetLayout()
    self.return_button:resetLayout()
    self.content_group:resetLayout()
    self:_recalculateDimen(no_recalculate_dimen)

    if not self.page_items then
        -- Builds before 2024.07 never call setupItemHeights from
        -- _recalculateDimen; without this the list would render no rows.
        self:setupItemHeights()
    end

    local page_items = self.page_items and self.page_items[self.page] or {}
    for idx, index in ipairs(page_items) do
        local item = self.item_table[index]
        if item then
            item.idx = index
            if index == self.itemnumber then
                select_number = idx
            end
            local item_tmp = Ao3MenuItem:new{
                idx = index,
                entry = item,
                menu = self,
                show_parent = self.show_parent,
                dimen = Geom:new{
                    x = 0, y = 0,
                    w = self.item_dimen.w,
                    h = item.height or self.item_dimen.h,
                },
                font_size = self.font_size,
                infont_size = self.items_mandatory_font_size or (self.font_size - 4),
                linesize = self.linesize,
                line_color = self.line_color,
            }
            table.insert(self.item_group, item_tmp)
            table.insert(self.layout, { item_tmp })
        end
    end

    self:updatePageInfo(select_number)
    if self.mergeTitleBarIntoLayout then
        -- Newer builds merge the title bar into the focus layout; older
        -- device builds have no such method and must keep working.
        self:mergeTitleBarIntoLayout()
    end

    UIManager:setDirty(self.show_parent, function()
        local refresh_dimen = old_dimen and old_dimen:combine(self.dimen)
            or self.dimen
        return "ui", refresh_dimen
    end)
end

function Ao3:showListing(listing, fallback_title, replace)
    local rows = {}
    for _, work in ipairs(listing.items) do
        local summary = trim(work.summary or "")
        local current = work
        rows[#rows + 1] = {
            text = work.title,
            mandatory = work.authors,
            -- One selectable card carries everything visible for the work.
            -- The raw work is kept for the action and for future fields.
            ao3_work = work,
            summary = summary ~= "" and shorten(summary, AO3_CARD_SUMMARY_CHARS) or nil,
            action = function()
                self:showWork(current)
            end,
        }
    end
    if #rows == 0 then
        rows[1] = { text = _("No works found.") }
    end

    -- Paging rows are only added when AO3 says there is another page. A
    -- paged fetch replaces this listing's rows so Back still returns to the
    -- screen that opened the listing, not to the previous page of results.
    if listing.next_url then
        rows[#rows + 1] = {
            text = _("Next page →"),
            action = function()
                self:loadListing(listing.next_url, fallback_title, true)
            end,
        }
    end
    if listing.prev_url then
        rows[#rows + 1] = {
            text = _("← Previous page"),
            action = function()
                self:loadListing(listing.prev_url, fallback_title, true)
            end,
        }
    end

    local title = fallback_title or _("Works")
    if listing.count then
        title = T(_("%1 · %2 works"), title, listing.count)
    end
    if replace then
        self:replaceRows(title, rows)
    else
        self:pushRows(title, rows)
    end
end

function Ao3:showWork(work)
    local cached = findCachedWork(getDownloadDir(), work.id)
    local rows = {
        {
            _("Read"),
            cached and _("Open saved copy") or _("Fetch and open"),
            callback = function(kv_page)
                UIManager:close(kv_page)
                self:readWork(work.id, work.title)
            end,
        },
        {
            _("Refresh"),
            _("Download the latest version"),
            callback = function(kv_page)
                UIManager:close(kv_page)
                self:readWork(work.id, work.title, true)
            end,
        },
        "----------------------------",
    }
    local details = {
        { _("Summary"), work.summary },
        { _("Rating"), work.rating },
        { _("Warnings"), work.warnings },
        { _("Status"), work.complete },
        { _("Author"), work.authors },
        { _("Fandom"), work.fandoms },
        { _("Category"), work.category },
        { _("Tags"), work.tags },
        { _("Words"), work.words },
        { _("Chapters"), work.chapters },
        { _("Updated"), work.updated },
        { _("Kudos"), work.kudos },
        { _("Hits"), work.hits },
    }
    for _, detail in ipairs(details) do
        if detail[2] and detail[2] ~= "" then
            rows[#rows + 1] = detail
        end
    end

    -- Sits on top of the list; closing it drops the reader back on the
    -- results instead of the file manager.
    UIManager:show(KeyValuePage:new{
        title = work.title,
        kv_pairs = rows,
    })
end

-- ---------------------------------------------------------------------------
-- Reading a work
-- ---------------------------------------------------------------------------

function Ao3:downloadWork(id, title)
    local dir = getDownloadDir()
    local tmp = dir .. "/" .. id .. ".html.part"
    local old = findCachedWork(dir, id)

    local file, file_err = io.open(tmp, "wb")
    if not file then
        return nil, T(_("Cannot write to %1: %2"), dir, tostring(file_err))
    end

    local url = DOWNLOAD_HOST .. "/downloads/" .. id .. "/work.html"
    socketutil:set_timeout(30, 300)
    local ok, code, headers, status = pcall(function()
        return socket.skip(1, http.request{
            url = url,
            method = "GET",
            headers = {
                ["User-Agent"] = UA,
                ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                ["Accept-Language"] = "en-US,en;q=0.9",
                ["Referer"] = BASE_URL .. "/works/" .. id,
                ["Cookie"] = "view_adult=true",
            },
            sink = ltn12.sink.file(file),
            redirect = true,
        })
    end)
    socketutil:reset_timeout()
    pcall(function() file:close() end)

    if not ok then
        os.remove(tmp)
        return nil, tostring(code)
    end
    if code ~= 200 then
        os.remove(tmp)
        return nil, httpErrorMessage(code, headers, status)
    end

    -- The HTML download always contains the preface. A login/adult/error
    -- page does not, so use it as a cheap sanity check.
    local f = io.open(tmp, "rb")
    local head = f and f:read(32768) or ""
    if f then f:close() end
    if not head:find('id="preface"', 1, true) and not head:find('id="chapters"', 1, true) then
        local page_title = head:match("<title[^>]*>(.-)</title>") or ""
        page_title = util.htmlEntitiesToUtf8(page_title)
        os.remove(tmp)
        return nil, T(_("AO3 did not return a work file (%1). It may be restricted or unavailable."), page_title)
    end

    local page_title = head:match("<title[^>]*>(.-)</title>") or (title or ("AO3 " .. id))
    page_title = util.htmlEntitiesToUtf8(page_title)
    page_title = page_title:gsub("%.html$", "")
    local base = util.getSafeFilename(page_title, dir, 120, 10)
    base = base:gsub("[%.%s]+$", "")
    if base == "" then
        base = "AO3 " .. id
    end

    local final = dir .. "/" .. base .. " [" .. id .. "].html"
    -- Keep the old offline copy until a complete, validated replacement is
    -- ready. On Kindle/POSIX, rename atomically replaces the destination.
    local renamed, rename_err = os.rename(tmp, final)
    if not renamed then
        os.remove(tmp)
        return nil, T(_("Could not save the file: %1"), tostring(rename_err))
    end
    if old and old ~= final then
        os.remove(old)
    end
    return final
end

function Ao3:readWork(id, title, refresh)
    local cached = findCachedWork(getDownloadDir(), id)
    if cached and not refresh then
        require("apps/reader/readerui"):showReader(cached)
        return
    end

    NetworkMgr:runWhenOnline(function()
        local Trapper = require("ui/trapper")
        local path, err
        Trapper:wrap(function()
            Trapper:info(T(_("Downloading “%1”…"), title or id))
            local ok, result, download_err = pcall(self.downloadWork, self, id, title)
            if ok then
                path, err = result, download_err
            else
                err = tostring(result)
            end
            Trapper:reset()
        end)
        NetworkMgr:afterWifiAction()

        if path then
            require("apps/reader/readerui"):showReader(path)
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Could not open the work:\n%1"), err or _("unknown error")),
            })
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Screens and navigation
-- ---------------------------------------------------------------------------

-- All cached works, newest first. Only filenames are read; nothing is loaded.
function Ao3:listDownloads()
    local dir = getDownloadDir()
    local items = {}
    for entry in lfs.dir(dir) do
        if entry:match("%.html$") then
            local id = entry:match("%[(%d+)%]%.html$")
            local title = entry:gsub("%s*%[%d+%]%.html$", "")
            local path = dir .. "/" .. entry
            local mtime = lfs.attributes(path, "modification") or 0
            table.insert(items, {
                id = id,
                title = title ~= "" and title or entry,
                path = path,
                mtime = mtime,
            })
        end
    end
    table.sort(items, function(a, b) return a.mtime > b.mtime end)
    return items
end

-- One full-screen Menu is the whole app. Drilling into a screen snapshots the
-- current item table on Menu's own stack, so Back, the X and swipe-down all
-- return to the previous screen without refetching a page.
function Ao3:ensureMenu()
    if self.menu then return self.menu end

    local menu = Ao3WorkMenu:new{
        title = _("AO3"),
        item_table = {},
        covers_fullscreen = true,
        is_borderless = true,
        is_popout = false,
        title_bar_fm_style = true,
        -- AO3 listings are tapped, not keyboard-navigated. Hiding the
        -- per-row A/S/D shortcut boxes gives the title, author and summary
        -- the full width on every device (Menu still keeps page-turn keys).
        is_enable_shortcut = false,
        onMenuSelect = function(menu_self, item)
            if item.sub_item_table then
                self:menuPush(menu_self, item.text, item.sub_item_table)
            elseif item.action then
                item.action(menu_self)
            elseif item.callback then
                item.callback(menu_self)
            end
            return true
        end,
        close_callback = function()
            -- Drop the closed widget tree so nothing is retained on a
            -- memory-tight device.
            FandomPages.clearCache()
            self.menu = nil
        end,
    }

    menu.item_table_stack = menu.item_table_stack or {}
    menu.ao3_title_stack = {}
    menu.ao3_title = _("AO3")

    -- Menu's own back logic pops `item_table_stack`; keep the title stack and
    -- the footer arrow in sync with it.
    menu.onClose = function(menu_self)
        local will_pop = #menu_self.item_table_stack > 0
        local ret = Menu.onClose(menu_self)
        if will_pop then
            menu_self.ao3_title = table.remove(menu_self.ao3_title_stack) or _("AO3")
        end
        if menu_self.page_return_arrow then
            menu_self.page_return_arrow:enableDisable(#menu_self.item_table_stack > 0)
        end
        return ret
    end
    menu.onReturn = menu.onClose

    self.menu = menu
    return menu
end

function Ao3:menuPush(menu, title, rows)
    table.insert(menu.ao3_title_stack, menu.ao3_title or _("AO3"))
    menu.item_table.title = menu.ao3_title or _("AO3")
    table.insert(menu.item_table_stack, menu.item_table)
    menu:switchItemTable(title, rows, 1)
    menu.ao3_title = title
    if menu.page_return_arrow then
        menu.page_return_arrow:enableDisable(#menu.item_table_stack > 0)
    end
end

function Ao3:showHome()
    if self.menu then
        self.menu.item_table_stack = {}
        self.menu.ao3_title_stack = {}
        self.menu.ao3_title = _("AO3")
        self.menu:switchItemTable(_("AO3"), self:homeRows(), 1)
        if self.menu.page_return_arrow then
            self.menu.page_return_arrow:enableDisable(false)
        end
        return
    end
    local menu = self:ensureMenu()
    menu:switchItemTable(_("AO3"), self:homeRows(), 1)
    UIManager:show(menu)
end

-- Put a new item table on top of the current one (fetched pages, downloads).
function Ao3:pushRows(title, rows)
    local menu = self.menu
    if not menu then return end
    self:menuPush(menu, title, rows)
end

-- Paging inside a listing or a long letter must not retain each previous
-- window's item table on Menu's navigation stack.
function Ao3:replaceRows(title, rows)
    local menu = self.menu
    if not menu then return end
    menu:switchItemTable(title, rows, 1)
    menu.ao3_title = title
end

function Ao3:homeRows()
    local downloads = self:listDownloads()
    return {
        { text = _("Browse"), bold = true },
        {
            text = _("Latest works"),
            mandatory = _("Newest on AO3"),
            action = function()
                self:loadListing(self:recentUrl(), _("Latest works"))
            end,
        },
        {
            text = _("Fandoms"),
            mandatory = _("By media"),
            action = function()
                self:showFandoms()
            end,
        },
        {
            text = _("Search"),
            mandatory = _("Title, author or keyword"),
            action = function()
                self:searchDialog()
            end,
        },
        {
            text = _("Tag"),
            mandatory = _("Tag name or URL"),
            action = function()
                self:tagDialog()
            end,
        },
        { text = _("Library"), bold = true },
        {
            text = _("Downloads"),
            mandatory = #downloads > 0 and T(_("%1 saved"), #downloads) or _("None yet"),
            action = function()
                self:showDownloads()
            end,
        },
        {
            text = _("Open work"),
            mandatory = _("URL or ID"),
            action = function()
                self:workDialog()
            end,
        },
    }
end

-- The complete fandom list ships with the plugin, so this screen opens
-- instantly and works offline. Categories live in data/fandoms/index.lua;
-- each category's fandoms are split into one file per letter.
local function formatCount(count)
    local digits = tostring(count):reverse():gsub("(%d%d%d)(%d)", "%1,%2")
    return digits:reverse()
end

function Ao3:fandomRows(index)
    -- Translate outside the loop: `for _, category` would shadow `_`.
    local fandoms_label = _("%1 fandoms")
    local rows = {
        {
            text = _("Find a tag…"),
            mandatory = _("Any fandom or tag"),
            action = function()
                self:tagDialog()
            end,
        },
    }
    for _, category in ipairs(index) do
        rows[#rows + 1] = {
            text = category.name,
            mandatory = T(fandoms_label, formatCount(category.count)),
            action = function()
                self:showFandomLetters(category)
            end,
        }
    end
    return rows
end

function Ao3:showFandoms()
    local index = self:loadFandomIndex()
    if not index then
        UIManager:show(InfoMessage:new{
            text = _("The embedded fandom list is missing. Reinstall the plugin."),
        })
        return
    end
    self:pushRows(_("Fandoms"), self:fandomRows(index))
end

function Ao3:showFandomLetters(category)
    local rows = {}
    for _, letter in ipairs(category.letters) do
        rows[#rows + 1] = {
            text = letter,
            action = function()
                self:showFandomLetter(category, letter)
            end,
        }
    end
    self:pushRows(category.name, rows)
end

function Ao3:showFandomLetter(category, letter)
    self:showFandomLetterPage(category, letter, 0, false)
end

function Ao3:showFandomLetterPage(category, letter, offset, replace)
    local rows, page = self:loadFandomLetter(category, letter, offset)
    if not rows then
        UIManager:show(InfoMessage:new{
            text = _("Could not read that part of the fandom list."),
        })
        return
    end

    table.insert(rows, 1, {
        text = _("Find in this letter…"),
        action = function()
            self:findFandomDialog(category, letter)
        end,
    })

    if page.offset > 0 then
        rows[#rows + 1] = {
            text = _("← Previous 100 fandoms"),
            action = function()
                self:showFandomLetterPage(category, letter, math.max(0, page.offset - page.page_size), true)
            end,
        }
    end
    if page.next_offset then
        rows[#rows + 1] = {
            text = _("Next 100 fandoms →"),
            action = function()
                self:showFandomLetterPage(category, letter, page.next_offset, true)
            end,
        }
    end

    local title = T(_("%1 · %2 · %3–%4/%5"), category.name, letter,
        page.offset + 1, page.offset + #page.entries, formatCount(page.total))
    if replace then
        self:replaceRows(title, rows)
    else
        self:pushRows(title, rows)
    end
end

function Ao3:findFandomDialog(category, letter)
    local dialog
    dialog = InputDialog:new{
        title = T(_("Find in %1 · %2"), category.name, letter),
        description = _("Part of a fandom name"),
        buttons = {{
            { text = _("Cancel"), id = "close", callback = function()
                UIManager:close(dialog)
            end },
            { text = _("Find"), is_enter_default = true, callback = function()
                local query = trim(dialog:getInputValue())
                UIManager:close(dialog)
                if query == "" then return end
                local offset, err = self:findFandomOffset(category, letter, query)
                if offset then
                    self:showFandomLetterPage(category, letter, offset, true)
                else
                    UIManager:show(InfoMessage:new{
                        text = err or _("No matching fandom in this letter."),
                    })
                end
            end },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Ao3:showDownloads()
    local downloads = self:listDownloads()
    local rows = {}

    for _, item in ipairs(downloads) do
        rows[#rows + 1] = {
            text = item.title,
            mandatory = item.id and ("#" .. item.id) or nil,
            action = function()
                require("apps/reader/readerui"):showReader(item.path)
            end,
        }
    end

    if #rows == 0 then
        rows[1] = { text = _("No saved works yet.") }
        rows[2] = { text = _("Open a work and tap Read.") }
    end

    rows[#rows + 1] = {
        text = _("Storage folder"),
        mandatory = _("Show path"),
        action = function()
            UIManager:show(InfoMessage:new{
                text = T(_("AO3 downloads are stored in:\n%1"), getDownloadDir()),
                timeout = 5,
            })
        end,
    }

    local title = #downloads > 0 and T(_("Downloads (%1)"), #downloads) or _("Downloads")
    self:pushRows(title, rows)
end

-- ---------------------------------------------------------------------------
-- Dialogs
-- ---------------------------------------------------------------------------

function Ao3:searchUrl(query)
    return BASE_URL .. "/works/search?work_search%5Bquery%5D=" .. util.urlEncode(query)
end

-- Newest works across the archive. The sort query is decorative for this
-- page (AO3 ignores it here); `/works` is the "Latest Works" listing.
function Ao3:recentUrl()
    return BASE_URL .. "/works"
end

function Ao3:tagUrl(input)
    input = trim(input)
    if input:match("^https?://") then
        return input
    end
    local tag = input:gsub("/", "*s*"):gsub("&", "*a*")
    local encoded = util.urlEncode(tag):gsub("%%2[aA]", "*")
    return BASE_URL .. "/tags/" .. encoded .. "/works"
end

function Ao3:parseWorkId(input)
    input = trim(input)
    local id = input:match("/works/(%d+)")
        or input:match("/downloads/(%d+)")
        or input:match("^(%d+)$")
    return id
end

function Ao3:searchDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Search AO3"),
        description = _("Title, author, or keyword"),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Search"),
                is_enter_default = true,
                callback = function()
                    local query = trim(dialog:getInputValue())
                    UIManager:close(dialog)
                    if query ~= "" then
                        self:loadListing(self:searchUrl(query), T(_("Search: %1"), query))
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Ao3:tagDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Browse an AO3 tag"),
        description = _("Tag name or tag URL"),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Browse"),
                is_enter_default = true,
                callback = function()
                    local input = trim(dialog:getInputValue())
                    UIManager:close(dialog)
                    if input ~= "" then
                        self:loadListing(self:tagUrl(input), input)
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Ao3:workDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Open a work"),
        description = _("Paste an AO3 work URL or ID"),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Open"),
                is_enter_default = true,
                callback = function()
                    local input = trim(dialog:getInputValue())
                    UIManager:close(dialog)
                    local id = self:parseWorkId(input)
                    if id then
                        self:readWork(id)
                    else
                        UIManager:show(InfoMessage:new{
                            text = _("Could not find a work ID in that input."),
                        })
                    end
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

-- ---------------------------------------------------------------------------
-- Plugin entry point
-- ---------------------------------------------------------------------------

function Ao3:init()
    self.ui.menu:registerToMainMenu(self)
end

function Ao3:addToMainMenu(menu_items)
    -- One entry, one app. Everything else lives inside the AO3 screen.
    menu_items.ao3_browser = {
        text = _("AO3"),
        sorting_hint = "more_tools",
        callback = function()
            self:showHome()
        end,
    }
end

return Ao3
