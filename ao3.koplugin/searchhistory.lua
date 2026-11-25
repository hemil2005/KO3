--[[--
Per-dialog recent search history for KO3.

Stored in `settings/ao3_history.lua`, outside `plugins/ao3.koplugin/` and
separate from `settings/ao3.lua`, so history survives restarts, plugin
updates, and Log out. Each search dialog keeps its own list of up to 10
recent queries, most recent first.
]]

local DataStorage = require("datastorage")
local LuaSettings = require("luasettings")

local SearchHistory = {}

SearchHistory.MAX_ENTRIES = 10

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function SearchHistory.path()
    local ok, dir = pcall(function() return DataStorage:getSettingsDir() end)
    if not ok or not dir then
        dir = DataStorage:getFullDataDir()
    end
    return dir .. "/ao3_history.lua"
end

local function normalizeList(list)
    if type(list) ~= "table" then return {} end
    local out, seen = {}, {}
    for _, item in ipairs(list) do
        local text = trim(item)
        if text ~= "" and not seen[text] then
            seen[text] = true
            out[#out + 1] = text
            if #out >= SearchHistory.MAX_ENTRIES then break end
        end
    end
    return out
end

function SearchHistory.get(kind, path)
    if type(kind) ~= "string" or kind == "" then return {} end
    local ok, settings = pcall(function()
        return LuaSettings:open(path or SearchHistory.path())
    end)
    if not ok or not settings then return {} end
    return normalizeList(settings:readSetting(kind))
end

function SearchHistory.record(kind, query, path)
    if type(kind) ~= "string" or kind == "" then return {} end
    local text = trim(query)
    if text == "" then return SearchHistory.get(kind, path) end

    local ok, settings = pcall(function()
        return LuaSettings:open(path or SearchHistory.path())
    end)
    if not ok or not settings then return {} end

    local existing = normalizeList(settings:readSetting(kind))
    local updated = { text }
    for _, item in ipairs(existing) do
        if item ~= text then
            updated[#updated + 1] = item
            if #updated >= SearchHistory.MAX_ENTRIES then break end
        end
    end

    settings:saveSetting(kind, updated)
    settings:flush()
    return updated
end

return SearchHistory
