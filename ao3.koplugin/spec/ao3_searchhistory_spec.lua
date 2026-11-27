-- KOReader busted spec for the recent-searches picker.
--
-- The picker is a ButtonDialog shown from an InputDialog. On a touch reader
-- the on-screen keyboard is a separate window that stays above a later dialog
-- for input, so every tap on the picker is swallowed and its box sits there
-- looking open but dead. These tests pin the keyboard hide/restore and the
-- single text update that keep the picker usable.

require("commonrequire")

local UIManager = require("ui/uimanager")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")

describe("AO3 search history picker", function()
    local plugin
    local calls
    local saved

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
        calls = {}
        saved = {
            show = UIManager.show,
            close = UIManager.close,
            setDirty = UIManager.setDirty,
        }
        UIManager.show = function(_, widget)
            calls[#calls + 1] = "show"
            plugin._shown = widget
        end
        UIManager.close = function()
            calls[#calls + 1] = "close"
        end
        UIManager.setDirty = function(_, kind, region)
            calls[#calls + 1] = "dirty:" .. tostring(kind) .. ":" .. tostring(region)
        end
    end)

    after_each(function()
        UIManager.show = saved.show
        UIManager.close = saved.close
        UIManager.setDirty = saved.setDirty
    end)

    local function fake_dialog(visible)
        return {
            isKeyboardVisible = function() return visible end,
            onCloseKeyboard = function()
                calls[#calls + 1] = "hide-keyboard"
            end,
            onShowKeyboard = function()
                calls[#calls + 1] = "show-keyboard"
            end,
            setInputText = function(_, text, cursor_at_end)
                calls[#calls + 1] = "text:" .. tostring(text) .. ":"
                    .. tostring(cursor_at_end)
            end,
        }
    end

    local function picker_for(entries, dialog)
        plugin._shown = nil
        plugin:showSearchHistoryEntries(dialog, entries)
        return assert(plugin._shown)
    end

    local function count(value)
        local n = 0
        for _, call in ipairs(calls) do
            if call == value then n = n + 1 end
        end
        return n
    end

    it("hides the keyboard before the picker and restores it after a pick", function()
        local dialog = fake_dialog(true)
        local picker = picker_for({ "kingsaxcul", "wardown" }, dialog)

        assert.are.equal("show", calls[#calls])
        assert.is_true(calls[#calls - 1] == "hide-keyboard")

        picker.buttons[1][1].callback()
        assert.are.equal("close", calls[#calls - 3])
        assert.are.equal("text:kingsaxcul:true", calls[#calls - 2])
        assert.are.equal("show-keyboard", calls[#calls - 1])
        assert.are.equal("dirty:all:ui", calls[#calls])
        -- One update, not a clear followed by a set.
        assert.are.equal(1, count("text:kingsaxcul:true"))
    end)

    it("does not double-restore the keyboard when the picker closes", function()
        local dialog = fake_dialog(true)
        local picker = picker_for({ "kingsaxcul" }, dialog)
        picker.buttons[1][1].callback()
        -- A real close calls onCloseWidget after the callback.
        picker.onCloseWidget(picker)
        assert.are.equal(1, count("show-keyboard"))
    end)

    it("restores the keyboard when the picker is dismissed", function()
        local dialog = fake_dialog(true)
        local picker = picker_for({ "kingsaxcul" }, dialog)
        assert.are.equal(1, count("hide-keyboard"))
        picker.onCloseWidget(picker)
        assert.are.equal(1, count("show-keyboard"))
        assert.are.equal(0, count("text:"))
    end)

    it("leaves a hidden keyboard alone", function()
        local dialog = fake_dialog(false)
        local picker = picker_for({ "astolat" }, dialog)
        assert.are.equal(0, count("hide-keyboard"))
        assert.are.equal(0, count("show-keyboard"))

        picker.buttons[1][1].callback()
        assert.are.equal("text:astolat:true", calls[#calls - 1])
        assert.are.equal(0, count("show-keyboard"))
        assert.are.equal(0, count("hide-keyboard"))
    end)

    it("gives an entry an edit caret at the end", function()
        local dialog = fake_dialog(false)
        local picker = picker_for({ "Harbor Lights" }, dialog)
        picker.buttons[1][1].callback()
        assert.are.equal("text:Harbor Lights:true", calls[#calls - 1])
    end)
end)
