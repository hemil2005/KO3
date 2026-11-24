-- KOReader busted spec for the plugin's reader preferences.
--
--   ln -s ../../plugins/ao3.koplugin/spec/ao3_preferences_spec.lua spec/unit/ao3_preferences_spec.lua
--   ./kodev test --busted=--pattern=ao3_preferences front
--
-- The preferences file is separate from the AO3 session on purpose: logging
-- out must not reset how work lists look.

require("commonrequire")

local lfs = require("libs/libkoreader-lfs")

local Preferences = dofile("plugins/ao3.koplugin/preferences.lua")
local Account = dofile("plugins/ao3.koplugin/account.lua")

describe("AO3 reader preferences", function()
    local dir, path

    before_each(function()
        local DataStorage = require("datastorage")
        dir = DataStorage:getFullDataDir() .. "/ao3_prefs_spec"
        if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
        path = dir .. "/ao3_prefs.lua"
        os.remove(path)
        os.remove(path .. ".old")
    end)

    after_each(function()
        os.remove(path)
        os.remove(path .. ".old")
    end)

    it("folds the tag box when nothing has been chosen yet", function()
        local prefs = Preferences.load(path)
        assert.is_false(prefs.tags_expanded)
    end)

    it("round-trips the tag default", function()
        assert.is_true(Preferences.save({ tags_expanded = true }, path))
        assert.is_true(Preferences.load(path).tags_expanded)

        assert.is_true(Preferences.save({ tags_expanded = false }, path))
        assert.is_false(Preferences.load(path).tags_expanded)
    end)

    it("ignores a value that is not a boolean", function()
        local f = assert(io.open(path, "wb"))
        f:write('return { ["tags_expanded"] = "yes" }\n')
        f:close()
        assert.is_false(Preferences.load(path).tags_expanded)
    end)

    it("keeps its file separate from the session file", function()
        local DataStorage = require("datastorage")
        local old_dir = DataStorage.getSettingsDir
        DataStorage.getSettingsDir = function() return dir end
        local prefs_path = Preferences.path()
        local session_path = Account.settingsPath()
        DataStorage.getSettingsDir = old_dir

        assert.are.equal(dir .. "/ao3_prefs.lua", prefs_path)
        assert.are.equal(dir .. "/ao3.lua", session_path)
        assert.are_not.equal(prefs_path, session_path)
    end)
end)
