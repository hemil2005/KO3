--[[--
Reader preferences that belong to the app, not to a session.

They live in their own settings file so Log out (which deletes
`settings/ao3.lua`) cannot take the reader's display choices with it. Four
kinds of choice are stored here: how the app looks (booleans, plus the one
card-design enum), the fandoms the reader pinned to the landing page
(`favourites`), the saved work they opened last, and how often the app may ask
about updates (timestamps and a dismissed version). None of them identifies
the reader; that stays in the session file.
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Preferences = {}

-- Work lists start with the tag box folded: a list is for choosing a work,
-- and one line of tags is enough to recognise it. The modern card is the
-- default design; the legacy one is the plain title/author/blurb card.
--
-- The update bookkeeping is here so Log out cannot make the plugin forget
-- which release the reader dismissed: `last_check_ts` is the epoch second of
-- the last manifest request, `remind_after_ts` the end of a "remind later"
-- window, and `dismissed_version` the release that must not ask again.
--
-- `last_read_path` and `last_read_title` are the saved copy the reader opened
-- most recently. They are a reading fact, not a session, so logging out keeps
-- the Continue reading row on the landing page.
local DEFAULTS = {
    tags_expanded = false,
    card_style = "modern",
    -- Pinned fandoms, newest first: { name = string, url = string, count = string }.
    -- The url is the offline index's path ("/tags/Some%20Fandom/works"), so a
    -- tile can open the listing without a request of its own.
    favourites = {},
    last_check_ts = 0,
    remind_after_ts = 0,
    dismissed_version = "",
    last_read_path = "",
    last_read_title = "",
}

local CARD_STYLES = {
    modern = true,
    legacy = true,
}

-- The landing page has room for four favourites plus the "All favourites"
-- tile; keeping twelve means the full list still fits a couple of pages.
local FAVOURITES_MAX = 12
Preferences.MAX_FAVOURITES = FAVOURITES_MAX

local function trim(value)
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function favouriteString(value)
    local kind = type(value)
    if kind == "string" then return value end
    if kind == "number" then return tostring(value) end
    return nil
end

-- One rule for the favourites list, shared by load, save, the home screen and
-- the fandom rows: an entry is a table with a name and a url, anything else is
-- dropped. URLs identify a fandom, names are the fallback identity, so a
-- hand-edited file can never pin the same fandom twice. Order is newest first
-- and only the first twelve survive.
function Preferences.favourites(value)
    local favourites = {}
    if type(value) ~= "table" then return favourites end
    local seen_urls, seen_names = {}, {}
    for _, item in ipairs(value) do
        if #favourites >= FAVOURITES_MAX then break end
        if type(item) == "table" then
            local name = favouriteString(item.name)
            local url = favouriteString(item.url)
            local count = favouriteString(item.count) or ""
            if name and url then
                name, url, count = trim(name), trim(url), trim(count)
                local url_key, name_key = url:lower(), name:lower()
                if name ~= "" and url ~= ""
                        and not seen_urls[url_key] and not seen_names[name_key] then
                    seen_urls[url_key] = true
                    seen_names[name_key] = true
                    favourites[#favourites + 1] = {
                        name = name,
                        url = url,
                        count = count,
                    }
                end
            end
        end
    end
    return favourites
end

-- Anything that is not one of the two designs is the default. A hand-edited
-- or older file must never leave the list without a card builder.
function Preferences.cardStyle(value)
    if type(value) == "string" and CARD_STYLES[value] then return value end
    return "modern"
end

-- Epoch seconds, or 0. A hand-edited file must not turn into a timer that
-- fires in the past or never.
function Preferences.timestamp(value)
    local number = tonumber(value)
    if not number or number < 0 then return 0 end
    return math.floor(number)
end

function Preferences.path()
    local ok, dir = pcall(function() return DataStorage:getSettingsDir() end)
    if not ok or not dir then
        dir = DataStorage:getFullDataDir()
    end
    return dir .. "/ao3_prefs.lua"
end

-- A missing or unreadable file is not an error: the reader simply gets the
-- defaults. `path` is for tests.
function Preferences.load(path)
    local prefs = {}
    for key, value in pairs(DEFAULTS) do
        -- Tables are copied so a caller mutating the list cannot reach into
        -- the defaults table and leak into the next load.
        prefs[key] = type(value) == "table" and {} or value
    end

    local ok, settings = pcall(function()
        return LuaSettings:open(path or Preferences.path())
    end)
    if not ok or not settings then return prefs end

    local expanded = settings:readSetting("tags_expanded")
    if type(expanded) == "boolean" then
        prefs.tags_expanded = expanded
    end
    prefs.card_style = Preferences.cardStyle(settings:readSetting("card_style"))
    prefs.favourites = Preferences.favourites(settings:readSetting("favourites"))
    prefs.last_check_ts = Preferences.timestamp(settings:readSetting("last_check_ts"))
    prefs.remind_after_ts = Preferences.timestamp(settings:readSetting("remind_after_ts"))
    local dismissed = settings:readSetting("dismissed_version")
    if type(dismissed) == "string" and dismissed ~= "" then
        prefs.dismissed_version = dismissed
    end
    local last_path = settings:readSetting("last_read_path")
    if type(last_path) == "string" then
        prefs.last_read_path = last_path
    end
    local last_title = settings:readSetting("last_read_title")
    if type(last_title) == "string" then
        prefs.last_read_title = last_title
    end
    return prefs
end

function Preferences.save(prefs, path)
    local ok, settings = pcall(function()
        return LuaSettings:open(path or Preferences.path())
    end)
    if not ok or not settings then return false end
    settings:saveSetting("tags_expanded", prefs and prefs.tags_expanded == true)
    settings:saveSetting("card_style",
        Preferences.cardStyle(prefs and prefs.card_style))
    settings:saveSetting("favourites",
        Preferences.favourites(prefs and prefs.favourites))
    settings:saveSetting("last_check_ts",
        Preferences.timestamp(prefs and prefs.last_check_ts))
    settings:saveSetting("remind_after_ts",
        Preferences.timestamp(prefs and prefs.remind_after_ts))
    settings:saveSetting("dismissed_version",
        type(prefs and prefs.dismissed_version) == "string"
            and prefs.dismissed_version or "")
    settings:saveSetting("last_read_path",
        type(prefs and prefs.last_read_path) == "string"
            and prefs.last_read_path or "")
    settings:saveSetting("last_read_title",
        type(prefs and prefs.last_read_title) == "string"
            and prefs.last_read_title or "")
    settings:flush()
    return true
end

return Preferences
