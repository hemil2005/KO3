--[[--
AO3 account sign-in, personal lists and work actions for the AO3 browser.

Signing in is three requests: GET a JSON CSRF token, POST the credential
fields, then load one page to confirm the logged-in greeting. Nothing here
crawls, retries or prefetches; the caller sends each request only when the user
asks.

Only AO3's own session cookies are kept. Cloudflare cookies (`cf_clearance`,
`__cf_bm`, `__cfwaitingroom`) are deliberately ignored: they are bound to the
client that earned them and replaying them is both useless and an attempt to
reuse a bot-check pass. The password is posted once and never written to disk;
settings/ao3.lua holds only the session cookie and the display name. The user
can remove both with Log out.

Markup read here:

    Token       GET /token_dispenser.json -> {"token":"..."}
    Greeting    div#greeting a[href="/users/<name>/pseuds/<name>"]
    Lists       /users/<name>/{bookmarks,marked_for_later,readings,subscriptions}
    Work page   form#new_kudo, #bookmark-form, li.subscribe,
                forms posting to /works/<id>/{mark_for_later,mark_as_read}
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")
local htmlparser = require("htmlparser")
local util = require("util")
local _ = require("gettext")

local Account = {}

Account.BASE_URL = "https://archiveofourown.org"
Account.LOGIN_URL = Account.BASE_URL .. "/users/login"
Account.TOKEN_URL = Account.BASE_URL .. "/token_dispenser.json"

-- Rails session cookie plus the optional persistent "remember me" token.
-- `user_credentials` is a Rails/nginx cache marker (value "1"), not a
-- credential: AO3 signs a logged-in request out to /lost_cookie when it is
-- missing, so it has to travel with the session. Everything else in
-- Set-Cookie is dropped.
Account.KEPT_COOKIES = {
    "_otwarchive_session",
    "remember_user_token",
    "user_credentials",
}

local KEPT = {}
for _, name in ipairs(Account.KEPT_COOKIES) do KEPT[name] = true end

local function trim(s)
    return ((s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
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
    for _, node in ipairs(nodes) do return node end
end

function Account.settingsPath()
    local ok, dir = pcall(function() return DataStorage:getSettingsDir() end)
    if not ok or not dir then
        dir = DataStorage:getFullDataDir()
    end
    return dir .. "/ao3.lua"
end

-- A saved session is only usable when it carries AO3's own session cookie.
function Account.isSignedIn(session)
    return type(session) == "table"
        and type(session.cookies) == "table"
        and trim(session.cookies._otwarchive_session or "") ~= ""
end

function Account.load(path)
    local ok, settings = pcall(function() return LuaSettings:open(path or Account.settingsPath()) end)
    if not ok or not settings then return nil end
    local session = settings:readSetting("session")
    if Account.isSignedIn(session) then
        return session
    end
    return nil
end

function Account.save(path, session)
    if not Account.isSignedIn(session) then return false end
    local ok, settings = pcall(function() return LuaSettings:open(path or Account.settingsPath()) end)
    if not ok or not settings then return false end
    settings:saveSetting("session", session)
    settings:flush()
    return true
end

function Account.clear(path)
    path = path or Account.settingsPath()
    local ok, settings = pcall(function() return LuaSettings:open(path) end)
    if not ok or not settings then return false end
    settings:delSetting("session")
    settings:flush()
    -- LuaSettings keeps an .old copy of the previous file. Remove it too so
    -- Log out cannot leave a usable session cookie behind.
    os.remove(path .. ".old")
    return true
end

-- Rails renders one or two hidden token inputs (header and page form) plus a
-- csrf-token meta tag. Any of them is valid for the anonymous session.
function Account.parseCsrf(html)
    for tag in (html or ""):gmatch("<input[^>]*>") do
        if tag:find("authenticity_token", 1, true) then
            local value = tag:match('value="([^"]*)"') or tag:match("value='([^']*)'")
            if value and value ~= "" then
                return util.htmlEntitiesToUtf8(value)
            end
        end
    end
    local meta = (html or ""):match('<meta[^>]-name="csrf%-token"[^>]-content="([^"]*)"')
        or (html or ""):match('<meta[^>]-content="([^"]*)"[^>]-name="csrf%-token"')
    if meta and meta ~= "" then
        return util.htmlEntitiesToUtf8(meta)
    end
    return nil
end

-- AO3 serves a CSRF token from /token_dispenser.json for its JS client. It is
-- smaller than the login page and, unlike /users/login, is not challenged for
-- this client. Fall back to a plain pattern if dkjson is unavailable.
function Account.parseToken(body)
    if not body or body == "" then return nil end
    local ok, decoded = pcall(function()
        return require("dkjson").decode(body)
    end)
    if ok and type(decoded) == "table"
        and type(decoded.token) == "string" and decoded.token ~= "" then
        return decoded.token
    end
    return body:match('"token"%s*:%s*"([^"]+)"')
end

function Account.loginBody(token, login, password)
    return table.concat({
        "authenticity_token=" .. util.urlEncode(token or ""),
        "user%5Blogin%5D=" .. util.urlEncode(login or ""),
        "user%5Bpassword%5D=" .. util.urlEncode(password or ""),
        -- Keep the session across restarts. The token itself is what is
        -- stored, never the password.
        "user%5Bremember_me%5D=1",
        "commit=Log+In",
    }, "&")
end

-- Merge the cookies AO3 set on a response into a small jar. Returns the jar
-- and whether anything changed.
--
-- LuaSocket can join repeated Set-Cookie headers with a comma. A cookie's
-- Expires attribute also contains a comma, so split only at a comma followed
-- by `name=`. This matters during sign-in: AO3 rotates the session cookie and
-- may send a deletion for the old one in the same response. Whichever order
-- they arrive in, an expired cookie must not overwrite the live one.
local function splitSetCookie(header)
    local parts, start = {}, 1
    while true do
        local at = header:find(",%s*[%w_%.%-]+=", start)
        if not at then
            parts[#parts + 1] = header:sub(start)
            break
        end
        parts[#parts + 1] = header:sub(start, at - 1)
        start = at + 1
    end
    return parts
end

local function cookieIsExpired(part)
    local lower = part:lower()
    local max_age = tonumber(lower:match(";%s*max%-age%s*=%s*([%-%d]+)"))
    if max_age and max_age <= 0 then return true end
    local year = tonumber(lower:match(";%s*expires%s*=%s*[^;]-([%d][%d][%d][%d])"))
    if year and year <= 1970 then return true end
    return false
end

function Account.mergeCookies(jar, set_cookie)
    jar = jar or {}
    if type(set_cookie) == "table" then
        -- A table of headers is also valid. OPDS's cookie jar accepts both.
        local changed = false
        for _, header in ipairs(set_cookie) do
            local _, header_changed = Account.mergeCookies(jar, header)
            changed = changed or header_changed
        end
        return jar, changed
    end
    if not set_cookie or set_cookie == "" then return jar, false end
    local changed = false
    for _, part in ipairs(splitSetCookie(set_cookie)) do
        local name, value = part:match("^%s*([%w_%.%-]+)%s*=%s*([^;]*)")
        if name and KEPT[name] then
            value = trim(value):gsub('^"(.*)"$', "%1")
            if value ~= "" and not cookieIsExpired(part) then
                if jar[name] ~= value then
                    jar[name] = value
                    changed = true
                end
            end
        end
    end
    return jar, changed
end

function Account.cookieHeader(jar)
    if type(jar) ~= "table" then return nil end
    local parts = {}
    for _, name in ipairs(Account.KEPT_COOKIES) do
        local value = jar[name]
        if value and value ~= "" then
            parts[#parts + 1] = name .. "=" .. value
        end
    end
    -- AO3 rejects a logged-in request without its `user_credentials` marker
    -- and redirects it to /lost_cookie. Sessions saved before the marker was
    -- kept, and Set-Cookie responses that never carried it, still have a live
    -- session cookie, so send the marker rather than force a new sign-in.
    if (jar._otwarchive_session or "") ~= ""
        and (jar.user_credentials or "") == "" then
        parts[#parts + 1] = "user_credentials=1"
    end
    if #parts == 0 then return nil end
    return table.concat(parts, "; ")
end

function Account.isLoginPage(html)
    html = html or ""
    return html:find('id="new_user_session', 1, true) ~= nil
        or html:find('form class="new_user"', 1, true) ~= nil
end

-- AO3's ApplicationController sends a logged-in request that lacks the
-- user_credentials marker to /lost_cookie, which tells the reader the session
-- was ended. Recognize it by the page's URL or its title: cheap, and tolerant
-- of the surrounding markup changing.
function Account.isLostCookiePage(html)
    if type(html) ~= "string" or html == "" then return false end
    if html:find("/lost_cookie", 1, true) then return true end
    local title = html:match("<title[^>]*>(.-)</title>")
    return title ~= nil and title:lower():find("lost cookie", 1, true) ~= nil
end

-- The flash block AO3 renders above a failed sign-in.
function Account.loginError(html)
    local ok, root = pcall(htmlparser.parse, html or "", 2000)
    if ok and root then
        for _, selector in ipairs({ "div.flash.error", "p.flash.error", "div.error", "p.error" }) do
            local node = first(root:select(selector))
            local text = plain(node)
            if text ~= "" then return text end
        end
    end
    local text = (html or ""):match('<div class="flash error"[^>]*>(.-)</div>')
    if text then
        text = plain({ getcontent = function() return text end })
        if text ~= "" then return text end
    end
    return nil
end

-- After a successful sign-in AO3 greets the user in the header. This is also
-- how an email login turns into the account name without another request.
function Account.loggedInName(html)
    html = html or ""
    local start = html:find('id="greeting"', 1, true)
    if not start then return nil end
    local window = html:sub(start, start + 1500)
    local name = window:match("/users/([^/%?#\"]+)")
    if name and name ~= "" then
        return util.htmlEntitiesToUtf8(name)
    end
    return nil
end

function Account.listUrl(login, path)
    if not login or login == "" or not path then return nil end
    return Account.BASE_URL .. "/users/" .. util.urlEncode(login) .. path
end

--[[--
Work actions: kudos, bookmark, subscribe, Marked for Later.

These mirror the website's own form posts. Every one carries the session's
CSRF token; deletes and updates ride on Rails' `_method` override so a plain
POST is enough (LuaSocket does not need to send PATCH/DELETE). Kudos asks for
the JS response and subscriptions for JSON, so a successful action returns a
small body instead of another full work page.

The work page also tells us the current state. Its bookmark form carries the
pseud to bookmark with and, when one exists, the bookmark id; its subscribe
form carries the subscription id; and its Mark for Later button switches to
"Mark as Read" once the work is on that list. `parseWorkActions` reads those
forms, so the UI can show the right label without guessing.
]]--

local function formEncode(pairs)
    local parts = {}
    for _, pair in ipairs(pairs) do
        if pair[2] ~= nil then
            parts[#parts + 1] = util.urlEncode(pair[1])
                .. "=" .. util.urlEncode(tostring(pair[2]))
        end
    end
    return table.concat(parts, "&")
end

function Account.workUrl(id)
    return Account.BASE_URL .. "/works/" .. util.urlEncode(tostring(id))
end

function Account.kudosBody(token, work_id)
    return formEncode{
        { "authenticity_token", token },
        { "kudo[commentable_id]", work_id },
        { "kudo[commentable_type]", "Work" },
    }
end

function Account.bookmarkBody(token, opts)
    opts = opts or {}
    return formEncode{
        { "authenticity_token", token },
        -- A bookmark must belong to a pseud. The work page supplies the
        -- default one; a caller may choose another.
        { "bookmark[pseud_id]", opts.pseud_id },
        { "bookmark[bookmarker_notes]", opts.notes },
        { "bookmark[tag_string]", opts.tags },
        { "bookmark[collection_names]", opts.collections },
        { "bookmark[private]", opts.private and "1" or nil },
        { "bookmark[rec]", opts.rec and "1" or nil },
    }
end

local WORK_ACTION_REQUESTS = {
    kudos = function(id, token)
        return Account.BASE_URL .. "/kudos.js", Account.kudosBody(token, id)
    end,
    bookmark = function(id, token, opts)
        return Account.BASE_URL .. "/works/" .. util.urlEncode(id) .. "/bookmarks",
            Account.bookmarkBody(token, opts)
    end,
    unbookmark = function(_, token, opts)
        local bookmark_id = tostring(opts.bookmark_id or "")
        if not bookmark_id:match("^%d+$") then return nil end
        return Account.BASE_URL .. "/bookmarks/" .. bookmark_id,
            formEncode{
                { "authenticity_token", token },
                { "_method", "delete" },
            }
    end,
    subscribe = function(id, token, opts)
        local login = opts.username
        if not login or login == "" then return nil end
        return Account.BASE_URL .. "/users/" .. util.urlEncode(login) .. "/subscriptions.json",
            formEncode{
                { "authenticity_token", token },
                { "subscription[subscribable_id]", id },
                { "subscription[subscribable_type]", "Work" },
            }
    end,
    unsubscribe = function(_, token, opts)
        local login = opts.username
        local subscription_id = tostring(opts.subscription_id or "")
        if not login or login == "" or not subscription_id:match("^%d+$") then
            return nil
        end
        return Account.BASE_URL .. "/users/" .. util.urlEncode(login)
                .. "/subscriptions/" .. subscription_id .. ".json",
            formEncode{
                { "authenticity_token", token },
                { "_method", "delete" },
            }
    end,
    mark_for_later = function(id, token)
        return Account.workUrl(id) .. "/mark_for_later",
            formEncode{
                { "authenticity_token", token },
                { "_method", "patch" },
            }
    end,
    mark_as_read = function(id, token)
        return Account.workUrl(id) .. "/mark_as_read",
            formEncode{
                { "authenticity_token", token },
                { "_method", "patch" },
            }
    end,
}

-- Returns the URL and form body for an action, or nil for an unknown action
-- or a missing id. The work id is always validated: it goes into the URL.
function Account.workActionRequest(action, work_id, token, opts)
    local build = WORK_ACTION_REQUESTS[action]
    if not build then return nil end
    work_id = tostring(work_id or "")
    if not work_id:match("^%d+$") then return nil end
    return build(work_id, token, opts or {})
end

local function windowAround(html, needle, closer)
    local start = html:find(needle, 1, true)
    if not start then return nil end
    local finish = html:find(closer, start, true) or #html
    return html:sub(start, finish)
end

-- Read a hidden input's value regardless of attribute order.
local function inputValue(block, name)
    for tag in block:gmatch("<input[^>]*>") do
        local tag_name = tag:match('name="([^"]*)"') or tag:match("name='([^']*)'")
        if tag_name == name then
            return tag:match('value="([^"]*)"') or tag:match("value='([^']*)'")
        end
    end
end

-- The bookmark form either posts to /works/<id>/bookmarks (new) or to
-- /bookmarks/<id> with _method=put (existing). The selected pseud and the
-- existing bookmark's id are both in that form.
local function parseBookmark(html)
    local block = windowAround(html, 'id="bookmark-form"', "</form>")
    if not block then
        return { available = false, bookmarked = false }
    end
    local action = block:match('<form[^>]-action="([^"]+)"')
        or block:match("<form[^>]-action='([^']+)'")
    local bookmark_id = action and action:match("/bookmarks/(%d+)")
    local pseud_id = inputValue(block, "bookmark[pseud_id]")
    if not pseud_id then
        pseud_id = block:match('<option[^>]-selected[^>]-value="(%d+)"')
            or block:match('<option[^>]-value="(%d+)"[^>]-selected')
    end
    return {
        available = true,
        bookmarked = bookmark_id ~= nil,
        id = bookmark_id,
        pseud_id = pseud_id,
    }
end

local function parseSubscribe(html)
    local block = windowAround(html, '<li class="subscribe">', "</li>")
    if not block then
        return { available = false, subscribed = false }
    end
    local action = block:match('<form[^>]-action="([^"]+)"')
        or block:match("<form[^>]-action='([^']+)'")
    if not action then
        return { available = false, subscribed = false }
    end
    local subscription_id = action:match("/subscriptions/(%d+)")
    local login = action:match("/users/([^/]+)/subscriptions")
    return {
        available = true,
        subscribed = subscription_id ~= nil,
        id = subscription_id,
        username = login and util.htmlEntitiesToUtf8(login) or nil,
    }
end

-- Parse the signed-in work page into the state the action buttons need.
-- `token` is the page's own token. It is kept for inspection but not used for
-- form posts: AO3 scopes those tokens to their form, so the plugin uses
-- /token_dispenser.json for the action POST instead.
function Account.parseWorkActions(html)
    if not html or html == "" then return nil end

    -- Only these two actions count: the bookmark form also posts under
    -- /works/<id>/, but it does not describe the read-later list.
    local mark_action
    if html:find('<form[^>]-action="[^"]*/works/%d+/mark_as_read"')
        or html:find("<form[^>]-action='[^']*/works/%d+/mark_as_read'") then
        mark_action = "mark_as_read"
    elseif html:find('<form[^>]-action="[^"]*/works/%d+/mark_for_later"')
        or html:find("<form[^>]-action='[^']*/works/%d+/mark_for_later'") then
        mark_action = "mark_for_later"
    end

    return {
        token = Account.parseCsrf(html),
        signed_in = html:find('class="logged-in"', 1, true) ~= nil,
        bookmark = parseBookmark(html),
        subscribe = parseSubscribe(html),
        mark_available = mark_action ~= nil,
        marked_for_later = mark_action == "mark_as_read",
        kudos_available = html:find('id="new_kudo"', 1, true) ~= nil,
        kudos_done = false,
    }
end

return Account
