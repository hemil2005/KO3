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

    it("uses the modern work card when nothing has been chosen yet", function()
        assert.are.equal("modern", Preferences.load(path).card_style)
    end)

    it("falls back to the modern card for an unknown design", function()
        local f = assert(io.open(path, "wb"))
        f:write('return { ["card_style"] = "ornate" }\n')
        f:close()
        assert.are.equal("modern", Preferences.load(path).card_style)
    end)

    it("round-trips the legacy work card", function()
        assert.is_true(Preferences.save({ card_style = "legacy" }, path))
        assert.are.equal("legacy", Preferences.load(path).card_style)
    end)

    it("stores a design it does not know as the modern card", function()
        assert.is_true(Preferences.save({ card_style = "ornate" }, path))
        assert.are.equal("modern", Preferences.load(path).card_style)
    end)

    it("starts with no update bookkeeping", function()
        local prefs = Preferences.load(path)
        assert.are.equal(0, prefs.last_check_ts)
        assert.are.equal(0, prefs.remind_after_ts)
        assert.are.equal("", prefs.dismissed_version)
    end)

    it("round-trips the update bookkeeping", function()
        assert.is_true(Preferences.save({
            tags_expanded = false,
            last_check_ts = 1700000000,
            remind_after_ts = 1700086400,
            dismissed_version = "1.6.0",
        }, path))
        local prefs = Preferences.load(path)
        assert.are.equal(1700000000, prefs.last_check_ts)
        assert.are.equal(1700086400, prefs.remind_after_ts)
        assert.are.equal("1.6.0", prefs.dismissed_version)
    end)

    it("ignores hand-edited timestamps and a non-string version", function()
        local f = assert(io.open(path, "wb"))
        f:write('return { ["last_check_ts"] = "soon", ["remind_after_ts"] = -5,'
            .. ' ["dismissed_version"] = 7 }\n')
        f:close()
        local prefs = Preferences.load(path)
        assert.are.equal(0, prefs.last_check_ts)
        assert.are.equal(0, prefs.remind_after_ts)
        assert.are.equal("", prefs.dismissed_version)
    end)

    it("keeps the update bookkeeping when a display choice changes", function()
        -- Toggling a setting saves the whole table; a dismissed release must
        -- survive that or the prompt would come back on the next open.
        local prefs = Preferences.load(path)
        prefs.dismissed_version = "1.6.0"
        prefs.last_check_ts = 1700000000
        assert.is_true(Preferences.save(prefs, path))
        prefs.tags_expanded = true
        assert.is_true(Preferences.save(prefs, path))

        local reread = Preferences.load(path)
        assert.is_true(reread.tags_expanded)
        assert.are.equal("1.6.0", reread.dismissed_version)
        assert.are.equal(1700000000, reread.last_check_ts)
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
