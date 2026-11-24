--[[--
Reader preferences that belong to the app, not to a session.

They live in their own settings file so Log out (which deletes
`settings/ao3.lua`) cannot take the reader's display choices with it. Only
display choices are stored here — booleans, plus the one card-design enum —
never anything that identifies the reader; that stays in the session file.
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local Preferences = {}

-- Work lists start with the tag box folded: a list is for choosing a work,
-- and one line of tags is enough to recognise it. The modern card is the
-- default design; the legacy one is the plain title/author/blurb card.
local DEFAULTS = {
    tags_expanded = false,
    card_style = "modern",
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
    settings:flush()
    return true
end

return Preferences
