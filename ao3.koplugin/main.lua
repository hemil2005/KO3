--[[
KO3 for KOReader.

A deliberately small browser for archiveofourown.org:
search and tag listings are fetched as HTML, parsed into native
KOReader lists, and a work is fetched only when you tap Read.

No comments, no images, no WebView. An optional AO3 sign-in adds the user's
own bookmarks, marked-for-later, history and subscriptions, and lets the work
page leave kudos, bookmark, subscribe and mark a work for later. Without it
the browser is unchanged and reads public works.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Screen = require("device").screen
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local ImageWidget = require("ui/widget/imagewidget")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Menu = require("ui/widget/menu")
local MultiInputDialog = require("ui/widget/multiinputdialog")
local NetworkMgr = require("ui/network/manager")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextViewer = require("ui/widget/textviewer")
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
local socketurl = require("socket.url")
local http = require("socket.http")
local util = require("util")
local htmlparser = require("htmlparser")
local _ = require("gettext")
local T = ffiutil.template

-- Assigned after the module files are loaded, but referenced by the network
-- helpers defined before it.
local BugReport

local BASE_URL = "https://archiveofourown.org"
local DOWNLOAD_HOST = "https://download.archiveofourown.org"
-- AO3's edge distinguishes this client. With a specific Chrome UA the token
-- endpoint and login page return 403 (cf-mitigated: challenge); this Firefox
-- UA and the headers below return 200 on the same request. Keep them in sync
-- with the working request; see AGENTS.md.
local UA = "Mozilla/5.0 (platform; rv:gecko-version) Gecko/gecko-trail Firefox/firefox-version"

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
-- Account module
-- ---------------------------------------------------------------------------

local MAIN_SOURCE = debug.getinfo(1, "S").source:sub(2)
local Account = dofile((MAIN_SOURCE:gsub("main%.lua$", "account.lua")))

-- ---------------------------------------------------------------------------
-- Networking
-- ---------------------------------------------------------------------------

-- AO3 asks crawlers to be gentle and answers 429 (or sometimes 403) when
-- requests are bursty. One page per tap is already cheap; this keeps rapid
-- taps from tripping the gate.
--
-- No Cloudflare cookies are kept. The only cookies sent are the adult-content
-- preference and, after an explicit sign-in, AO3's own session cookie. See
-- account.lua.
local MIN_REQUEST_INTERVAL = 1.0
local last_request_at = 0
local REQUEST_COOKIE = "view_adult=true"
local DEFAULT_BLOCK_SECONDS = 300

-- Session cookies belong to AO3 only. The download host is included because
-- AO3's FAQ says restricted-work downloads need the session, and it is the
-- host the plugin already uses. Any other redirect target gets no cookies.
local COOKIE_HOSTS = {
    ["archiveofourown.org"] = true,
    ["www.archiveofourown.org"] = true,
    ["download.archiveofourown.org"] = true,
}
local REDIRECT_CODES = { [301] = true, [302] = true, [303] = true, [307] = true, [308] = true }
local MAX_REDIRECTS = 5

local function urlHost(url)
    local ok, parsed = pcall(socketurl.parse, url or "")
    if not ok or type(parsed) ~= "table" or not parsed.host then return nil end
    return parsed.host:lower()
end

local function cookiesAllowed(url)
    return COOKIE_HOSTS[urlHost(url) or ""] == true
end

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

-- Cookies for a request: the session (when signed in) plus view_adult. The
-- session is only attached for AO3's own hosts; a redirect elsewhere gets
-- just the adult-content preference.
function Ao3:cookieHeader(request_url, jar)
    local parts = {}
    local cookies = jar or (self.session and self.session.cookies)
    if cookies and cookiesAllowed(request_url) then
        local header = Account.cookieHeader(cookies)
        if header then parts[#parts + 1] = header end
    end
    parts[#parts + 1] = REQUEST_COOKIE
    return table.concat(parts, "; ")
end

-- AO3 rotates session cookies rarely, so only a real change is written back.
-- Cookies set by another host are ignored. A caller doing a sign-in check can
-- pass its own jar so nothing is persisted before confirmation.
function Ao3:absorbCookies(response_headers, request_url, jar)
    if not response_headers or not cookiesAllowed(request_url) then return end
    if jar then
        Account.mergeCookies(jar, response_headers["set-cookie"])
        return
    end
    if not self.session then return end
    local merged, changed = Account.mergeCookies(
        self.session.cookies, response_headers["set-cookie"])
    if changed then
        self.session.cookies = merged
        Account.save(Account.settingsPath(), self.session)
    end
end

-- One request path for page GETs and the sign-in POST. `opts` may carry
-- method, body, cookie, redirect and retry_on_403.
-- Returns body, error, status_code, response_headers. Body is set for
-- 2xx/3xx responses; error is set otherwise.
--
-- Redirects are followed here, not by LuaSocket: LuaSocket copies the
-- original headers (including Cookie) to the new URL. Recomputing cookies per
-- hop and refusing an HTTPS -> HTTP downgrade is the same approach the OPDS
-- client uses.
function Ao3:httpRequest(url, opts, timeout)
    opts = opts or {}
    local now = socket.gettime()
    if self.blocked_until and now < self.blocked_until then
        return nil, blockedMessage(self.blocked_code, self.blocked_until - now)
    end
    self.blocked_until = nil

    local method = opts.method or "GET"
    local body = opts.body
    local request_url = url
    local hops = 0
    local first_hop = true

    local function finish(...)
        socketutil:reset_timeout()
        return ...
    end

    socketutil:set_timeout(timeout or 20, (timeout or 20) * 3)
    while true do
        local chunks = {}
        local headers = {
            ["User-Agent"] = UA,
            ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            ["Accept-Language"] = "en-US,en;q=0.5",
            ["Sec-GPC"] = "1",
            ["DNT"] = "1",
            ["Connection"] = "keep-alive",
            ["Cookie"] = (first_hop and opts.cookie)
                or self:cookieHeader(request_url, opts.cookie_jar),
        }
        for name, value in pairs(opts.headers or {}) do
            -- Cookies are decided above; never let a caller override them
            -- across a redirect.
            if name:lower() ~= "cookie" then headers[name] = value end
        end
        if body then
            headers["Content-Type"] = headers["Content-Type"]
                or "application/x-www-form-urlencoded"
            headers["Content-Length"] = tostring(#body)
        end

        local function attempt()
            throttle()
            return pcall(function()
                local request = {
                    url = request_url,
                    method = method,
                    headers = headers,
                    sink = ltn12.sink.table(chunks),
                    redirect = false,
                }
                if body then
                    request.source = ltn12.source.string(body)
                end
                return socket.skip(1, http.request(request))
            end)
        end

        local ok, code, response_headers, status = attempt()
        local challenged = isBrowserChallenge(code, response_headers, chunks)
        if ok and code == 403 and not challenged and opts.retry_on_403 ~= false then
            -- Retry a transient challenge once. A 429, particularly one with
            -- Retry-After, must not be retried immediately. A sign-in POST
            -- sets retry_on_403=false so credentials are not posted twice.
            socket.sleep(3)
            chunks = {}
            ok, code, response_headers, status = attempt()
            challenged = isBrowserChallenge(code, response_headers, chunks)
        end

        if not ok then
            return finish(nil, tostring(code))
        end
        self:absorbCookies(response_headers, request_url, opts.cookie_jar)
        local response_body = table.concat(chunks)

        local location = response_headers and response_headers["location"]
        if REDIRECT_CODES[code] and location and opts.redirect ~= false then
            hops = hops + 1
            if hops > MAX_REDIRECTS then
                return finish(nil, _("AO3 redirected too many times."), code, response_headers)
            end
            local next_url = socketurl.absolute(request_url, location)
            if not next_url then
                return finish(nil, _("AO3 sent an invalid redirect."), code, response_headers)
            end
            if request_url:match("^https:") and next_url:match("^http:") then
                return finish(nil, _("AO3 redirected to an insecure address; stopped."),
                    code, response_headers)
            end
            -- 301/302/303 change a POST to a GET with no body, as browsers do.
            if code == 301 or code == 302 or code == 303 then
                if method ~= "GET" and method ~= "HEAD" then
                    method, body = "GET", nil
                end
            end
            request_url = next_url
            first_hop = false
        else
            if type(code) == "number" and code >= 200 and code < 400 then
                return finish(response_body, nil, code, response_headers)
            end
            if code == 429 or code == 403 then
                local retry_after = code == 429
                    and tonumber(response_headers and response_headers["retry-after"])
                local delay = math.max(60, retry_after or DEFAULT_BLOCK_SECONDS)
                self.blocked_until = socket.gettime() + delay
                self.blocked_code = challenged and "challenge" or code
                return finish(nil, blockedMessage(self.blocked_code, delay), code, response_headers)
            end
            local message = httpErrorMessage(code, response_headers, status)
            -- Form posts answer 422 with the reason in the body (a duplicate
            -- kudos, a validation error). Callers that can use it ask for the
            -- body; everything else still gets nil, as before.
            if opts.return_error_body then
                return finish(response_body, message, code, response_headers)
            end
            return finish(nil, message, code, response_headers)
        end
    end
end

function Ao3:fetchHtml(url, timeout)
    local body, err, code = self:httpRequest(url, nil, timeout)
    BugReport.log("http", T("%1 -> %2", BugReport.sanitizeUrl(url), tostring(code)))
    return body, err
end

-- ---------------------------------------------------------------------------
-- Listing parser
-- ---------------------------------------------------------------------------

local AuthorPage = dofile((MAIN_SOURCE:gsub("main%.lua$", "authorpage.lua")))
local WorkPage = dofile((MAIN_SOURCE:gsub("main%.lua$", "workpage.lua")))
local HomePage = dofile((MAIN_SOURCE:gsub("main%.lua$", "homepage.lua")))
local AccountPage = dofile((MAIN_SOURCE:gsub("main%.lua$", "accountpage.lua")))
local SettingsPage = dofile((MAIN_SOURCE:gsub("main%.lua$", "settingspage.lua")))
local Preferences = dofile((MAIN_SOURCE:gsub("main%.lua$", "preferences.lua")))
local Uikit = dofile((MAIN_SOURCE:gsub("main%.lua$", "uikit.lua")))
local Updater = dofile((MAIN_SOURCE:gsub("main%.lua$", "updater.lua")))
BugReport = dofile((MAIN_SOURCE:gsub("main%.lua$", "bugreport.lua")))
Ao3.BugReport = BugReport
Ao3.Updater = Updater

-- Work blurbs are parsed in authorpage.lua so author bookmarks can reuse the
-- same parser; listings, search results and bookmark pages share the markup.
local parseWork = AuthorPage.parseWorkNode

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
            -- Search/tag pages say "1 - 20 of N Works"; author pages say
            -- "N Works by <name>" (single page) or the same "of" form.
            count = text:match("of ([%d,]+) Works")
                or text:match("^([%d,]+) Works by")
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
            ao3_fandom = true,
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
function Ao3:fetchPage(url, parse, label, on_success, on_error, silent)
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
                BugReport.log("error", err)
            end
            Trapper:reset()
        end)
        NetworkMgr:afterWifiAction()

        if data then
            on_success(data)
        else
            if on_error then pcall(on_error, err) end
            if not silent then
                UIManager:show(InfoMessage:new{
                    text = T(_("Could not load AO3:\n%1"), err or _("unknown error")),
                })
            end
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
-- An expanded tag box stops at six lines: a listing is for choosing a work,
-- and a card taller than the page would be clipped by the menu. The details
-- page still carries the complete tag list.
local AO3_CARD_TAG_LINES = 6

-- AO3's required-tag symbols, redrawn in the catalogue's own ink. The shapes
-- are AO3's (a lettered rating square, a warning mark, a gender symbol and a
-- completion mark); the colour is not, because the device is grayscale and
-- the design has no hue. The symbol grid is the letter index of a work.
local RATING_LETTERS = {
    ["rating-general-audience"] = "G",
    ["rating-teen"] = "T",
    ["rating-mature"] = "M",
    ["rating-explicit"] = "E",
    ["rating-notrated"] = "?",
}
local WARNING_GLYPHS = {
    ["warning-yes"] = "!",
    ["warning-choosenotto"] = "!?",
    ["warning-external-work"] = "↗",
}
local CATEGORY_ICONS = {
    ["category-gen"] = "category-gen",
    ["category-slash"] = "category-slash",
    ["category-het"] = "category-het",
    ["category-femslash"] = "category-femslash",
    ["category-multi"] = "category-multi",
    ["category-other"] = "category-other",
}

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

-- A TextBoxWidget draws its line boxes plus whatever the face's tallest
-- glyph needs beyond the last one, so a block measured from its line count
-- alone clips its final line by a pixel — visible as a hairline cutting
-- through the third line of a work card's blurb. Measure that overflow the way
-- TextBoxWidget itself does, once per size.
local textbox_extra_cache = {}
local function textboxExtra(face)
    local key = face.size or 0
    local extra = textbox_extra_cache[key]
    if extra == nil then
        extra = 0
        local ok, face_height = pcall(function()
            return face.ftsize:getHeightAndAscender()
        end)
        if ok and face_height then
            -- TextBoxWidget's own line height, which the card metrics use too.
            local line_h = math.floor((1 + 0.3) * (face.size or 0) + 0.5)
            local diff = math.floor(line_h - face_height)
            if diff < 0 then extra = -diff end
        end
        textbox_extra_cache[key] = extra
    end
    return extra
end

-- Forward declaration: the card metrics need text measurement, and the
-- measurement cache is defined below for the fandom index.
local measuredWidth

local function ao3CardMetrics(font_size, infont_size, linesize)
    local title_size, info_size, summary_size = ao3CardSizes(font_size, infont_size)
    local title_face = Font:getFace("smallinfofont", title_size)
    local info_face = Font:getFace("smallinfofont", info_size)
    local title_h = lineHeight(title_face, true)
    local author_h = lineHeight(info_face, false)
    -- TextBoxWidget computes its line height as (1 + line_height) * face.size.
    local summary_line_h = math.floor((1 + 0.3) * summary_size + 0.5)
    local summary_h = AO3_CARD_SUMMARY_LINES * summary_line_h
        + textboxExtra(Font:getFace("smallinfofont", summary_size))
    -- A fandom index row is a name of at most two lines plus the air that
    -- keeps two records apart; the second line is only paid when used.
    local fandom_line_h = math.floor((1 + 0.3) * title_size + 0.5)
    local fandom_line_extra = textboxExtra(title_face)
    local fandom_name_h = 2 * fandom_line_h + fandom_line_extra
    local fandom_pad = 2 * Size.span.vertical_large

    -- The symbol grid is two cells square with a hairline gap; the card's
    -- text column starts after it. A cell is sized from the type, not from a
    -- frozen pixel value, so the grid grows with the reader's font setting.
    local symbol = Screen:scaleBySize(22)
    local symbol_gap = Screen:scaleBySize(3)
    local symbol_w = 2 * symbol + symbol_gap
    local symbol_glyph = math.max(9, math.floor(symbol * 0.66))

    local tag_glyph_w = measuredWidth("+", Font:getFace("cfont", info_size), true)
    local tag_glyph_h = lineHeight(Font:getFace("cfont", info_size), true)
    local tag_line_h = math.floor((1 + 0.3) * info_size + 0.5)

    return {
        title_size = title_size,
        info_size = info_size,
        summary_size = summary_size,
        title_h = title_h,
        meta_h = author_h,
        summary_h = summary_h,
        summary_line_h = summary_line_h,
        symbol = symbol,
        symbol_gap = symbol_gap,
        symbol_w = symbol_w,
        symbol_glyph = symbol_glyph,
        -- Air above the first line, so a symbol cell never touches the
        -- separator of the card above it.
        top_pad = Size.span.vertical_large,
        -- With the grid present the title and byline sit beside it; without
        -- one the top block is just the two lines of type.
        top_h = math.max(symbol_w, title_h + Size.span.vertical_default + author_h),
        tag_border = Size.border.default,
        tag_pad = Size.padding.default,
        tag_glyph_w = tag_glyph_w,
        tag_glyph_h = tag_glyph_h,
        tag_line_h = tag_line_h,
        linesize = linesize,
        fandom_name_h = fandom_name_h,
        fandom_line_h = fandom_line_h,
        fandom_one_line_h = fandom_line_h + fandom_line_extra + fandom_pad + linesize,
        fandom_two_line_h = fandom_name_h + fandom_pad + linesize,
        compact_h = title_h + 2 * Size.span.vertical_default + linesize,
    }
end

-- Paging through a big letter re-measures the same names, so remember each
-- string's single-line width. The table is capped: browsing many letters must
-- not grow without bound on a memory-tight device.
local measured_width_cache = {}
local measured_width_count = 0
local MEASURED_WIDTH_CACHE_MAX = 2000

measuredWidth = function(text, face, bold)
    local key = tostring(face.size or 0) .. (bold and "b" or "n") .. "\1" .. text
    local width = measured_width_cache[key]
    if width then return width end
    local probe = TextWidget:new{ text = text, face = face, bold = bold }
    width = probe:getWidth()
    if probe.free then probe:free() end
    if measured_width_count >= MEASURED_WIDTH_CACHE_MAX then
        measured_width_cache = {}
        measured_width_count = 0
    end
    measured_width_cache[key] = width
    measured_width_count = measured_width_count + 1
    return width
end

-- The width a fandom name may use once the right-aligned count has taken its
-- column. Shared by the height pass and the row builder so a name never wraps
-- inside a row measured for one line.
local function fandomNameWidth(entry, content_width, metrics)
    local count = trim(tostring(entry.mandatory or ""))
    local count_w = 0
    if count ~= "" then
        count_w = measuredWidth(count,
            Font:getFace("infont", metrics.info_size), false)
    end
    return math.max(1, content_width - (count_w > 0
        and (count_w + Size.span.horizontal_default) or 0))
end

-- Two lines is the ceiling; the row is measured for exactly what the name
-- needs. Anything within a hair of the edge is given the second line rather
-- than risk clipping a glyph.
local function fandomNameLines(entry, content_width, metrics)
    local name = trim(entry.text or "")
    local available = fandomNameWidth(entry, content_width, metrics)
    local name_w = measuredWidth(name,
        Font:getFace("smallinfofont", metrics.title_size), true)
    if name_w + 2 * Size.padding.small > available then return 2 end
    return 1
end

-- The tag box is the one control inside a work card: a paper fold with one
-- line of tags closed and up to six lines open. The section headers' +/−
-- glyph sits in its corner, so the tap has a visible affordance.
local function tagTextWidth(width, metrics)
    return math.max(1, width - 2 * (metrics.tag_border + metrics.tag_pad)
        - metrics.tag_glyph_w - Size.span.horizontal_small)
end

-- Fit as many whole tags as one line allows, then say how many are left.
-- A tag is never cut in half: a half-tag is worse than a count.
local function fittedTags(tags, face, width)
    local all = table.concat(tags, ", ")
    if measuredWidth(all, face, false) <= width then return all end

    local prefix, count = "", 0
    for i = 1, #tags do
        local candidate = count == 0 and tags[i] or (prefix .. ", " .. tags[i])
        if measuredWidth(candidate, face, false) <= width then
            prefix, count = candidate, i
        else
            break
        end
    end

    local more = #tags - count
    local suffix = " " .. T(_("+%1 more"), more)
    while count > 0 and measuredWidth(prefix .. suffix, face, false) > width do
        count = count - 1
        prefix = count > 0 and table.concat(tags, ", ", 1, count) or ""
    end
    if count == 0 then return T(_("+%1 more"), more) end
    return prefix .. suffix
end

local function tagBoxHeight(tags, metrics, width, expanded, entry)
    local text_h = metrics.meta_h
    if expanded then
        -- Build the same TextBox the card will show and take its height: a
        -- line count alone would miss the glyph allowance the widget adds.
        -- The height is cached on the row so paging does not lay the tags out
        -- again; only an open box pays for it.
        local key = tostring(metrics.info_size) .. ":" .. tostring(width)
        local cached = entry and entry.ao3_tag_height
        if cached and cached.key == key then
            text_h = cached.h
        else
            local box = TextBoxWidget:new{
                text = table.concat(tags, ", "),
                face = Font:getFace("smallinfofont", metrics.info_size),
                width = tagTextWidth(width, metrics),
                height = AO3_CARD_TAG_LINES * metrics.tag_line_h,
                height_adjust = true,
                height_overflow_show_ellipsis = true,
                alignment = "left",
            }
            text_h = box:getSize().h
            box:free()
            if entry then
                entry.ao3_tag_height = { key = key, h = text_h }
            end
        end
    end
    return 2 * (metrics.tag_border + metrics.tag_pad)
        + math.max(text_h, metrics.tag_glyph_h)
end

local function hasSymbols(work)
    return work.rating_key or work.warning_key
        or work.category_key or work.complete_key
end

local function hasStats(work)
    return trim(work.words or "") ~= "" or trim(work.chapters or "") ~= ""
        or trim(work.updated or "") ~= ""
end

-- A blurb is paid for by the lines it actually uses, not by the three-line
-- ceiling: a two-line summary must not leave a blank line under the card.
-- The box is built exactly as the card will show it and measured, because a
-- line whose glyph overflows its nominal height is a pixel taller than the
-- line count suggests. The measurement is cached on the row, since the menu
-- re-runs its height pass on every page turn.
local function summaryHeight(entry, metrics, width)
    local text = trim(entry.summary or "")
    if text == "" then return 0 end
    local key = tostring(metrics.summary_size) .. ":" .. tostring(width)
    local cached = entry.ao3_summary_height
    if cached and cached.key == key then return cached.h end

    local box = TextBoxWidget:new{
        text = text,
        face = Font:getFace("smallinfofont", metrics.summary_size),
        width = width,
        height = metrics.summary_h,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        alignment = "left",
    }
    local h = box:getSize().h
    box:free()
    entry.ao3_summary_height = { key = key, h = h }
    return h
end

-- The title and its byline share one line when both fit: the catalogue reads
-- "title ... by author" across the row instead of paying a second line for a
-- short name. A title too long to leave room keeps the byline beneath it, and
-- the same measurement drives the height pass and the widget builder so a card
-- is never measured for fewer lines than it draws.
local function titleSharesByline(entry, metrics, text_w)
    local title = trim(entry.text or "")
    local author = trim(entry.mandatory or "")
    local title_w = title ~= "" and measuredWidth(title,
        Font:getFace("smallinfofont", metrics.title_size), true) or 0
    local author_w = measuredWidth(T(_("by %1"),
        author ~= "" and author or _("Anonymous")),
        Font:getFace("smallinfofont", metrics.info_size), false)
    return title_w + Size.span.horizontal_default + author_w <= text_w
end

-- Fandom and relationships are both classification, so they share a line when
-- they fit and keep a line each when they do not.
local function metadataSharesLine(entry, metrics, text_w)
    local work = entry.ao3_work or {}
    local fandom = trim(work.fandoms or "")
    local ships = trim(work.relationships or "")
    if fandom == "" or ships == "" then return true end
    local face = Font:getFace("smallinfofont", metrics.info_size)
    return measuredWidth(fandom, face, false)
        + measuredWidth(" · ", face, false)
        + measuredWidth(ships, face, false) <= text_w
end

-- Exact height of a card, shared by the menu's height pass and the widget
-- builder, so an opened tag box cannot clip the text below it.
local function ao3CardHeight(entry, metrics, content_width)
    local work = entry.ao3_work or {}
    local grid = hasSymbols(work)
    local text_w = grid
        and math.max(1, content_width - metrics.symbol_w - Size.padding.large)
        or content_width
    local type_h = metrics.title_h
    if not titleSharesByline(entry, metrics, text_w) then
        type_h = type_h + Size.span.vertical_default + metrics.meta_h
    end
    local h = metrics.top_pad
        + (grid and math.max(metrics.symbol_w, type_h) or type_h)

    local first = true
    local function add(gap, block_h)
        h = h + (first and Size.span.vertical_large or gap) + block_h
        first = false
    end
    local has_fandom = trim(work.fandoms or "") ~= ""
    local has_ships = trim(work.relationships or "") ~= ""
    if has_fandom or has_ships then
        local meta_h = metrics.meta_h
        if has_fandom and has_ships
                and not metadataSharesLine(entry, metrics, text_w) then
            meta_h = 2 * meta_h + Size.span.vertical_default
        end
        add(0, meta_h)
    end
    if work.tag_list and #work.tag_list > 0 then
        add(Size.span.vertical_large, tagBoxHeight(work.tag_list, metrics,
            text_w, entry.tags_expanded == true, entry))
    end
    local summary_h = summaryHeight(entry, metrics, text_w)
    if summary_h > 0 then
        add(Size.span.vertical_large, summary_h)
    end
    if hasStats(work) then add(Size.span.vertical_large, metrics.meta_h) end
    return h + metrics.top_pad + metrics.linesize
end

-- A square cell with one mark. A blank cell is AO3's symbol for "none", so
-- it stays a square rather than disappearing from the grid.
local function symbolCell(content, metrics)
    local border = Size.border.default
    local inner = metrics.symbol - 2 * border
    return FrameContainer:new{
        bordersize = border,
        color = Blitbuffer.COLOR_BLACK,
        background = Blitbuffer.COLOR_WHITE,
        margin = 0,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = inner, h = inner },
            content,
        },
    }
end

local function blankCell(metrics)
    return symbolCell(VerticalSpan:new{ width = 0 }, metrics)
end

local Ao3MenuItem = InputContainer:extend{
    linesize = Size.line.medium,
    line_color = Blitbuffer.COLOR_DARK_GRAY,
}

-- The AO3 symbols are vector files rendered at cell size, so they stay sharp
-- on every screen and fall back to a blank cell on a build without SVG.
function Ao3MenuItem:symbolImage(name, metrics)
    if not self.icons_dir then return nil end
    local ok, widget = pcall(ImageWidget.new, ImageWidget, {
        file = self.icons_dir .. name .. ".svg",
        width = metrics.symbol_glyph,
        height = metrics.symbol_glyph,
        alpha = true,
    })
    if ok and widget then return widget end
    return nil
end

-- Rating, warnings, category, completion: a 2x2 grid beside the title. It is
-- the card's classification mark, the way a catalogue entry carries its
-- subject code before the title.
function Ao3MenuItem:buildSymbols(work, metrics)
    if not hasSymbols(work) then return nil end

    local function textCell(glyph)
        if not glyph or glyph == "" then return blankCell(metrics) end
        return symbolCell(TextWidget:new{
            text = glyph,
            face = Font:getFace("smallinfofont", metrics.symbol_glyph),
            bold = true,
            max_width = metrics.symbol,
        }, metrics)
    end
    local function imageCell(name)
        local image = name and self:symbolImage(name, metrics)
        if not image then return blankCell(metrics) end
        return symbolCell(image, metrics)
    end

    local rating = textCell(RATING_LETTERS[work.rating_key or ""])
    local warning = textCell(WARNING_GLYPHS[work.warning_key or ""])
    local category = imageCell(CATEGORY_ICONS[work.category_key or ""])
    local complete
    if work.complete_key == "complete-yes" then
        complete = textCell("✓")
    elseif work.complete_key == "complete-no" then
        complete = imageCell("complete-no")
    else
        complete = blankCell(metrics)
    end

    local top = HorizontalGroup:new{ align = "center" }
    top[#top + 1] = rating
    top[#top + 1] = HorizontalSpan:new{ width = metrics.symbol_gap }
    top[#top + 1] = warning

    local bottom = HorizontalGroup:new{ align = "center" }
    bottom[#bottom + 1] = category
    bottom[#bottom + 1] = HorizontalSpan:new{ width = metrics.symbol_gap }
    bottom[#bottom + 1] = complete

    local grid = VerticalGroup:new{ align = "left" }
    grid[#grid + 1] = top
    grid[#grid + 1] = VerticalSpan:new{ width = metrics.symbol_gap }
    grid[#grid + 1] = bottom
    self.symbol_grid = grid
    return grid
end

-- Words, chapters, updated: the record's numbers, with the labels in Slate
-- and the values in bold ink. A trailing fact that will not fit is dropped
-- rather than wrapped onto a second line.
function Ao3MenuItem:buildStats(work, metrics, width)
    local face = Font:getFace("smallinfofont", metrics.info_size)
    local items = {}
    local function add(label, value)
        value = trim(value or "")
        if value ~= "" then
            items[#items + 1] = { label = label, value = value }
        end
    end
    add(_("Words"), work.words)
    add(_("Chapters"), work.chapters)
    add(_("Updated"), work.updated)
    if #items == 0 then return nil end

    local row = HorizontalGroup:new{ align = "center" }
    local used = 0
    for i, item in ipairs(items) do
        local label = TextWidget:new{
            text = item.label,
            face = face,
            fgcolor = Uikit.SECONDARY,
        }
        local value = TextWidget:new{
            text = item.value,
            face = face,
            bold = true,
        }
        local piece = label:getWidth() + Size.padding.small + value:getWidth()
        local gap = 0
        if i > 1 then
            gap = 2 * Size.span.horizontal_small + measuredWidth("·", face, false)
        end
        if used + gap + piece > width then break end

        if i > 1 then
            row[#row + 1] = HorizontalSpan:new{ width = Size.span.horizontal_small }
            row[#row + 1] = TextWidget:new{
                text = "·",
                face = face,
                fgcolor = Uikit.SECONDARY,
            }
            row[#row + 1] = HorizontalSpan:new{ width = Size.span.horizontal_small }
        end
        row[#row + 1] = label
        row[#row + 1] = HorizontalSpan:new{ width = Size.padding.small }
        row[#row + 1] = value
        used = used + gap + piece
    end
    if used == 0 then return nil end
    return row
end

-- The tag fold. Closed, it shows the tags that fit plus a count of the rest;
-- open, the whole list up to the card's limit. Tapping it toggles in place
-- without opening the work: the tap area is a child of the card, so it
-- consumes the tap before the menu row does.
function Ao3MenuItem:buildTagBox(work, metrics, width)
    local tags = work.tag_list
    if not tags or #tags == 0 then return nil end

    local expanded = self.entry.tags_expanded == true
    local face = Font:getFace("smallinfofont", metrics.info_size)
    local text_w = tagTextWidth(width, metrics)
    local glyph = TextWidget:new{
        text = expanded and "-" or "+",
        face = Font:getFace("cfont", metrics.info_size),
        bold = true,
        fgcolor = Uikit.SECONDARY,
    }

    local text
    if expanded then
        text = TextBoxWidget:new{
            text = table.concat(tags, ", "),
            face = face,
            width = text_w,
            height = AO3_CARD_TAG_LINES * metrics.tag_line_h,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
            fgcolor = Blitbuffer.COLOR_GRAY_6,
        }
    else
        text = TextWidget:new{
            text = fittedTags(tags, face, text_w),
            face = face,
            fgcolor = Blitbuffer.COLOR_GRAY_6,
            max_width = text_w,
        }
    end

    local inner_w = width - 2 * (metrics.tag_border + metrics.tag_pad)
    local row = HorizontalGroup:new{ align = "top" }
    row[#row + 1] = text
    row[#row + 1] = HorizontalSpan:new{
        width = math.max(0, inner_w - text:getSize().w - glyph:getWidth()),
    }
    row[#row + 1] = glyph

    local frame = FrameContainer:new{
        bordersize = metrics.tag_border,
        color = Blitbuffer.COLOR_DARK_GRAY,
        background = Blitbuffer.COLOR_WHITE,
        margin = 0,
        padding = metrics.tag_pad,
        row,
    }
    self.tags_text_widget = text
    return Uikit.tapArea(frame, width, frame:getSize().h, function()
        self:toggleTags()
    end)
end

function Ao3MenuItem:buildCard(metrics)
    local width = self.content_width
    local work = self.entry.ao3_work or {}
    local author = trim(self.entry.mandatory or "")
    local summary = trim(self.entry.summary or "")

    local grid = self:buildSymbols(work, metrics)
    local text_w = width
    if grid then
        text_w = math.max(1, width - metrics.symbol_w - Size.padding.large)
    end

    local title = trim(self.entry.text or "")
    local title_widget = TextWidget:new{
        text = title ~= "" and title or _("Untitled"),
        face = Font:getFace("smallinfofont", metrics.title_size),
        bold = true,
        max_width = text_w,
    }
    -- "by" is the catalogue's word for it, and the byline keeps the right
    -- edge of the card even when the title stops early.
    local author_widget = TextWidget:new{
        text = T(_("by %1"), author ~= "" and author or _("Anonymous")),
        face = Font:getFace("smallinfofont", metrics.info_size),
        fgcolor = Blitbuffer.COLOR_GRAY_6,
        max_width = text_w,
    }
    self.title_widget = title_widget
    self.author_widget = author_widget

    local title_block
    if titleSharesByline(self.entry, metrics, text_w) then
        -- One line: the title on the left, the byline flush right, with the
        -- remaining width as the gap between them.
        title_widget.max_width = math.max(1, text_w
            - author_widget:getWidth() - Size.span.horizontal_default)
        title_block = HorizontalGroup:new{ align = "center" }
        title_block[#title_block + 1] = title_widget
        title_block[#title_block + 1] = HorizontalSpan:new{
            width = math.max(0, text_w - title_widget:getWidth()
                - author_widget:getWidth()),
        }
        title_block[#title_block + 1] = author_widget
    else
        local byline = HorizontalGroup:new{ align = "center" }
        byline[#byline + 1] = HorizontalSpan:new{
            width = math.max(0, text_w - author_widget:getWidth()),
        }
        byline[#byline + 1] = author_widget
        title_block = VerticalGroup:new{ align = "left" }
        title_block[#title_block + 1] = title_widget
        title_block[#title_block + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
        title_block[#title_block + 1] = byline
    end

    local top = HorizontalGroup:new{ align = "top" }
    if grid then
        top[#top + 1] = grid
        top[#top + 1] = HorizontalSpan:new{ width = Size.padding.large }
    end
    top[#top + 1] = title_block

    -- The body hangs from the title's left edge, under the symbol margin.
    local body = VerticalGroup:new{ align = "left" }
    local function addBlock(widget, gap)
        body[#body + 1] = VerticalSpan:new{
            width = #body == 0 and Size.span.vertical_large or gap,
        }
        body[#body + 1] = widget
    end

    local fandom = trim(work.fandoms or "")
    local ships = trim(work.relationships or "")
    if fandom ~= "" and ships ~= "" and metadataSharesLine(self.entry, metrics, text_w) then
        -- Both classifications on one line, separated by the same dot the
        -- relationships themselves use.
        self.fandom_widget = TextWidget:new{
            text = work.fandoms,
            face = Font:getFace("smallinfofont", metrics.info_size),
            fgcolor = Blitbuffer.COLOR_GRAY_6,
            max_width = text_w,
        }
        self.ships_widget = TextWidget:new{
            text = work.relationships,
            face = Font:getFace("smallinfofont", metrics.info_size),
            fgcolor = Blitbuffer.COLOR_GRAY_6,
            max_width = text_w,
        }
        local meta = HorizontalGroup:new{ align = "center" }
        meta[#meta + 1] = self.fandom_widget
        meta[#meta + 1] = TextWidget:new{
            text = " · ",
            face = Font:getFace("smallinfofont", metrics.info_size),
            fgcolor = Blitbuffer.COLOR_GRAY_6,
        }
        meta[#meta + 1] = self.ships_widget
        addBlock(meta, Size.span.vertical_default)
    else
        if fandom ~= "" then
            self.fandom_widget = TextWidget:new{
                text = work.fandoms,
                face = Font:getFace("smallinfofont", metrics.info_size),
                fgcolor = Blitbuffer.COLOR_GRAY_6,
                max_width = text_w,
            }
            addBlock(self.fandom_widget, Size.span.vertical_default)
        end
        if ships ~= "" then
            self.ships_widget = TextWidget:new{
                text = work.relationships,
                face = Font:getFace("smallinfofont", metrics.info_size),
                fgcolor = Blitbuffer.COLOR_GRAY_6,
                max_width = text_w,
            }
            addBlock(self.ships_widget, Size.span.vertical_default)
        end
    end
    local tag_box = self:buildTagBox(work, metrics, text_w)
    if tag_box then
        self.tags_widget = tag_box
        addBlock(tag_box, Size.span.vertical_large)
    end
    if summary ~= "" then
        self.summary_widget = TextBoxWidget:new{
            text = summary,
            face = Font:getFace("smallinfofont", metrics.summary_size),
            width = text_w,
            height = metrics.summary_h,
            height_adjust = true,
            height_overflow_show_ellipsis = true,
            alignment = "left",
            fgcolor = Blitbuffer.COLOR_GRAY_6,
        }
        addBlock(self.summary_widget, Size.span.vertical_large)
    end
    local stats = self:buildStats(work, metrics, text_w)
    if stats then
        self.stats_widget = stats
        addBlock(stats, Size.span.vertical_large)
    end
    body[#body + 1] = VerticalSpan:new{ width = metrics.top_pad }

    local content = VerticalGroup:new{ align = "left" }
    content[#content + 1] = VerticalSpan:new{ width = metrics.top_pad }
    content[#content + 1] = top
    if grid then
        local indented = HorizontalGroup:new{ align = "top" }
        indented[#indented + 1] = HorizontalSpan:new{
            width = metrics.symbol_w + Size.padding.large,
        }
        indented[#indented + 1] = body
        content[#content + 1] = indented
    else
        content[#content + 1] = body
    end
    return content
end

-- Open or close the tags in place. The menu owns paging, so its heights are
-- recomputed and the page that now holds this card is redrawn; the work is
-- not opened and Back still returns to the screen that opened the listing.
function Ao3MenuItem:toggleTags()
    local entry, menu = self.entry, self.menu
    if not entry or not menu then return end
    entry.tags_expanded = not entry.tags_expanded

    if menu.setupItemHeights then menu:setupItemHeights() end
    if menu.getPageNumber and entry.idx then
        menu.page = menu:getPageNumber(entry.idx)
    end
    menu:updateItems()
end

-- An index record: a bold name allowed to run to two lines and closed with an
-- ellipsis after that, and its count in the right-hand column like every other
-- row. The fandom browser and an author's fandoms and series share it, so a
-- long name gets a second line instead of being cut after one.
function Ao3MenuItem:buildIndex(metrics)
    local width = self.content_width
    local count = trim(tostring(self.entry.mandatory or ""))

    self.fandom_count_widget = count ~= "" and TextWidget:new{
        text = count,
        face = Font:getFace("infont", metrics.info_size),
    } or nil
    local count_w = self.fandom_count_widget and self.fandom_count_widget:getWidth() or 0
    local gap = count_w > 0 and Size.span.horizontal_default or 0

    self.fandom_name_widget = TextBoxWidget:new{
        text = trim(self.entry.text or ""),
        face = Font:getFace("smallinfofont", metrics.title_size),
        bold = true,
        width = math.max(1, width - count_w - gap),
        height = metrics.fandom_name_h,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        alignment = "left",
    }

    -- The count sits on the record's first line. Centring it against a
    -- two-line name would float it between the lines and read as a stray
    -- number in the middle of the row.
    local row = HorizontalGroup:new{ align = "top" }
    row[#row + 1] = self.fandom_name_widget
    if self.fandom_count_widget then
        row[#row + 1] = HorizontalSpan:new{ width = gap }
        row[#row + 1] = self.fandom_count_widget
    end
    return row
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
    self.icons_dir = (self.menu and self.menu.ao3_icons_dir)
        or "plugins/ao3.koplugin/assets/icons/"
    local metrics = ao3CardMetrics(self.font_size, self.infont_size, self.linesize)
    self.ao3_metrics = metrics

    local content
    if self.entry.ao3_panel then
        -- A built panel (work page sections and actions). It carries its own
        -- spacing; the menu only supplies the focus underline.
        content = self.entry.ao3_panel
    elseif self.entry.ao3_work then
        content = self:buildCard(metrics)
    elseif self.entry.ao3_fandom or self.entry.ao3_series then
        content = self:buildIndex(metrics)
    else
        content = self:buildCompact(metrics)
    end
    self.content_group = content

    local content_h = math.max(1, self.dimen.h - self.linesize)
    local content_dimen = Geom:new{ x = 0, y = 0, w = self.content_width, h = content_h }
    -- Cards keep the title at a consistent top edge. Compact rows stay
    -- left-aligned like native menu rows and centre vertically.
    local content_holder
    if self.entry.ao3_work or self.entry.ao3_panel then
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
        color = self.entry.line_color or self.line_color,
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
    self._underline_container.color = self.entry.line_color or self.line_color
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

function Ao3WorkMenu:fandomContentWidth()
    local width = self.item_dimen and self.item_dimen.w or Screen:getWidth()
    return math.max(1, width - 2 * Size.padding.fullscreen)
end

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
        if item.ao3_tabs then
            -- The author tab strip is a row of its own above the content. A
            -- sticky strip (the fandom letter index) is painted above every
            -- page instead, so it pays for its height once and never scrolls
            -- out of reach.
            item.height = item.ao3_tabs:getSize().h + Size.span.vertical_default
            if item.ao3_sticky then
                budget = math.max(1, budget - item.height)
            end
        elseif item.ao3_static then
            -- A prebuilt, non-selectable block (hero, stats, folded text).
            item.height = item.ao3_static:getSize().h
        elseif item.ao3_panel then
            -- A selectable block (action bar, section header); the extra
            -- line is the focus underline.
            item.height = item.ao3_panel:getSize().h + self.linesize
        elseif item.ao3_work then
            item.height = ao3CardHeight(item, metrics, self:fandomContentWidth())
        elseif item.ao3_fandom or item.ao3_series then
            -- An index record: one line for most names, two when the name
            -- needs it, never more.
            item.height = fandomNameLines(item, self:fandomContentWidth(),
                metrics) == 2 and metrics.fandom_two_line_h or metrics.fandom_one_line_h
        else
            item.height = compact_h
        end
        if item.ao3_sticky then
            -- Not part of the paged item list; updateItems paints it first.
        elseif #items > 0 and used + item.height > budget then
            -- A group label travels with the first row of its group: a page
            -- must not end on a label whose content is overleaf.
            local carry
            local last = self.item_table[items[#items]]
            if last and last.keep_with_next then
                carry = table.remove(items)
                used = used - (last.height or 0)
            end
            if #items > 0 then
                self.page_items[#self.page_items + 1] = items
            end
            items = carry and { carry, index } or { index }
            used = item.height + (carry and (last.height or 0) or 0)
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

    -- A sticky strip (the fandom letter index) is painted above every page so
    -- the reader can change letters without paging back to the top.
    local first = self.item_table[1]
    if first and first.ao3_sticky and first.ao3_tabs then
        local strip = first.ao3_tabs
        strip.dimen = Geom:new{
            x = 0, y = 0,
            w = self.item_dimen.w,
            h = first.height or strip:getSize().h,
        }
        table.insert(self.item_group, strip)
    end

    for idx, index in ipairs(page_items) do
        local item = self.item_table[index]
        if item then
            item.idx = index
            if index == self.itemnumber then
                select_number = idx
            end
            if item.ao3_tabs then
                -- The tab strip paints itself; it is not a focusable row, so
                -- DPad navigation stays on the content below it.
                local strip = item.ao3_tabs
                strip.dimen = Geom:new{
                    x = 0, y = 0,
                    w = self.item_dimen.w,
                    h = item.height or strip:getSize().h,
                }
                table.insert(self.item_group, strip)
            elseif item.ao3_static then
                -- Static page content (hero, stats, folded text): painted,
                -- never focused.
                table.insert(self.item_group, item.ao3_static)
            else
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

-- One selectable card per work: title, author, bounded summary. Shared by
-- plain listings and the author screen's Works/Bookmarks tabs.
function Ao3:workRow(work)
    local summary = trim(work.summary or "")
    return {
        text = work.title,
        mandatory = work.authors,
        ao3_work = work,
        summary = summary ~= "" and shorten(summary, AO3_CARD_SUMMARY_CHARS) or nil,
        -- The setting is the default; a tap on this card's tag box changes
        -- only this row, until the listing is fetched again.
        tags_expanded = self.prefs and self.prefs.tags_expanded == true or false,
        action = function()
            self:showWork(work)
        end,
    }
end

function Ao3:listingRows(listing, fallback_title)
    local rows = {}
    for _, work in ipairs(listing.items) do
        rows[#rows + 1] = self:workRow(work)
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
    return rows, title
end

function Ao3:showListing(listing, fallback_title, replace)
    local rows, title = self:listingRows(listing, fallback_title)
    if replace then
        self:replaceRows(title, rows)
    else
        self:pushRows(title, rows)
    end
end

-- ---------------------------------------------------------------------------
-- Account
-- ---------------------------------------------------------------------------
--
-- Signing in is optional. Out of the box the plugin browses public AO3 like
-- before; after Sign in, the session cookie is attached to every request so
-- the personal lists below can be opened. No request is made until the user
-- taps a row.

local ACCOUNT_LISTS = {
    bookmarks = {
        label = _("Bookmarks"),
        path = "/bookmarks",
        loading = _("Loading bookmarks…"),
        empty = _("No bookmarks."),
    },
    marked = {
        label = _("Marked for Later"),
        path = "/marked_for_later",
        loading = _("Loading marked works…"),
        empty = _("Nothing marked for later."),
    },
    history = {
        label = _("History"),
        path = "/readings",
        loading = _("Loading history…"),
        empty = _("No reading history."),
    },
    subscriptions = {
        label = _("Subscriptions"),
        path = "/subscriptions",
        loading = _("Loading subscriptions…"),
        empty = _("No subscriptions."),
    },
}

function Ao3:loginDialog()
    local dialog
    dialog = MultiInputDialog:new{
        title = _("Sign in to AO3"),
        fields = {
            {
                description = _("Username or email"),
                hint = _("AO3 username"),
            },
            {
                description = _("Password"),
                text_type = "password",
                hint = _("Password"),
            },
        },
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(dialog)
                    end,
                },
                {
                    text = _("Sign in"),
                    is_enter_default = true,
                    callback = function()
                        local fields = dialog:getFields()
                        UIManager:close(dialog)
                        self:signIn(fields[1], fields[2])
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    if dialog.onShowKeyboard then
        dialog:onShowKeyboard()
    end
end

-- Sign-in uses AO3's JSON token endpoint instead of loading /users/login.
-- That page is challenged for this client; the token endpoint is not. The
-- password lives only in this call and is never written to settings.
function Ao3:performLogin(login, password)
    local token_body, token_err, token_code, token_headers = self:httpRequest(
        Account.TOKEN_URL, {
            redirect = true,
            headers = {
                ["Accept"] = "application/json, text/javascript, */*; q=0.01",
            },
        }, 30)
    if not token_body then return nil, token_err end

    local token = Account.parseToken(token_body)
    if not token then
        return nil, _("Could not read AO3's sign-in token. Try again in a moment.")
    end

    local jar = Account.mergeCookies({}, token_headers and token_headers["set-cookie"])

    local cookie = Account.cookieHeader(jar)
    cookie = cookie and (cookie .. "; " .. REQUEST_COOKIE) or REQUEST_COOKIE
    local body = Account.loginBody(token, login, password)
    local response, post_err, code, post_headers = self:httpRequest(Account.LOGIN_URL, {
        method = "POST",
        body = body,
        redirect = false,
        retry_on_403 = false,
        cookie = cookie,
        headers = {
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Referer"] = Account.LOGIN_URL,
            ["Origin"] = Account.BASE_URL,
            ["Content-Length"] = tostring(#body),
        },
    }, 30)
    jar = Account.mergeCookies(jar, post_headers and post_headers["set-cookie"])

    if code == 301 or code == 302 or code == 303 or code == 307 or code == 308 then
        if not Account.isSignedIn({ cookies = jar }) then
            return nil, _("AO3 accepted the form but returned no session. Check the username and password.")
        end
        -- A redirect alone is not proof: the anonymous form cookie is already
        -- in the jar, so a failed sign-in can redirect back to the form. Load
        -- the destination once and require AO3's logged-in greeting.
        local location = post_headers and post_headers["location"]
        if not location then
            return nil, _("AO3 did not say where the sign-in went. Try again.")
        end
        local verify_url = socketurl.absolute(Account.LOGIN_URL, location)
        local verified, verify_err = self:httpRequest(verify_url, {
            cookie_jar = jar,
            redirect = true,
        }, 30)
        if not verified then return nil, verify_err end
        local name = Account.loggedInName(verified)
        if not name and not verified:find('class="logged-in"', 1, true) then
            return nil, _("AO3 did not confirm the sign-in. Check the username and password.")
        end
        return {
            username = name or trim(login),
            cookies = jar,
            saved_at = os.time(),
        }
    end
    if post_err then return nil, post_err end

    -- A rejected sign-in re-renders the form with a flash error. Occasionally
    -- a server answers 200 with the signed-in page instead.
    local name = response and Account.loggedInName(response)
    if name then
        return { username = name, cookies = jar, saved_at = os.time() }
    end
    local message = response and Account.loginError(response)
    if message then return nil, message end
    return nil, T(_("Unexpected response from AO3 (HTTP %1)."), code or "?")
end

function Ao3:signIn(login, password)
    login, password = trim(login), password or ""
    if login == "" or password == "" then
        UIManager:show(InfoMessage:new{
            text = _("Enter your AO3 username and password."),
        })
        return
    end

    NetworkMgr:runWhenOnline(function()
        local Trapper = require("ui/trapper")
        local session, err
        Trapper:wrap(function()
            Trapper:info(_("Signing in to AO3…"))
            local ok, result, message = pcall(function()
                return self:performLogin(login, password)
            end)
            if ok then
                session, err = result, message
            else
                err = tostring(result)
            end
            Trapper:reset()
        end)
        NetworkMgr:afterWifiAction()

        if session then
            self.session = session
            self:clearWorkActionCache()
            Account.save(Account.settingsPath(), session)
            self:showHome()
            UIManager:show(InfoMessage:new{
                text = T(_("Signed in as %1."), session.username),
            })
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Could not sign in:\n%1"), err or _("unknown error")),
            })
        end
    end)
end

function Ao3:signOut()
    self.session = nil
    self:clearWorkActionCache()
    Account.clear()
    self:showHome()
    UIManager:show(InfoMessage:new{
        text = _("Signed out of AO3. Saved works are still available."),
    })
end

function Ao3:showAccount()
    if not self.session then
        self:loginDialog()
        return
    end
    local font_size = (self.menu and self.menu.font_size) or 20
    local width = Screen:getWidth() - 2 * Size.padding.fullscreen
    local name = self.session.username or _("your account")
    self:pushRows(_("Account"), AccountPage.build{
        name = name,
        width = width,
        font_size = font_size,
        on_list = function(kind) self:showAccountList(kind) end,
        on_works = function()
            self:showAuthor(name, BASE_URL .. "/users/" .. name)
        end,
        on_logout = function() self:signOut() end,
    })
end

function Ao3:settingsRows()
    return SettingsPage.build{
        tags_expanded = self.prefs and self.prefs.tags_expanded == true,
        on_toggle = function() self:toggleTagsDefault() end,
    }
end

-- The default is stored the moment it changes; the settings row is rebuilt in
-- place so its On/Off value follows the tap.
function Ao3:toggleTagsDefault()
    self.prefs = self.prefs or Preferences.load()
    self.prefs.tags_expanded = not self.prefs.tags_expanded
    Preferences.save(self.prefs)
    if self.menu then
        self:replaceRows(_("Settings"), self:settingsRows())
    end
end

function Ao3:showSettings()
    self:pushRows(_("Settings"), self:settingsRows())
end

function Ao3:learnAccountName(html)
    local name = Account.loggedInName(html)
    if name and self.session and name ~= self.session.username then
        self.session.username = name
        Account.save(Account.settingsPath(), self.session)
    end
end

function Ao3:accountParser(kind)
    return function(html)
        if Account.isLostCookiePage(html) then
            -- AO3 ended the session because a required marker cookie was
            -- missing. Retrying with the same jar cannot help.
            self.session = nil
            self:clearWorkActionCache()
            Account.clear()
            return nil, _("AO3 ended the saved session. Sign in again from Account.")
        end
        if Account.isLoginPage(html) then
            -- The cookie is stale or revoked. Drop it so Home offers Sign in
            -- instead of silently showing empty lists.
            self.session = nil
            self:clearWorkActionCache()
            Account.clear()
            return nil, _("Your AO3 session has expired. Sign in again from Account.")
        end
        self:learnAccountName(html)
        if kind == "bookmarks" then
            return AuthorPage.parseBookmarks(html)
        elseif kind == "subscriptions" then
            return AuthorPage.parseSubscriptions(html)
        end
        return self:parseListing(html)
    end
end

function Ao3:loadAccountList(kind, url, replace)
    local meta = ACCOUNT_LISTS[kind]
    if not meta then return end
    if not Account.isSignedIn(self.session) then
        UIManager:show(InfoMessage:new{
            text = _("Your AO3 session has expired. Sign in again."),
        })
        self:showHome()
        self:loginDialog()
        return
    end
    url = url or Account.listUrl(self.session.username, meta.path)
    if not url then return end
    self:fetchPage(url, self:accountParser(kind), meta.loading, function(data)
        self:showAccountRows(kind, data, replace)
    end, function()
        -- accountParser drops the stale session, so return to a Home screen
        -- that offers Sign in rather than leaving a dead Account page open.
        if not Account.isSignedIn(self.session) then
            self:showHome()
        end
    end)
end

function Ao3:showAccountList(kind)
    self:loadAccountList(kind, nil, false)
end

function Ao3:accountRows(kind, data)
    local meta = ACCOUNT_LISTS[kind]
    -- Translate outside the loop: `for _, item` shadows gettext `_`.
    local series_label = _("Series")
    local author_label = _("Author")
    local rows = {}
    for _, item in ipairs(data.items) do
        if item.kind == "series" then
            rows[#rows + 1] = {
                text = item.title,
                mandatory = series_label,
                action = function()
                    self:loadListing(BASE_URL .. item.url, item.title)
                end,
            }
        elseif item.kind == "user" then
            rows[#rows + 1] = {
                text = item.title,
                mandatory = author_label,
                action = function()
                    self:showAuthor(item.name, BASE_URL .. "/users/" .. item.name)
                end,
            }
        else
            rows[#rows + 1] = self:workRow(item)
        end
    end
    if #rows == 0 then
        rows[1] = { text = meta.empty }
    end

    if data.next_url then
        rows[#rows + 1] = {
            text = _("Next page →"),
            action = function()
                self:loadAccountList(kind, data.next_url, true)
            end,
        }
    end
    if data.prev_url then
        rows[#rows + 1] = {
            text = _("← Previous page"),
            action = function()
                self:loadAccountList(kind, data.prev_url, true)
            end,
        }
    end
    return rows
end

function Ao3:showAccountRows(kind, data, replace)
    local meta = ACCOUNT_LISTS[kind]
    local name = self.session and self.session.username or _("Account")
    local rows = self:accountRows(kind, data)

    local title = T(_("%1 · %2"), meta.label, name)
    if data.count then
        title = T(_("%1 · %2"), title, data.count)
    end
    if replace then
        self:replaceRows(title, rows)
    else
        self:pushRows(title, rows)
    end
end

-- ---------------------------------------------------------------------------
-- Author screen
-- ---------------------------------------------------------------------------
--
-- Four tabs: Dashboard (default), Works, Series, Bookmarks, as one page rather
-- than four lists: the same masthead, solid bar and tab strip on every tab, so
-- the screen always says whose page it is and which shelf is open. Each tab's
-- page is fetched at most once per author visit.

function Ao3:showAuthor(name, profile)
    local base = AuthorPage.profileUrl(profile or "")
    if not base then return end
    if not base:match("^https?://") then
        base = BASE_URL .. base
    end
    self.author = {
        name = (name and name ~= "") and name or base,
        profile = base,
        tab = "dashboard",
        cache = {},
    }
    self:renderAuthorTab("dashboard", false)
end

function Ao3:renderAuthorTab(tab_id, replace)
    local author = self.author
    if not author then return end
    author.tab = tab_id
    local cached = author.cache[tab_id]
    if cached then
        self:showAuthorRows(tab_id, cached, replace)
        return
    end

    local url, parse, label
    if tab_id == "dashboard" then
        url = author.profile .. "?expand_fandoms=true"
        parse = function(html) return AuthorPage.parseFandoms(html) end
        label = _("Loading fandoms…")
    elseif tab_id == "works" then
        url = AuthorPage.tabUrl(author.profile, "works")
        parse = function(html) return self:parseListing(html) end
        label = _("Loading works…")
    elseif tab_id == "series" then
        url = AuthorPage.tabUrl(author.profile, "series")
        parse = function(html) return AuthorPage.parseSeries(html) end
        label = _("Loading series…")
    elseif tab_id == "bookmarks" then
        url = AuthorPage.tabUrl(author.profile, "bookmarks")
        parse = function(html) return AuthorPage.parseBookmarks(html) end
        label = _("Loading bookmarks…")
    end
    if not url then return end

    self:fetchPage(url, parse, label, function(data)
        author.cache[tab_id] = data
        self:showAuthorRows(tab_id, data, replace)
    end)
end

function Ao3:showAuthorRows(tab_id, data, replace)
    local author = self.author
    local font_size = (self.menu and self.menu.font_size) or 20
    local width = Screen:getWidth() - 2 * Size.padding.fullscreen

    local rows = AuthorPage.build{
        tab = tab_id,
        name = author.name,
        data = data,
        width = width,
        font_size = font_size,
        on_tab = function(selected) self:renderAuthorTab(selected, true) end,
        on_listing = function(url, title)
            self:loadListing(BASE_URL .. url, title)
        end,
        on_page = function(url) self:loadAuthorPage(tab_id, url) end,
        work_row = function(work) return self:workRow(work) end,
    }

    -- The masthead names the author and the strip shows the tab, so the title
    -- bar names the shelf and nothing else.
    local title = AuthorPage.tabTitle(tab_id)
    if replace then
        self:replaceRows(title, rows)
    else
        self:pushRows(title, rows)
    end
end

-- Another page of the open shelf replaces that shelf's rows, so the masthead,
-- the strip and the title bar stay put and Back still returns to the screen
-- that opened the author page.
function Ao3:loadAuthorPage(tab_id, url)
    local author = self.author
    if not author then return end
    local parse, label
    if tab_id == "works" then
        parse = function(html) return self:parseListing(html) end
        label = _("Loading works…")
    elseif tab_id == "series" then
        parse = function(html) return AuthorPage.parseSeries(html) end
        label = _("Loading series…")
    elseif tab_id == "bookmarks" then
        parse = function(html) return AuthorPage.parseBookmarks(html) end
        label = _("Loading bookmarks…")
    else
        return
    end
    self:fetchPage(url, parse, label, function(data)
        author.cache[tab_id] = data
        self:showAuthorRows(tab_id, data, true)
    end)
end

function Ao3:showWork(work)
    self:showWorkPage(work, false)
end

-- The four buttons on the work page map onto the account module's toggles.
-- The cached state decides the direction: an action that is already on is
-- the one whose tap turns it off.
function Ao3:workSocial(work)
    local cached = self.work_social
        and self.work_social[tostring(work and work.id or "")]
    if cached then return cached end
    local state = self:workActionState(work)
    if not state then return {} end
    return {
        kudos = state.kudos_done == true,
        bookmark = state.bookmark and state.bookmark.bookmarked == true,
        subscribe = state.subscribe and state.subscribe.subscribed == true,
        later = state.marked_for_later == true,
    }
end

function Ao3:workSocialAction(work, id)
    local social = self:workSocial(work)
    local action
    if id == "kudos" then
        action = "kudos"
    elseif id == "bookmark" then
        action = social.bookmark and "unbookmark" or "bookmark"
    elseif id == "subscribe" then
        action = social.subscribe and "unsubscribe" or "subscribe"
    elseif id == "later" then
        action = social.later and "mark_as_read" or "mark_for_later"
    end
    if not action then return end
    self:workAction(work, action, function(result)
        if result then
            -- Redraw so the checkmark appears (or disappears) at once.
            self:showWorkPage(work, true)
        end
    end)
end

-- Opening a work while signed in reads the page's action state once, so the
-- four buttons show accurate checkmarks without a tap. Failures stay quiet:
-- the page itself still works, and the buttons report their own errors.
function Ao3:ensureWorkSocialLoaded(work)
    if not Account.isSignedIn(self.session) or not work or not work.id then
        return
    end
    if self:workActionState(work) then return end
    if self.work_social
        and self.work_social[tostring(work.id)] then
        return
    end
    if NetworkMgr.isConnected and not NetworkMgr:isConnected() then return end

    local id = tostring(work.id)
    self.work_social_loading = self.work_social_loading or {}
    if self.work_social_loading[id] then return end
    self.work_social_loading[id] = true
    self:loadWorkActionState(work, function()
        self.work_social_loading[id] = nil
        if self.work_state and tostring(self.work_state.id) == id
            and self.menu and self.menu.ao3_title == _("Work details") then
            self:showWorkPage(work, true)
        end
    end, { silent = true })
end

-- Folded sections are rebuilt in place: the page keeps its position on the
-- navigation stack, so Back still returns to the listing that opened it.
-- `focus` names the section that was just toggled, so the page lands on the
-- text that appeared (or on the header that hid it).
function Ao3:showWorkPage(work, replace, focus)
    if not replace then
        self:ensureWorkSocialLoaded(work)
    end
    local state = self.work_state
    if not state or state.id ~= work.id then
        state = { id = work.id, summary = false, tags = false }
        self.work_state = state
    end

    local font_size = (self.menu and self.menu.font_size) or 20
    local width = Screen:getWidth() - 2 * Size.padding.fullscreen
    local rows = WorkPage.build{
        work = work,
        width = width,
        font_size = font_size,
        -- A menu row taller than a page is clipped, so the folded text is
        -- bounded and the remainder opens in a scrollable TextViewer.
        body_max_height = math.floor(Screen:getHeight() * 0.44),
        cached = findCachedWork(getDownloadDir(), work.id),
        state = state,
        on_read = function() self:readWork(work.id, work.title) end,
        on_refresh = function() self:readWork(work.id, work.title, true) end,
        on_toggle = function(section)
            state[section] = not state[section]
            self:showWorkPage(work, true, section)
        end,
        on_full_text = function(title, text)
            UIManager:show(TextViewer:new{ title = title, text = text })
        end,
        on_author = function(name, url) self:showAuthor(name, url) end,
        signed_in = Account.isSignedIn(self.session),
        social = self:workSocial(work),
        on_action = function(action) self:workSocialAction(work, action) end,
    }

    local title = _("Work details")
    if replace then
        -- Prefer the body that just appeared; fall back to its header.
        local anchor = 1
        if focus then
            for i, row in ipairs(rows) do
                if row.role == focus then anchor = i end
                if row.role == focus .. "_body" then anchor = i end
            end
        end
        self:replaceRows(title, rows, anchor)
        -- switchItemTable picks the page from the previous table's layout;
        -- with the new layout in place, follow the anchor to its real page.
        local menu = self.menu
        if menu and menu.page_items then
            for page, items in ipairs(menu.page_items) do
                local found = false
                for _, index in ipairs(items) do
                    if index == anchor then
                        found = true
                        break
                    end
                end
                if found then
                    if menu.page ~= page then
                        menu:onGotoPage(page)
                    end
                    break
                end
            end
        end
    else
        self:pushRows(title, rows)
    end
end

-- ---------------------------------------------------------------------------
-- Work actions: kudos, bookmark, subscribe, Marked for Later
-- ---------------------------------------------------------------------------
--
-- Everything below is the same form post the website makes. The work page
-- carries the current state (bookmarked? subscribed? on the read-later list?)
-- and the pseud a bookmark belongs to; one fetch of it fills those. The CSRF
-- token comes from /token_dispenser.json, which is small and is cached until
-- the session cookie changes. AO3's work-page tokens are form-scoped, so a
-- token copied from one form can be rejected by another (a live kudos post
-- proved that).
--
-- No UI lives here: `workAction` reports through `on_done(result, err)` and a
-- short InfoMessage, so the work-page buttons can be drawn independently.

local WORK_ACTION_DONE = {
    kudos = _("Kudos left."),
    bookmark = _("Bookmarked."),
    unbookmark = _("Bookmark removed."),
    subscribe = _("Subscribed."),
    unsubscribe = _("Unsubscribed."),
    mark_for_later = _("Added to Marked for Later."),
    mark_as_read = _("Removed from Marked for Later."),
}

local REDIRECT_OK = {
    [301] = true, [302] = true, [303] = true, [307] = true, [308] = true,
}

local function jsonField(body, key)
    if not body then return nil end
    local value = body:match('"' .. key .. '"%s*:%s*"([^"]*)"')
    return value and value:gsub("\\(.)", "%1")
end

local function jsonNumber(body, key)
    if not body then return nil end
    return body:match('"' .. key .. '"%s*:%s*(%d+)')
end

local function jsonErrors(body)
    if not body then return nil end
    local list = body:match('"errors"%s*:%s*%[(.-)%]')
    if not list then return jsonField(body, "error_message") end
    local messages = {}
    for message in list:gmatch('"([^"]*)"') do
        messages[#messages + 1] = message:gsub("\\(.)", "%1")
    end
    return #messages > 0 and table.concat(messages, " ") or nil
end

function Ao3:workActionState(work)
    if not work or not work.id or not self.work_actions then return nil end
    return self.work_actions[tostring(work.id)]
end

-- Bookmark and subscription ids belong to one account. Drop them whenever
-- the session changes, so logging out and in as someone else cannot reuse the
-- previous user's ids.
function Ao3:clearWorkActionCache()
    self.work_actions = nil
    self.work_social_loading = nil
    self.csrf_token = nil
    self.csrf_fingerprint = nil
end

function Ao3:rememberWorkState(work, state)
    self.work_actions = self.work_actions or {}
    self.work_actions[tostring(work.id)] = state
end

-- The token endpoint exists exactly for cached pages: it is small, and its
-- token is valid for this session. Cache it; a changed session cookie means a
-- new token is needed.
function Ao3:csrfToken(force)
    self.csrf_fingerprint = self.csrf_fingerprint or ""
    local fingerprint = (self.session and self.session.cookies
        and self.session.cookies._otwarchive_session) or ""
    if not force and self.csrf_token and self.csrf_fingerprint == fingerprint then
        return self.csrf_token
    end
    local body, err = self:httpRequest(Account.TOKEN_URL, {
        headers = {
            ["Accept"] = "application/json, text/javascript, */*; q=0.01",
        },
        redirect = true,
    }, 30)
    if not body then return nil, err end
    local token = Account.parseToken(body)
    if not token then
        return nil, _("Could not read a form token from AO3. Try again in a moment.")
    end
    self.csrf_token = token
    self.csrf_fingerprint = fingerprint
    return token
end

-- One fetch of the work page, reused for every action on that work. `force`
-- is for the rare case where a form id has gone stale.
function Ao3:ensureWorkState(work, force)
    local id = tostring(work and work.id or "")
    if not id:match("^%d+$") then
        return nil, _("This work has no AO3 id.")
    end
    if not force and self.work_actions and self.work_actions[id] then
        return self.work_actions[id]
    end
    local html, err = self:fetchHtml(Account.workUrl(id), 25)
    if not html then return nil, err end
    local state = Account.parseWorkActions(html)
    if not state then
        return nil, _("Could not read the work's AO3 page.")
    end
    state.work_id = id
    self:rememberWorkState(work, state)
    return state
end

-- Exactly one form post, no UI. Returns a result table on success (with ids
-- AO3 sent back) or nil, message, details.
function Ao3:performWorkAction(work, action, opts)
    opts = opts or {}
    if not Account.isSignedIn(self.session) then
        return nil, _("Sign in to AO3 first.")
    end
    local id = tostring(work and work.id or "")
    if not id:match("^%d+$") then
        return nil, _("This work has no AO3 id.")
    end

    local state
    if action == "bookmark" or action == "unbookmark" or action == "unsubscribe" then
        local err
        state, err = self:ensureWorkState(work)
        if not state then return nil, err end

        if action == "bookmark" then
            if state.bookmark.bookmarked then
                return nil, _("You have already bookmarked this work."),
                    { already = true }
            end
            if not state.bookmark.available then
                return nil, _("AO3 did not show a bookmark form. Sign in again.")
            end
            -- A bookmark needs a pseud. AO3 renders the default one in the
            -- form; use it unless the caller chose another.
            opts.pseud_id = opts.pseud_id or state.bookmark.pseud_id
            if not opts.pseud_id then
                return nil, _("Could not read your AO3 pseud. Reload the work and try again.")
            end
        elseif action == "unbookmark" then
            opts.bookmark_id = opts.bookmark_id or state.bookmark.id
            if not opts.bookmark_id then
                local refresh_err
                state, refresh_err = self:ensureWorkState(work, true)
                if not state then return nil, refresh_err end
                opts.bookmark_id = state.bookmark.id
            end
            if not opts.bookmark_id then
                return nil, _("This work is not bookmarked.")
            end
        elseif action == "unsubscribe" then
            opts.subscription_id = opts.subscription_id or state.subscribe.id
            if not opts.subscription_id then
                local refresh_err
                state, refresh_err = self:ensureWorkState(work, true)
                if not state then return nil, refresh_err end
                opts.subscription_id = state.subscribe.id
            end
            if not opts.subscription_id then
                return nil, _("You are not subscribed to this work.")
            end
            opts.username = opts.username or state.subscribe.username
        end
    end

    if action == "subscribe" or action == "unsubscribe" then
        opts.username = opts.username or self.session.username
        if not opts.username then
            return nil, _("Could not read your AO3 name. Sign in again.")
        end
    end

    local token, token_err = self:csrfToken()
    if not token then return nil, token_err end

    local url, body = Account.workActionRequest(action, id, token, opts)
    if not url then return nil, _("AO3 did not offer that action for this work.") end

    local accept = "text/html, */*;q=0.8"
    if action == "kudos" then
        accept = "text/javascript, application/javascript, */*;q=0.8"
    elseif action == "subscribe" or action == "unsubscribe" then
        accept = "application/json, */*;q=0.8"
    end

    local response, err, code, headers = self:httpRequest(url, {
        method = "POST",
        body = body,
        -- Follow nothing: a redirect already says whether AO3 accepted the
        -- form, and following it would fetch a whole work page for nothing.
        redirect = false,
        -- Never replay a form post. A retried 403 would leave duplicate kudos
        -- or create the same bookmark twice.
        retry_on_403 = false,
        return_error_body = true,
        headers = {
            ["Accept"] = accept,
            ["Content-Type"] = "application/x-www-form-urlencoded",
            ["Referer"] = Account.workUrl(id),
            ["Origin"] = Account.BASE_URL,
        },
    }, 30)

    if not code then return nil, err end

    -- A stale form token should not wedge every later action. Drop it so the
    -- next tap fetches a fresh one; do not retry this post automatically.
    if code == 422 and response then
        local lower = response:lower()
        if lower:find("csrf", 1, true)
            or lower:find("authenticity", 1, true) then
            self.csrf_token = nil
            self.csrf_fingerprint = nil
            return nil, _("AO3 rejected the form token. Tap again."),
                { code = code }
        end
    end

    local result
    if action == "kudos" then
        if code >= 200 and code < 300 then
            result = { action = action, done = true }
        elseif code == 422 then
            local message = jsonField(response, "error_message")
                or _("AO3 did not accept the kudos.")
            if message:lower():find("already left kudos", 1, true) then
                result = {
                    action = action, done = true, already = true,
                    message = message,
                }
            else
                return nil, message, { code = code }
            end
        else
            return nil, err or _("AO3 did not accept the kudos."), { code = code }
        end
    elseif action == "bookmark" then
        if REDIRECT_OK[code] then
            local location = (headers and headers["location"]) or ""
            result = {
                action = action, done = true,
                bookmark_id = location:match("/bookmarks/(%d+)"),
                pseud_id = opts.pseud_id,
            }
        else
            return nil, Account.flashError(response)
                or _("AO3 did not create the bookmark."), { code = code }
        end
    elseif action == "unbookmark" then
        if REDIRECT_OK[code] or (code >= 200 and code < 300) then
            result = { action = action, done = true, bookmark_id = opts.bookmark_id }
        else
            return nil, err or _("AO3 did not remove the bookmark."), { code = code }
        end
    elseif action == "subscribe" then
        if code == 201 or code == 200 then
            result = {
                action = action, done = true,
                subscription_id = jsonNumber(response, "item_id"),
            }
        elseif code == 422 then
            local message = jsonErrors(response)
                or _("AO3 did not create the subscription.")
            if message:lower():find("already", 1, true) then
                result = {
                    action = action, done = true, already = true,
                    message = message,
                }
            else
                return nil, message, { code = code }
            end
        else
            return nil, err or _("AO3 did not create the subscription."),
                { code = code }
        end
    elseif action == "unsubscribe" then
        if code >= 200 and code < 300 then
            result = { action = action, done = true, subscription_id = opts.subscription_id }
        elseif code == 422 then
            return nil, jsonErrors(response) or _("AO3 did not remove the subscription."),
                { code = code }
        else
            return nil, err or _("AO3 did not remove the subscription."), { code = code }
        end
    elseif action == "mark_for_later" or action == "mark_as_read" then
        if REDIRECT_OK[code] or (code >= 200 and code < 300) then
            result = { action = action, done = true }
        else
            return nil, err or _("AO3 did not update Marked for Later."), { code = code }
        end
    else
        return nil, _("Unknown work action.")
    end

    self:applyWorkActionResult(work, action, result)
    return result
end

-- Keep the cached work state in step with what just happened, so the next
-- button press does not need another page load.
function Ao3:applyWorkActionResult(work, action, result)
    local state = self:workActionState(work)
    if not state then return end
    if action == "kudos" then
        state.kudos_done = true
    elseif action == "bookmark" then
        state.bookmark.available = true
        state.bookmark.bookmarked = true
        state.bookmark.id = result.bookmark_id or state.bookmark.id
        state.bookmark.pseud_id = result.pseud_id or state.bookmark.pseud_id
    elseif action == "unbookmark" then
        state.bookmark.bookmarked = false
        state.bookmark.id = nil
    elseif action == "subscribe" then
        state.subscribe.available = true
        state.subscribe.subscribed = true
        state.subscribe.id = result.subscription_id or state.subscribe.id
    elseif action == "unsubscribe" then
        state.subscribe.subscribed = false
        state.subscribe.id = nil
    elseif action == "mark_for_later" then
        state.marked_for_later = true
    elseif action == "mark_as_read" then
        state.marked_for_later = false
    end
end

-- Async wrapper for UI: network check, spinner, one request, a short result.
-- `on_done(result, err, details)` is called on the UI thread. `opts.label`
-- replaces the spinner text; `opts.silent` suppresses the result InfoMessage
-- when the caller wants to update its own row instead.
function Ao3:workAction(work, action, opts, on_done)
    if type(opts) == "function" then opts, on_done = {}, opts end
    opts = opts or {}

    if not Account.isSignedIn(self.session) then
        UIManager:show(InfoMessage:new{
            text = _("Sign in to AO3 to use kudos, bookmarks and subscriptions."),
        })
        if on_done then pcall(on_done, nil, _("Sign in to AO3 first.")) end
        return
    end

    NetworkMgr:runWhenOnline(function()
        local Trapper = require("ui/trapper")
        local result, err, details
        Trapper:wrap(function()
            Trapper:info(opts.label or _("Sending to AO3…"))
            local ok, r, e, d = pcall(function()
                return self:performWorkAction(work, action, opts)
            end)
            if ok then
                result, err, details = r, e, d
            else
                err = tostring(r)
            end
            Trapper:reset()
        end)
        NetworkMgr:afterWifiAction()

        if result then
            if on_done then pcall(on_done, result) end
            if not opts.silent then
                UIManager:show(InfoMessage:new{
                    text = result.message or WORK_ACTION_DONE[action] or _("Done."),
                })
            end
        else
            if on_done then pcall(on_done, nil, err, details) end
            if not opts.silent then
                UIManager:show(InfoMessage:new{
                    text = T(_("AO3 refused:\n%1"), err or _("unknown error")),
                })
            end
        end
    end)
end

-- Load the work page once and cache its action state. The UI can call this
-- when it needs to draw the buttons; the form token is fetched separately and
-- cached for the session.
function Ao3:loadWorkActionState(work, on_done, opts)
    opts = opts or {}
    if not Account.isSignedIn(self.session) then
        if not opts.silent then
            UIManager:show(InfoMessage:new{
                text = _("Sign in to AO3 to use kudos, bookmarks and subscriptions."),
            })
        end
        if on_done then pcall(on_done, nil, _("Sign in to AO3 first.")) end
        return
    end
    self:fetchPage(Account.workUrl(work.id), function(html)
        local state = Account.parseWorkActions(html)
        if not state then
            return nil, _("Could not read the work's AO3 page.")
        end
        state.work_id = tostring(work.id)
        self:rememberWorkState(work, state)
        return state
    end, _("Loading work actions…"), function(state)
        if on_done then pcall(on_done, state) end
    end, function(err)
        if on_done then pcall(on_done, nil, err) end
    end, opts.silent)
end

-- ---------------------------------------------------------------------------
-- Reading a work
-- ---------------------------------------------------------------------------

function Ao3:downloadWork(id, title)
    local dir = getDownloadDir()
    local tmp = dir .. "/" .. id .. ".html.part"
    local old = findCachedWork(dir, id)

    local probe, file_err = io.open(tmp, "wb")
    if not probe then
        return nil, T(_("Cannot write to %1: %2"), dir, tostring(file_err))
    end
    probe:close()

    local url = DOWNLOAD_HOST .. "/downloads/" .. id .. "/work.html"

    -- Stream to disk, but follow redirects here so the session cookie is
    -- recomputed for each host (LuaSocket would copy the original Cookie).
    local function fetch(request_url)
        local file = io.open(tmp, "wb")
        if not file then
            return false, T(_("Cannot write to %1"), dir)
        end
        socketutil:set_timeout(30, 300)
        local ok, code, headers, status = pcall(function()
            return socket.skip(1, http.request{
                url = request_url,
                method = "GET",
                headers = {
                    ["User-Agent"] = UA,
                    ["Accept"] = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                    ["Accept-Language"] = "en-US,en;q=0.9",
                    ["Referer"] = BASE_URL .. "/works/" .. id,
                    -- Restricted works need the signed-in session; AO3's
                    -- FAQ says scripts must send the session cookies.
                    ["Cookie"] = self:cookieHeader(request_url),
                },
                sink = ltn12.sink.file(file),
                redirect = false,
            })
        end)
        socketutil:reset_timeout()
        pcall(function() file:close() end)
        return ok, code, headers, status
    end

    local ok, code, headers, status
    local request_url = url
    for hop = 1, MAX_REDIRECTS + 1 do
        ok, code, headers, status = fetch(request_url)
        if not ok then break end
        if REDIRECT_CODES[code] and headers and headers["location"]
            and hop <= MAX_REDIRECTS then
            local next_url = socketurl.absolute(request_url, headers["location"])
            if not next_url
                or (request_url:match("^https:") and next_url:match("^http:")) then
                os.remove(tmp)
                return nil, _("AO3 redirected the download to an unsafe address.")
            end
            request_url = next_url
        else
            break
        end
    end

    BugReport.log("download", T("%1 -> %2", BugReport.sanitizeUrl(url), tostring(code)))
    if not ok then
        os.remove(tmp)
        return nil, tostring(code)
    end
    if REDIRECT_CODES[code] then
        os.remove(tmp)
        return nil, _("AO3 redirected the download too many times.")
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
    if Account.isLostCookiePage(head) then
        -- The session jar is live as far as the plugin knows, but AO3 ended
        -- it. Keep it (the reader may still have an offline session) and say
        -- exactly what happened instead of blaming the work.
        os.remove(tmp)
        BugReport.log("download", "rejected: session ended (lost cookie)")
        return nil, _("AO3 ended the saved session. Sign in again from Account.")
    end
    if not head:find('id="preface"', 1, true) and not head:find('id="chapters"', 1, true) then
        local page_title = head:match("<title[^>]*>(.-)</title>") or ""
        page_title = util.htmlEntitiesToUtf8(page_title)
        BugReport.log("download", "rejected: response was not a work file")
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
    BugReport.log("download", "saved work " .. tostring(id))
    return final
end

-- ---------------------------------------------------------------------------
-- Opening a work in the reader
-- ---------------------------------------------------------------------------
--
-- The plugin's menu stays in UIManager's stack underneath the reader, so
-- closing the reader reveals the AO3 screen the user left. ReaderUI's own
-- exit paths skip that and jump to the file manager, so they are hooked for
-- works opened from here.

function Ao3:openWorkReader(path, title)
    local ReaderUI = require("apps/reader/readerui")
    ReaderUI:showReader(path, nil, nil, nil, function()
        -- ReaderUI.instance is assigned after after_open_callback returns.
        UIManager:nextTick(function()
            self:installReaderHooks(require("apps/reader/readerui").instance, title)
        end)
    end)
end

function Ao3:installReaderHooks(reader)
    if not reader or not reader.document then return end
    local doc = reader.document

    -- Chapters-only, flat TOC (see AuthorPage.cleanToc).
    if doc.getToc and not doc.ao3_toc_cleaned then
        local get_toc = doc.getToc
        doc.getToc = function(this)
            return AuthorPage.cleanToc(get_toc(this))
        end
        doc.ao3_toc_cleaned = true
        -- ReaderToc fills and caches its table on the first page update, which
        -- happens before this callback. Drop that cache so the next build asks
        -- the document again and gets the cleaned table.
        if reader.toc and reader.toc.resetToc then
            reader.toc:resetToc()
        end
    end

    local function backToPlugin()
        if not reader.document then return end
        -- ReaderUI:onHome suspends repaints before closing; do the same here
        -- so the revealed menu repaints normally.
        if UIManager.setSuspendRepaints then
            UIManager:setSuspendRepaints(false)
        end
        reader:onClose()
        local menu = self.menu
        if menu and UIManager.isWidgetShown and not UIManager:isWidgetShown(menu) then
            UIManager:show(menu)
        end
    end

    -- Back key / Back gesture (through Event "Home"): return to AO3.
    reader.onHome = function()
        backToPlugin()
        return true
    end

    -- KOReader's TOC menu draws letter shortcut boxes when the device reports
    -- a keyboard (the emulator does) and packs rows tightly. The TOC is for
    -- touch, so hide the shortcuts and give the rows a little more air by
    -- showing three fewer per page.
    local toc = reader.toc
    if toc and toc.onShowToc then
        local on_show_toc = toc.onShowToc
        toc.onShowToc = function(toc_self, ...)
            local ret = on_show_toc(toc_self, ...)
            local menu = toc_self.toc_menu
            if menu then
                local changed = false
                if menu.is_enable_shortcut then
                    menu.is_enable_shortcut = false
                    changed = true
                end
                local per_page = menu.items_per_page or 14
                local padded = math.max(7, per_page - 3)
                if padded ~= per_page then
                    menu.items_per_page = padded
                    changed = true
                end
                if changed then
                    menu:updateItems(menu.page or 1)
                    if menu.dimen and UIManager.setDirty then
                        UIManager:setDirty(menu, "ui")
                    end
                end
            end
            return ret
        end
    end

    -- A visible entry in the reader menu's Navigation tab. It belongs at the
    -- bottom of that tab's first page, so insert it into the menu order rather
    -- than relying on the orphan fallback, which appends to the end.
    local ok, order = pcall(require, "ui/elements/reader_menu_order")
    if ok and type(order) == "table" and type(order.navi) == "table" then
        local present = false
        for _, key in ipairs(order.navi) do
            if key == "ao3_back_to_browser" then present = true break end
        end
        if not present then
            for index, key in ipairs(order.navi) do
                if key == "skim_to" then
                    table.insert(order.navi, index + 1, "ao3_back_to_browser")
                    break
                end
            end
        end
    end

    if reader.menu and reader.menu.registerToMainMenu then
        reader.menu:registerToMainMenu{
            name = "ao3_back_to_browser",
            addToMainMenu = function(widget, menu_items)
                menu_items.ao3_back_to_browser = {
                    text = _("Back to AO3"),
                    sorting_hint = "navi",
                    callback = function()
                        if reader.menu and reader.menu.onCloseReaderMenu then
                            reader.menu:onCloseReaderMenu()
                        end
                        backToPlugin()
                    end,
                }
            end,
        }
        reader.menu.tab_item_table = nil
    end

    -- The end-of-work dialog gains the same choice; the stock "File browser"
    -- button keeps doing what it says.
    local status = reader.status
    if status and status.onEndOfBook then
        local on_end = status.onEndOfBook
        status.onEndOfBook = function(status_self)
            on_end(status_self)
            local dialog = UIManager.getTopmostVisibleWidget
                and UIManager:getTopmostVisibleWidget()
            if dialog and dialog.name == "end_document" and dialog.buttons
                    and not dialog.ao3_back_added then
                dialog.ao3_back_added = true
                dialog.buttons[#dialog.buttons + 1] = {{
                    text = _("Back to AO3"),
                    callback = function()
                        UIManager:close(dialog)
                        backToPlugin()
                    end,
                }}
                if dialog.reinit then
                    dialog:reinit()
                    UIManager:setDirty(dialog, "ui")
                end
            end
        end
    end
end

function Ao3:readWork(id, title, refresh)
    local cached = findCachedWork(getDownloadDir(), id)
    if cached and not refresh then
        self:openWorkReader(cached, title)
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
            self:openWorkReader(path, title)
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
        -- The plugin never writes a subtitle, and the file-manager style would
        -- still reserve a blank line for one. Dropping it keeps the header one
        -- line tall instead of leaving a band of empty paper above every page.
        subtitle = false,
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
    -- The card symbols and the settings gear are authored SVGs beside the
    -- official logo; the menu carries the directory to every row.
    menu.ao3_icons_dir = self:pluginDir() .. "/assets/icons/"

    -- The title bar's close button pads its tap zone one icon-height below a
    -- 49px bar, so its target covers the top half of the first content row.
    -- The author screen's tab strip is that row: tapping "Bookmarks" hit
    -- Close and dropped back to Home instead of switching tabs. Keep the
    -- icon where it is, but end its target with the bar.
    local close = menu.title_bar and menu.title_bar.right_button
    if close and type(close.padding_bottom) == "number" and close.padding_bottom > 0 then
        local pad = close.padding_bottom
        close.padding_bottom = 0
        -- IconButton keeps the pad as the last cell of its vertical group and
        -- counts it in its dimen; update both so hit testing follows.
        if close.button and close.button[3] then
            close.button[3].width = 0
        end
        if close.dimen then
            close.dimen.h = math.max(0, close.dimen.h - pad)
        end
    end

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
        -- The logo lockup is the page header; the native bar keeps only the
        -- close button, so "AO3" is not written twice.
        self.menu.title = ""
        self.menu.ao3_title = ""
        self.menu:switchItemTable("", self:homeRows(), 1)
        if self.menu.page_return_arrow then
            self.menu.page_return_arrow:enableDisable(false)
        end
        return
    end
    local menu = self:ensureMenu()
    menu.title = ""
    menu.ao3_title = ""
    menu:switchItemTable("", self:homeRows(), 1)
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
function Ao3:replaceRows(title, rows, itemnumber)
    local menu = self.menu
    if not menu then return end
    menu:switchItemTable(title, rows, itemnumber or 1)
    menu.ao3_title = title
end

function Ao3:homeRows()
    local downloads = self:listDownloads()

    -- The traced SVG is preferred; the official PNG is the fallback (and the
    -- source of truth) if the asset is missing.
    local assets = self:pluginDir() .. "/assets/"
    local logo = assets .. "ao3-logo.svg"
    if lfs.attributes(logo, "mode") ~= "file" then
        logo = assets .. "ao3-logo.png"
    end
    if lfs.attributes(logo, "mode") ~= "file" then
        logo = nil
    end

    return HomePage.build{
        width = Screen:getWidth() - 2 * Size.padding.fullscreen,
        font_size = (self.menu and self.menu.font_size) or 20,
        logo_path = logo,
        icons_dir = assets .. "icons/",
        downloads = #downloads,
        version = Updater.currentVersion(self:pluginDir()),
        signed_in = self.session ~= nil,
        account_name = self.session and self.session.username or nil,
        on_account = function() self:showAccount() end,
        on_settings = function() self:showSettings() end,
        on_search = function() self:searchDialog() end,
        on_latest = function()
            self:loadListing(self:recentUrl(), _("Latest works"))
        end,
        on_fandoms = function() self:showFandoms() end,
        on_author = function() self:authorDialog() end,
        on_tag = function() self:tagDialog() end,
        on_downloads = function() self:showDownloads() end,
        on_open = function() self:workDialog() end,
        on_update = function() self:checkForUpdates() end,
        on_report = function() self:reportBug() end,
        on_restore = lfs.attributes(Updater.backupDir(self:pluginDir()), "mode") == "directory"
            and function() self:rollbackUpdate() end or nil,
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
                self:showFandomLetterPage(category,
                    (category.letters and category.letters[1]) or "A", 0, false)
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

-- The alphabet as one printed thumb index: nine letters to a shelf, so the
-- whole of A-Z and "#" sits on the page at once instead of taking two screens
-- of near-empty rows. The open letter is the single inverted cell - the tab
-- strip's checked state, and the only block of ink on the screen.
local FANDOM_INDEX_COLUMNS = 9

function Ao3:fandomLetterCell(letter, open, width, height, font_size, on_select)
    local border = Size.border.thin
    local label = TextWidget:new{
        text = letter,
        face = Font:getFace("smallinfofont", font_size),
        bold = true,
        fgcolor = open and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
        max_width = math.max(1, width - 2 * border - 2 * Size.padding.small),
    }
    local frame = FrameContainer:new{
        background = open and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_BLACK,
        bordersize = border,
        margin = 0,
        padding = 0,
        CenterContainer:new{
            dimen = Geom:new{
                w = math.max(1, width - 2 * border),
                h = math.max(1, height - 2 * border),
            },
            label,
        },
    }
    return Uikit.tapArea(frame, width, height, function()
        on_select(letter)
    end)
end

function Ao3:fandomLetterIndex(category, open_letter, width, on_select)
    local letters = category and category.letters
    if not letters or #letters == 0 then return nil end

    width = math.max(1, width or Screen:getWidth())
    local gutter = Size.padding.fullscreen
    local inner_w = math.max(1, width - 2 * gutter)
    local font_size = (self.menu and self.menu.font_size) or 20
    local cell_h = lineHeight(Font:getFace("smallinfofont", font_size), true)
        + 2 * Size.padding.default
    local columns = math.min(#letters, FANDOM_INDEX_COLUMNS)

    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.large }
    local first = 1
    while first <= #letters do
        local last = math.min(first + columns - 1, #letters)
        local count = last - first + 1
        local row = HorizontalGroup:new{ align = "top" }
        row[#row + 1] = HorizontalSpan:new{ width = gutter }
        for i = first, last do
            -- Split the column evenly while keeping every cell a whole
            -- number of pixels, so the grid has no ragged right edge.
            local left = math.floor((i - first) * inner_w / count)
            local right = math.floor((i - first + 1) * inner_w / count)
            row[#row + 1] = self:fandomLetterCell(letters[i],
                letters[i] == open_letter, right - left, cell_h, font_size,
                on_select)
        end
        row[#row + 1] = HorizontalSpan:new{ width = gutter }
        group[#group + 1] = row
        first = last + 1
    end
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.large }
    return group
end

function Ao3:showFandomLetterPage(category, letter, offset, replace)
    local rows, page = self:loadFandomLetter(category, letter, offset)
    if not rows then
        UIManager:show(InfoMessage:new{
            text = _("Could not read that part of the fandom list."),
        })
        return
    end

    local strip = self:fandomLetterIndex(category, letter, nil, function(selected)
        -- Every tap starts that letter at its first window; tapping the open
        -- letter is the way back to the top of a long list.
        self:showFandomLetterPage(category, selected, 0, true)
    end)
    if strip then
        table.insert(rows, 1, { ao3_tabs = strip, ao3_sticky = true })
    end
    table.insert(rows, strip and 2 or 1, {
        text = _("Find in this letter…"),
        action = function()
            self:findFandomDialog(category, letter)
        end,
    })

    if #page.entries == 0 then
        rows[#rows + 1] = { text = _("No fandoms in this letter.") }
    end

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

    -- The open letter is already the inverted tab; the title spends its one
    -- line on where the reader is inside that letter.
    local title
    if page.total > 0 then
        title = T(_("%1 · %2–%3 of %4"), category.name, page.offset + 1,
            page.offset + #page.entries, formatCount(page.total))
    else
        title = T(_("%1 · %2 fandoms"), category.name, formatCount(page.total))
    end
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
                self:openWorkReader(item.path, item.title)
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

-- An author's works page reuses the work-card listing markup. Accept a
-- bare name, a profile path, or a full URL; the result always points at
-- the works list.
function Ao3:authorWorksUrl(input)
    input = trim(input)
    if input == "" then return nil end
    if input:match("^https?://") or input:sub(1, 1) == "/" then
        local page = input:match("^https?://") and input or (BASE_URL .. input)
        page = (page:gsub("/+$", ""))
        if page:match("/works$") then return page end
        return page .. "/works"
    end
    return BASE_URL .. "/users/" .. util.urlEncode(input) .. "/works"
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

function Ao3:authorDialog()
    local dialog
    dialog = InputDialog:new{
        title = _("Browse an AO3 author"),
        description = _("Author name or profile URL"),
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
                        local url = self:authorWorksUrl(input)
                        if url then
                            self:showAuthor(input, url)
                        end
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
-- Inline updates
-- ---------------------------------------------------------------------------
--
-- Releases are published by .github/workflows/release.yml: a zip of the
-- plugin plus a manifest carrying its version and SHA-256. Updating never
-- touches the code that is running; the new tree is staged next to the
-- install, validated, swapped in, and KOReader is restarted.

function Ao3:pluginDir()
    return self.path or "plugins/ao3.koplugin"
end

function Ao3:checkForUpdates()
    local dir = self:pluginDir()
    NetworkMgr:runWhenOnline(function()
        local Trapper = require("ui/trapper")
        local manifest, err
        Trapper:wrap(function()
            Trapper:info(_("Checking for updates…"), true)
            local ok, result, check_err = pcall(Updater.fetchManifest)
            if ok then
                manifest, err = result, check_err
            else
                err = tostring(result)
            end
            Trapper:reset()
        end)
        NetworkMgr:afterWifiAction()

        if not manifest then
            BugReport.log("update", "check failed: " .. tostring(err))
            UIManager:show(InfoMessage:new{
                text = T(_("Could not check for updates:\n%1"), err or _("unknown error")),
            })
            return
        end
        local current = Updater.currentVersion(dir)
        BugReport.log("update", T("installed %1, latest %2", current, manifest.version))
        if not Updater.isNewer(manifest.version, current) then
            UIManager:show(InfoMessage:new{
                text = T(_("You already have the latest version (v%1)."), current),
            })
            return
        end
        local notes = manifest.notes ~= "" and ("\n\n" .. manifest.notes) or ""
        UIManager:show(ConfirmBox:new{
            text = T(_("Update KO3 from v%1 to v%2?%3"), current, manifest.version, notes),
            ok_text = _("Update"),
            cancel_text = _("Later"),
            ok_callback = function()
                self:installUpdate(dir, manifest)
            end,
        })
    end)
end

function Ao3:installUpdate(dir, manifest)
    -- The check brackets its request with runWhenOnline/afterWifiAction, which
    -- may leave Wi-Fi off when the user then taps Update in the prompt. The
    -- download must bring the network back up itself, or it waits until the
    -- socket times out.
    NetworkMgr:runWhenOnline(function()
        local Trapper = require("ui/trapper")
        local installed, err
        Trapper:wrap(function()
            Trapper:info(T(_("Downloading v%1…"), manifest.version), true)
            local ok, result, result_err = pcall(Updater.update, dir, manifest)
            if not ok then
                err = tostring(result)
            elseif result then
                installed = true
            else
                err = result_err
            end
            Trapper:reset()
        end)
        NetworkMgr:afterWifiAction()

        if not installed then
            BugReport.log("update", "install failed: " .. tostring(err))
            UIManager:show(InfoMessage:new{
                text = T(_("Update failed:\n%1"), err or _("unknown error")),
            })
            return
        end
        BugReport.log("update", "installed " .. tostring(manifest.version))
        UIManager:show(ConfirmBox:new{
            text = T(_("Updated to v%1.\nRestart KOReader to use it."), manifest.version),
            ok_text = _("Restart"),
            cancel_text = _("Later"),
            ok_callback = function()
                UIManager:restartKOReader()
            end,
        })
    end)
end

function Ao3:rollbackUpdate()
    local dir = self:pluginDir()
    local previous = Updater.versionFromMeta(Updater.backupDir(dir)) or _("unknown")
    UIManager:show(ConfirmBox:new{
        text = T(_("Restore v%1 and discard the current version?"), previous),
        ok_text = _("Restore"),
        cancel_text = _("Cancel"),
        ok_callback = function()
            local ok, err = Updater.rollback(dir)
            if ok then
                UIManager:show(ConfirmBox:new{
                    text = _("Previous version restored. Restart KOReader now?"),
                    ok_text = _("Restart"),
                    cancel_text = _("Later"),
                    ok_callback = function()
                        UIManager:restartKOReader()
                    end,
                })
            else
                UIManager:show(InfoMessage:new{
                    text = T(_("Could not restore: %1"), err or _("unknown error")),
                })
            end
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Bug reports
-- ---------------------------------------------------------------------------
--
-- The report is built locally first. The log is attached only after the
-- consent dialog, which states what it contains and why it is needed.

function Ao3:openLink(url)
    if type(Device.openLink) == "function" then
        if pcall(Device.openLink, Device, url) then return true end
    end
    UIManager:show(InfoMessage:new{
        text = T(_("Open this URL in a browser:\n%1"), url),
    })
    return false
end

function Ao3:reportBug()
    local dialog
    dialog = InputDialog:new{
        title = _("Report a bug"),
        description = _("What happened, and what did you expect?\nPlease avoid personal details."),
        allow_newline = true,
        text_height = math.floor(Device.screen:getHeight() / 3),
        buttons = {{
            {
                text = _("Cancel"),
                id = "close",
                callback = function()
                    UIManager:close(dialog)
                end,
            },
            {
                text = _("Next"),
                callback = function()
                    local text = trim(dialog:getInputValue() or "")
                    UIManager:close(dialog)
                    if text == "" then
                        UIManager:show(InfoMessage:new{
                            text = _("Please describe the problem first."),
                        })
                        return
                    end
                    self:askAttachLog(text)
                end,
            },
        }},
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Ao3:askAttachLog(description)
    UIManager:show(ConfirmBox:new{
        text = _("Attach a diagnostic log?\n\nThe report and log are sent to the project's issue tracker. The log is used only to find the cause of this issue. It contains the plugin version, KOReader and device details, and recent request results. It does not contain your AO3 password, cookies, search text, or work text."),
        ok_text = _("Attach log"),
        ok_callback = function()
            self:finishReport(description, true)
        end,
        cancel_text = _("Without log"),
        cancel_callback = function()
            self:finishReport(description, false)
        end,
        other_buttons_first = true,
        other_buttons = {{{
            text = _("Cancel report"),
            callback = function() end,
        }}},
    })
end

function Ao3:finishReport(description, include_log)
    local dir, report_path, log_path, err = BugReport.save(description, include_log)
    if not dir then
        UIManager:show(InfoMessage:new{
            text = T(_("Could not save the report:\n%1"), err or _("unknown error")),
        })
        return
    end
    BugReport.log("report", "saved (log=" .. tostring(include_log) .. ")")

    local token = BugReport.token()
    if not token and not BugReport.RELAY_URL then
        self:showSavedReport(dir, include_log, description)
        return
    end

    local title = BugReport.title(description)
    local body = BugReport.build(description, include_log)
    NetworkMgr:runWhenOnline(function()
        local Trapper = require("ui/trapper")
        local url, submit_err
        Trapper:wrap(function()
            Trapper:info(_("Sending the report…"), true)
            local ok, result, result_err = pcall(BugReport.deliver, title, body)
            if ok then
                url, submit_err = result, result_err
            else
                submit_err = tostring(result)
            end
            Trapper:reset()
        end)
        NetworkMgr:afterWifiAction()

        if url then
            UIManager:show(ConfirmBox:new{
                text = T(_("Report sent. Thank you!\n%1"), url),
                ok_text = _("Open issue"),
                cancel_text = _("Close"),
                ok_callback = function()
                    self:openLink(url)
                end,
            })
        else
            UIManager:show(InfoMessage:new{
                text = T(_("Could not send the report (%1).\nIt is saved in:\n%2"),
                    submit_err or _("unknown error"), dir),
            })
        end
    end)
end

function Ao3:showSavedReport(dir, include_log, description)
    local files = include_log and _("report.md and log.txt") or _("report.md")
    local url = BugReport.issueUrl(BugReport.title(description))
    UIManager:show(ConfirmBox:new{
        text = T(_("Report saved:\n%1\n\nAttach %2 to a new issue:\n%3"),
            dir, files, BugReport.ISSUE_URL),
        ok_text = _("Open issue page"),
        cancel_text = _("Close"),
        ok_callback = function()
            self:openLink(url)
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Plugin entry point
-- ---------------------------------------------------------------------------

function Ao3:init()
    -- A saved session is read from disk, not verified online. Browsing works
    -- as before when there is none.
    self.session = Account.load()
    -- Display choices live in their own file, so Log out keeps them.
    self.prefs = Preferences.load()
    self.ui.menu:registerToMainMenu(self)
    BugReport.log("session", table.concat(BugReport.environment(), " | "))
end

-- KOReader appends plugin rows to the end of the tab they name. The Tools tab
-- is two pages on a 600px screen, so appending (or sitting before Profiles)
-- hides KO3 on page 2. Insert it in the built-in order near the top instead:
-- fourth row, before Statistics. The order table is shared with MenuSorter,
-- so inserting here affects both the file manager and reader menus.
local TOOLS_POSITION = 4

local function placeOnToolsTab()
    for _, module in ipairs({
        "ui/elements/filemanager_menu_order",
        "ui/elements/reader_menu_order",
    }) do
        local ok, order = pcall(require, module)
        local tools = ok and order and order.tools
        if type(tools) == "table" then
            for i = #tools, 1, -1 do
                if tools[i] == "ao3_browser" then
                    table.remove(tools, i)
                end
            end
            table.insert(tools, math.min(TOOLS_POSITION, #tools + 1), "ao3_browser")
        end
    end
end

function Ao3:addToMainMenu(menu_items)
    placeOnToolsTab()
    -- One entry, one app. Everything else lives inside the AO3 screen.
    menu_items.ao3_browser = {
        text = _("KO3"),
        -- Directly on the Tools tab, below the built-in rows. `more_tools`
        -- would hide the only entry of the app one level down.
        sorting_hint = "tools",
        callback = function()
            self:showHome()
        end,
    }
end

return Ao3
