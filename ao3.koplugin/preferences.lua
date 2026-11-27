--[[--
Reader preferences that belong to the app, not to a session.

They live in their own settings file so Log out (which deletes
`settings/ao3.lua`) cannot take the reader's display choices with it. Three
kinds of choice are stored here: how the app looks (booleans, plus the one
card-design enum), how often it may ask about updates (timestamps and a
dismissed version), and which saved work the reader opened last. None of it
identifies the reader; that stays in the session file.
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
    for key, value in pairs(DEFAULTS) do prefs[key] = value end

    local ok, settings = pcall(function()
        return LuaSettings:open(path or Preferences.path())
    end)
    if not ok or not settings then return prefs end

    local expanded = settings:readSetting("tags_expanded")
    if type(expanded) == "boolean" then
        prefs.tags_expanded = expanded
    end
    prefs.card_style = Preferences.cardStyle(settings:readSetting("card_style"))
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
