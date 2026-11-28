-- Offline tests for the background update check and its in-plugin prompt.
--
-- The cadence is a pure function, so the 15-minute and 24-hour rules are
-- checked without a timer. The prompt is checked against a stubbed window
-- stack, so "the reader is on top" is a plain table. Nothing here reaches the
-- network: the manifest fetch is replaced before the timer body runs.

require("commonrequire")

local UIManager = require("ui/uimanager")
local NetworkMgr = require("ui/network/manager")
local ButtonDialog = require("ui/widget/buttondialog")
local TextViewer = require("ui/widget/textviewer")

local Updater = dofile("plugins/ao3.koplugin/updater.lua")
local Ao3 = dofile("plugins/ao3.koplugin/main.lua")

local NOW = 1700000000

describe("AO3 update check policy", function()
    it("waits a quarter of an hour when offline, whatever is due", function()
        local action, delay = Updater.nextCheck(NOW, 0, false)
        assert.are.equal("wait", action)
        assert.are.equal(15 * 60, delay)
        -- Even a check that is long overdue does not fetch without a network.
        action, delay = Updater.nextCheck(NOW, NOW - 5 * 24 * 60 * 60, false)
        assert.are.equal("wait", action)
        assert.are.equal(Updater.RETRY_INTERVAL, delay)
    end)

    it("re-arms for the rest of the day when a check is not due", function()
        local action, delay = Updater.nextCheck(NOW, NOW - 60 * 60, true)
        assert.are.equal("wait", action)
        assert.are.equal(23 * 60 * 60, delay)
    end)

    it("checks when online and the day has passed", function()
        local action, delay = Updater.nextCheck(NOW, NOW - 24 * 60 * 60, true)
        assert.are.equal("check", action)
        assert.are.equal(0, delay)
        -- A first run (no stored timestamp) is due immediately.
        action = Updater.nextCheck(NOW, 0, true)
        assert.are.equal("check", action)
    end)

    it("does not park a check for more than a day after a clock change", function()
        local action, delay = Updater.nextCheck(NOW, NOW + 60 * 60, true)
        assert.are.equal("wait", action)
        assert.are.equal(Updater.CHECK_INTERVAL, delay)
    end)

    it("is due at the exact 24-hour mark", function()
        assert.are.equal("check", Updater.nextCheck(NOW, NOW - 24 * 60 * 60, true))
        assert.are.equal("wait", Updater.nextCheck(NOW, NOW - 24 * 60 * 60 + 1, true))
    end)
end)

describe("AO3 update prompt policy", function()
    it("asks for a version the reader has not dismissed", function()
        assert.is_true(Updater.promptDue("1.6.0", "", 0, NOW))
        assert.is_true(Updater.promptDue("1.6.0", "1.5.0", 0, NOW))
    end)

    it("never asks for the dismissed version, but asks for a newer one", function()
        assert.is_false(Updater.promptDue("1.6.0", "1.6.0", 0, NOW))
        assert.is_true(Updater.promptDue("1.7.0", "1.6.0", 0, NOW))
    end)

    it("stays quiet inside a remind-later window", function()
        assert.is_false(Updater.promptDue("1.6.0", "", NOW + 60, NOW))
        assert.is_true(Updater.promptDue("1.6.0", "", NOW, NOW))
        assert.is_true(Updater.promptDue("1.6.0", "", NOW - 60, NOW))
    end)

    it("has nothing to ask without a version", function()
        assert.is_false(Updater.promptDue(nil, "", 0, NOW))
        assert.is_false(Updater.promptDue("", "", 0, NOW))
    end)
end)

describe("AO3 background update checks", function()
    local plugin
    local scheduled, cancelled, shown, logs
    local saved

    local function fake_reader()
        return {
            document = {},
            onClose = function()
                table.remove(UIManager._window_stack)
            end,
        }
    end

    local function menu_on_top()
        plugin.menu = { name = "ao3" }
        UIManager._window_stack = { { widget = plugin.menu } }
        return plugin.menu
    end

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
        plugin.path = "/tmp/ao3.koplugin"
        plugin.prefs = {
            last_check_ts = 0,
            remind_after_ts = 0,
            dismissed_version = "",
        }
        plugin.savePrefs = function() end

        scheduled, cancelled, shown, logs = {}, {}, {}, {}

        saved = {
            time = os.time,
            connected = NetworkMgr.isConnected,
            scheduleIn = UIManager.scheduleIn,
            unschedule = UIManager.unschedule,
            show = UIManager.show,
            close = UIManager.close,
            stack = UIManager._window_stack,
            fetch = Ao3.Updater.fetchManifest,
            current = Ao3.Updater.currentVersion,
            isNewer = Ao3.Updater.isNewer,
            log = Ao3.BugReport.log,
        }

        os.time = function() return NOW end
        NetworkMgr.isConnected = function() return true end
        UIManager.scheduleIn = function(_, seconds, action)
            scheduled[#scheduled + 1] = { delay = seconds, action = action }
        end
        UIManager.unschedule = function(_, action)
            cancelled[#cancelled + 1] = action
            return true
        end
        UIManager.show = function(_, widget) shown[#shown + 1] = widget end
        UIManager.close = function() end
        UIManager._window_stack = { { widget = {} } }
        Ao3.Updater.currentVersion = function() return "1.5.0" end
        Ao3.BugReport.log = function(category, message)
            logs[#logs + 1] = tostring(category) .. ": " .. tostring(message)
        end
    end)

    after_each(function()
        plugin:disarmUpdateCheck()
        plugin.menu = nil
        os.time = saved.time
        NetworkMgr.isConnected = saved.connected
        UIManager.scheduleIn = saved.scheduleIn
        UIManager.unschedule = saved.unschedule
        UIManager.show = saved.show
        UIManager.close = saved.close
        UIManager._window_stack = saved.stack
        Ao3.Updater.fetchManifest = saved.fetch
        Ao3.Updater.currentVersion = saved.current
        Ao3.Updater.isNewer = saved.isNewer
        Ao3.BugReport.log = saved.log
    end)

    it("arms one timer with the same function reference and never stacks", function()
        plugin:startUpdateChecks()
        assert.is_true(plugin.update_timer_armed)
        assert.are.equal(1, #scheduled)
        assert.are.equal(Ao3.updateTick, scheduled[1].action)

        -- Returning to the landing page must not add a second timer.
        plugin:startUpdateChecks()
        assert.are.equal(1, #scheduled)

        -- Re-arming replaces the pending tick, and cancellation uses the same
        -- reference, so UIManager:unschedule can find it.
        plugin:armUpdateCheck(60)
        assert.are.equal(2, #scheduled)
        assert.are.equal(Ao3.updateTick, scheduled[2].action)
        assert.are.equal(60, scheduled[2].delay)
        assert.are.equal(Ao3.updateTick, cancelled[#cancelled])

        plugin:disarmUpdateCheck()
        assert.is_false(plugin.update_timer_armed)
        assert.are.equal(Ao3.updateTick, cancelled[#cancelled])
    end)

    it("does not fetch while offline and retries in fifteen minutes", function()
        local fetched = 0
        NetworkMgr.isConnected = function() return false end
        Ao3.Updater.fetchManifest = function()
            fetched = fetched + 1
            return { version = "1.6.0" }
        end

        plugin:backgroundUpdateCheck()

        assert.are.equal(0, fetched)
        assert.is_nil(plugin.pending_update)
        assert.are.equal(Updater.RETRY_INTERVAL, scheduled[#scheduled].delay)
        assert.are.equal(0, #shown)
    end)

    it("re-arms for the remainder of the day without fetching", function()
        local fetched = 0
        plugin.prefs.last_check_ts = NOW - 60 * 60
        Ao3.Updater.fetchManifest = function()
            fetched = fetched + 1
            return { version = "1.6.0" }
        end

        plugin:backgroundUpdateCheck()

        assert.are.equal(0, fetched)
        assert.are.equal(23 * 60 * 60, scheduled[#scheduled].delay)
        assert.is_nil(plugin.pending_update)
    end)

    it("records a newer release without drawing anything", function()
        local saves = 0
        plugin.savePrefs = function() saves = saves + 1 end
        plugin.prefs.last_check_ts = NOW - 25 * 60 * 60
        Ao3.Updater.fetchManifest = function() return { version = "1.6.0" } end

        plugin:backgroundUpdateCheck()

        assert.are.equal("1.6.0", plugin.pending_update.version)
        assert.are.equal(NOW, plugin.prefs.last_check_ts)
        assert.are.equal(1, saves)
        assert.are.equal(0, #shown)
        assert.are.equal(Updater.CHECK_INTERVAL, scheduled[#scheduled].delay)
    end)

    it("keeps a current release unpromising", function()
        plugin.prefs.last_check_ts = 0
        Ao3.Updater.fetchManifest = function() return { version = "1.5.0" } end

        plugin:backgroundUpdateCheck()

        assert.is_nil(plugin.pending_update)
        assert.are.equal(NOW, plugin.prefs.last_check_ts)
        assert.are.equal(0, #shown)
    end)

    it("logs a failed check, re-arms and shows no error dialog", function()
        plugin.prefs.last_check_ts = 0
        Ao3.Updater.fetchManifest = function() return nil, "HTTP 500" end

        plugin:backgroundUpdateCheck()

        assert.is_nil(plugin.pending_update)
        assert.are.equal(Updater.RETRY_INTERVAL, scheduled[#scheduled].delay)
        assert.are.equal(0, #shown)
        assert.is_truthy(logs[#logs]:find("background check failed", 1, true))
    end)

    it("contains an error raised inside the fetch", function()
        plugin.prefs.last_check_ts = 0
        Ao3.Updater.fetchManifest = function() error("boom") end

        local ok, err = pcall(function() plugin:backgroundUpdateCheck() end)

        assert.is_true(ok, err)
        assert.are.equal(Updater.RETRY_INTERVAL, scheduled[#scheduled].delay)
        assert.are.equal(0, #shown)
        assert.is_truthy(logs[#logs]:find("boom", 1, true))
    end)

    it("asks on the landing page, with the four native choices", function()
        menu_on_top()
        plugin.pending_update = { version = "1.6.0" }

        assert.is_true(plugin:maybePromptUpdate())
        assert.are.equal(1, #shown)
        local dialog = shown[1]
        assert.are.equal(ButtonDialog, getmetatable(dialog).__index)
        assert.are.equal(4, #dialog.buttons)
        assert.are.equal("Update", dialog.buttons[1][1].text)
        assert.are.equal("Remind later", dialog.buttons[2][1].text)
        assert.are.equal("Dismiss", dialog.buttons[3][1].text)
        assert.are.equal("Changelog", dialog.buttons[4][1].text)
        assert.is_truthy(dialog.title:find("1.6.0", 1, true))
        assert.is_truthy(dialog.title:find("1.5.0", 1, true))
    end)

    it("opens the release notes from the Changelog action", function()
        menu_on_top()
        plugin.pending_update = {
            version = "1.6.0",
            notes = "Changes in v1.6.0:\n- Faster lists\n- Fixed cards",
        }

        assert.is_true(plugin:maybePromptUpdate())
        shown[1].buttons[4][1].callback()

        local viewer = shown[#shown]
        assert.are.equal(TextViewer, getmetatable(viewer).__index)
        assert.are.equal("Changes in v1.6.0:\n- Faster lists\n- Fixed cards",
            viewer.text)
        assert.is_truthy(viewer.title:find("1.6.0", 1, true))
        -- Closing the notes returns to the same choices: the release is still
        -- pending and nothing was dismissed.
        assert.are.equal("1.6.0", plugin.pending_update.version)
        assert.are.equal(2, #shown)
    end)

    it("says a release has no changelog instead of opening an empty page", function()
        menu_on_top()
        plugin.pending_update = { version = "1.6.0", notes = "" }

        assert.is_true(plugin:maybePromptUpdate())
        shown[1].buttons[4][1].callback()

        assert.are.equal("This release has no changelog.", shown[#shown].text)
    end)

    it("never draws over the reader", function()
        local menu = menu_on_top()
        UIManager._window_stack = { { widget = menu }, { widget = fake_reader() } }
        plugin.pending_update = { version = "1.6.0" }

        assert.is_false(plugin:maybePromptUpdate())
        assert.are.equal(0, #shown)
    end)

    it("has nowhere to ask when the menu is closed", function()
        plugin.menu = nil
        UIManager._window_stack = {}
        plugin.pending_update = { version = "1.6.0" }

        assert.is_false(plugin:maybePromptUpdate())
        assert.are.equal(0, #shown)
    end)

    it("drops a pending release that is already installed", function()
        menu_on_top()
        plugin.pending_update = { version = "1.6.0" }
        Ao3.Updater.currentVersion = function() return "1.6.0" end

        assert.is_false(plugin:maybePromptUpdate())
        assert.is_nil(plugin.pending_update)
    end)

    it("does not ask for a dismissed version, but asks for a later release", function()
        menu_on_top()
        plugin.pending_update = { version = "1.6.0" }
        plugin.prefs.dismissed_version = "1.6.0"

        assert.is_false(plugin:maybePromptUpdate())
        assert.are.equal(0, #shown)

        plugin.pending_update = { version = "1.7.0" }
        assert.is_true(plugin:maybePromptUpdate())
    end)

    it("stays quiet until a remind-later window ends", function()
        menu_on_top()
        plugin.pending_update = { version = "1.6.0" }
        plugin.prefs.remind_after_ts = NOW + 60 * 60

        assert.is_false(plugin:maybePromptUpdate())

        plugin.prefs.remind_after_ts = NOW - 1
        assert.is_true(plugin:maybePromptUpdate())
    end)

    it("updates from the prompt on a tap and clears the pending release", function()
        menu_on_top()
        plugin.pending_update = { version = "1.6.0" }
        local installed
        plugin.installUpdate = function(_, dir, manifest)
            installed = { dir = dir, manifest = manifest }
        end

        assert.is_true(plugin:maybePromptUpdate())
        shown[1].buttons[1][1].callback()

        assert.are.equal("/tmp/ao3.koplugin", installed.dir)
        assert.are.equal("1.6.0", installed.manifest.version)
        assert.is_nil(plugin.pending_update)
    end)

    it("reminds later by keeping the release for the next day", function()
        menu_on_top()
        plugin.pending_update = { version = "1.6.0" }
        local saves = 0
        plugin.savePrefs = function() saves = saves + 1 end

        assert.is_true(plugin:maybePromptUpdate())
        shown[1].buttons[2][1].callback()

        assert.are.equal(1, saves)
        assert.are.equal(NOW + Updater.CHECK_INTERVAL, plugin.prefs.remind_after_ts)
        assert.are.equal("1.6.0", plugin.pending_update.version)
        -- The same window blocks the next prompt in this session.
        assert.is_false(plugin:maybePromptUpdate())
    end)

    it("dismisses the version it was shown, not the next one", function()
        menu_on_top()
        plugin.pending_update = { version = "1.6.0" }
        local saves = 0
        plugin.savePrefs = function() saves = saves + 1 end

        assert.is_true(plugin:maybePromptUpdate())
        shown[1].buttons[3][1].callback()

        assert.are.equal(1, saves)
        assert.are.equal("1.6.0", plugin.prefs.dismissed_version)
        assert.are.equal(0, plugin.prefs.remind_after_ts)
        assert.is_nil(plugin.pending_update)

        plugin.pending_update = { version = "1.7.0" }
        assert.is_true(plugin:maybePromptUpdate())
    end)

    it("shows the pending prompt when Back from the reader returns to the plugin", function()
        local menu = menu_on_top()
        local reader = fake_reader()
        plugin:installReaderHooks(reader)
        UIManager._window_stack = { { widget = menu }, { widget = reader } }
        plugin.pending_update = { version = "1.6.0" }

        -- While the book is open there is no prompt.
        assert.is_false(plugin:maybePromptUpdate())
        assert.are.equal(0, #shown)

        reader.onHome()

        assert.are.equal(1, #shown)
        assert.is_true(plugin:maybePromptUpdate())
    end)

    it("stops the timer when the menu closes and resumes it on open", function()
        local old_show = UIManager.show
        UIManager.show = function() end
        plugin:showHome()
        UIManager.show = old_show

        assert.is_true(plugin.update_timer_armed)
        assert.are.equal(Ao3.updateTick, scheduled[#scheduled].action)

        -- The closed menu leaves a window beneath it, so nothing else is shown.
        UIManager._window_stack = { { widget = {} } }
        plugin:onMenuClosed()
        assert.is_false(plugin.update_timer_armed)
        -- Both background timers leave with the menu.
        local cancelled_update = false
        for _, action in ipairs(cancelled) do
            if action == Ao3.updateTick then cancelled_update = true end
        end
        assert.is_true(cancelled_update)
    end)
end)
