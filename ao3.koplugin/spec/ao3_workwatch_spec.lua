-- KOReader busted spec for the quiet saved-work update watch.
--
--   ln -s ../../plugins/ao3.koplugin/spec/ao3_workwatch_spec.lua spec/unit/
--   ./kodev test --busted=--pattern=ao3_workwatch front
--
-- The watch asks AO3 for the chapter menu (`/works/<id>/navigate`), never for
-- the work page or the saved file's chapters, so these tests stub the
-- transport and check which work ids were asked about, what was remembered,
-- and what the bell, the Updates screen and the Downloads rows say. No test
-- reaches AO3.

require("commonrequire")

local DataStorage = require("datastorage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")

local Account = dofile("plugins/ao3.koplugin/account.lua")
local Ao3 = dofile("plugins/ao3.koplugin/main.lua")
local Preferences = dofile("plugins/ao3.koplugin/preferences.lua")
local WorkUpdate = dofile("plugins/ao3.koplugin/workupdate.lua")
local WorkWatch = dofile("plugins/ao3.koplugin/workwatch.lua")

local function download_dir()
    return DataStorage:getFullDataDir() .. "/ao3"
end

local function clear_downloads()
    local dir = download_dir()
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    for entry in lfs.dir(dir) do
        if entry ~= "." and entry ~= ".." then
            os.remove(dir .. "/" .. entry)
        end
    end
end

-- The same shape AO3's downloadable work file uses: the preface's stats list
-- pairs a label with the value the plugin reads.
local function work_html(chapters)
    return '<html><body><div id="preface"><dl class="work meta group">'
        .. '<dt class="stats">Stats:</dt><dd class="stats"><dl class="stats">'
        .. '<dt class="chapters">Chapters:</dt><dd class="chapters">'
        .. chapters .. '</dd>'
        .. '</dl></dd></dl></div></body></html>'
end

local function write_work(name, chapters)
    local dir = download_dir()
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local path = dir .. "/" .. name
    local f = assert(io.open(path, "wb"))
    f:write(work_html(chapters))
    f:close()
    return path
end

-- The chapter menu AO3 renders for /works/<id>/navigate: one li per posted
-- chapter, with a date and no work text.
local function navigate(count)
    local parts = {
        '<h2 class="heading">A Work by Someone</h2>',
        '<ol class="chapter index group" role="navigation">',
    }
    for i = 1, count do
        parts[#parts + 1] = '<li><a href="/works/201/chapters/' .. (1000 + i)
            .. '">Chapter ' .. i .. '</a> <span class="datetime">(2020-07-0'
            .. i .. ')</span></li>'
    end
    parts[#parts + 1] = '</ol>'
    return table.concat(parts, "\n")
end

local function role(rows, name)
    for _, row in ipairs(rows) do
        if row.role == name then return row end
    end
end

local function read_fixture(name)
    local f = assert(io.open("plugins/ao3.koplugin/spec/fixtures/" .. name, "rb"))
    local body = f:read("*a")
    f:close()
    return body
end

describe("AO3 chapter menu parsing", function()
    it("counts the chapter list AO3 renders", function()
        assert.are.equal(7, WorkUpdate.parseChapterIndex(navigate(7)))
        assert.are.equal(1, WorkUpdate.parseChapterIndex(navigate(1)))
    end)

    it("falls back to distinct chapter links when the wrapper changes", function()
        local html = '<div class="chapters">'
            .. '<a href="/works/201/chapters/11">One</a>'
            .. '<a href="/works/201/chapters/12">Two</a>'
            .. '<a href="/works/201/chapters/12">Two again</a>'
            .. '</div>'
        assert.are.equal(2, WorkUpdate.parseChapterIndex(html))
    end)

    it("refuses anything that is not a chapter list", function()
        assert.is_nil(WorkUpdate.parseChapterIndex(""))
        assert.is_nil(WorkUpdate.parseChapterIndex(nil))
        assert.is_nil(WorkUpdate.parseChapterIndex(
            '<html><body><form id="new_user">Log in</form></body></html>'))
        assert.is_nil(WorkUpdate.parseChapterIndex(
            '<ol class="chapter index group"></ol>'))
    end)
end)

describe("AO3 quiet watch state", function()
    local dir, path

    before_each(function()
        dir = DataStorage:getFullDataDir() .. "/ao3_watch_spec"
        if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
        path = dir .. "/ao3_prefs.lua"
        os.remove(path)
        os.remove(path .. ".old")
        clear_downloads()
    end)

    after_each(function()
        os.remove(path)
        os.remove(path .. ".old")
        clear_downloads()
    end)

    it("round-trips one check per work id", function()
        local prefs = {
            work_checks = {
                ["201"] = { ts = 1700000000, chapters = 5 },
                ["202"] = { ts = 1700000100, gone = true },
            },
            updates_seen_ts = 1700000200,
        }
        assert.is_true(Preferences.save(prefs, path))
        local loaded = Preferences.load(path)
        assert.are.equal(5, loaded.work_checks["201"].chapters)
        assert.are.equal(1700000000, loaded.work_checks["201"].ts)
        assert.is_true(loaded.work_checks["202"].gone)
        assert.are.equal(1700000200, loaded.updates_seen_ts)
    end)

    it("round-trips the subscription switch and list", function()
        assert.is_true(Preferences.save({
            check_subscriptions = false,
            subscription_check_ts = 1700000000,
            work_subscriptions = {
                { id = "111", title = "Followed" },
                { id = "111", title = "Again" },
                { id = "222", title = "" },
                { id = "x", title = "Bad" },
            },
        }, path))
        local loaded = Preferences.load(path)
        assert.is_false(loaded.check_subscriptions)
        assert.are.equal(1700000000, loaded.subscription_check_ts)
        assert.are.equal(2, #loaded.work_subscriptions)
        assert.are.equal("111", loaded.work_subscriptions[1].id)
        assert.are.equal("Followed", loaded.work_subscriptions[1].title)
        assert.are.equal("222", loaded.work_subscriptions[2].id)
        assert.are.equal("Work 222", loaded.work_subscriptions[2].title)
        -- Unset in an older file means the switch is on.
        assert.is_true(Preferences.load(path).check_subscriptions == false)
        os.remove(path)
        os.remove(path .. ".old")
        assert.is_true(Preferences.load(path).check_subscriptions)
    end)

    it("drops hand-edited entries that could invent a badge", function()
        local f = assert(io.open(path, "wb"))
        f:write('return { ["work_checks"] = {'
            .. '["201"] = { ["ts"] = 1700000000, ["chapters"] = 5 },'
            .. '["x"] = { ["ts"] = 1700000000, ["chapters"] = 5 },'
            .. '["202"] = { ["ts"] = 1700000000, ["chapters"] = 0 },'
            .. '["203"] = { ["ts"] = "soon", ["chapters"] = 4 },'
            .. '["204"] = "nope" } }\n')
        f:close()
        local checks = Preferences.load(path).work_checks
        assert.are.equal(5, checks["201"].chapters)
        assert.is_nil(checks["x"])
        assert.is_nil(checks["202"])
        assert.is_nil(checks["203"])
        assert.is_nil(checks["204"])
    end)

    it("asks about a work at most once a day", function()
        local item = { id = "201", path = write_work("A [201].html", "3/?") }
        local now = 1700000000
        local prefs = { work_checks = {} }

        assert.is_true(WorkWatch.due(prefs, item, now, WorkWatch.INTERVAL))
        WorkWatch.record(prefs, "201", 3, now)
        assert.is_false(WorkWatch.due(prefs, item, now + 60, WorkWatch.INTERVAL))
        assert.is_true(WorkWatch.due(prefs, item,
            now + WorkWatch.INTERVAL, WorkWatch.INTERVAL))
        -- The manual run ignores the interval.
        assert.is_true(WorkWatch.due(prefs, item, now + 60, 0))
    end)

    it("never asks about a one-shot, a finished save or a missing work", function()
        local shot = { id = "202", path = write_work("Shot [202].html", "1/1") }
        local done = { id = "203", path = write_work("Done [203].html", "7/7") }
        local missing = { id = "204", path = download_dir() .. "/gone.html" }
        local prefs = { work_checks = {} }
        local now = 1700000000

        assert.is_false(WorkWatch.due(prefs, shot, now))
        assert.is_false(WorkWatch.due(prefs, done, now))
        assert.is_false(WorkWatch.due(prefs, missing, now))
        assert.are.equal(0, #WorkWatch.plan({ shot, done, missing }, prefs, now))
    end)

    it("plans the oldest checks first and respects the budget", function()
        local items = {}
        local prefs = { work_checks = {} }
        for i = 1, 5 do
            local id = tostring(300 + i)
            items[i] = { id = id, path = write_work("W" .. i .. " [" .. id .. "].html", "2/?") }
            if i > 2 then
                prefs.work_checks[id] = { ts = 1700000000 + i, chapters = 2 }
            end
        end
        local now = 1700000000 + 10 * WorkWatch.INTERVAL
        local queue = WorkWatch.plan(items, prefs, now, { budget = 2 })

        assert.are.equal(2, #queue)
        -- The two never-checked works come before the older stored timestamps.
        assert.are.equal("301", queue[1].id)
        assert.are.equal("302", queue[2].id)
    end)

    it("forgets ids whose saved file is gone", function()
        local prefs = { work_checks = { ["201"] = { ts = 1, chapters = 3 } } }
        WorkWatch.plan({}, prefs, 1700000000)
        assert.is_nil(prefs.work_checks["201"])
    end)

    it("counts only chapters the saved copy does not have", function()
        local item = { id = "201", path = write_work("A [201].html", "3/7") }
        local prefs = { work_checks = { ["201"] = { ts = 1, chapters = 5 } } }

        assert.are.equal(2, WorkWatch.added(prefs, item))
        assert.is_true(WorkWatch.unread(prefs, { item }, 0))
        assert.is_false(WorkWatch.unread(prefs, { item }, 2))

        -- After the work is refreshed the same entry no longer has a gap.
        write_work("A [201].html", "5/7")
        assert.are.equal(0, WorkWatch.added(prefs, item))
        assert.is_false(WorkWatch.unread(prefs, { item }, 0))
    end)

    it("lists the works a check found, and the ones AO3 no longer serves", function()
        local fresh = { id = "201", path = write_work("New [201].html", "3/7") }
        local gone = { id = "202", path = write_work("Gone [202].html", "2/2") }
        local quiet = { id = "203", path = write_work("Quiet [203].html", "4/7") }
        local prefs = {
            work_checks = {
                ["201"] = { ts = 2, chapters = 5 },
                ["202"] = { ts = 2, gone = true },
                ["203"] = { ts = 2, chapters = 4 },
            },
        }

        local found = WorkWatch.updates(prefs, { fresh, gone, quiet })
        assert.are.equal(2, #found)
        assert.are.equal("201", found[1].item.id)
        assert.are.equal(2, found[1].added)
        assert.are.equal("202", found[2].item.id)
        assert.is_true(found[2].gone)
    end)

    it("baselines a subscribed work, then counts the gap", function()
        local prefs = {
            work_checks = {},
            work_subscriptions = { { id = "401", title = "Followed" } },
            updates_seen_ts = 0,
        }
        local now = 1700000000

        -- The first answer is the baseline: no badge for the chapters it
        -- already has when the reader subscribes.
        WorkWatch.record(prefs, "401", 12, now, false, { subscribed = true })
        assert.are.equal(0, WorkWatch.subscribedAdded(prefs, "401"))

        -- A later answer keeps the known count and moves only the live one.
        WorkWatch.record(prefs, "401", 14, now + 60, false, { subscribed = true })
        assert.are.equal(2, WorkWatch.subscribedAdded(prefs, "401"))
        assert.is_true(WorkWatch.unread(prefs, {}, now - 1))
        assert.is_false(WorkWatch.unread(prefs, {}, now + 60))

        local found = WorkWatch.updates(prefs, {})
        assert.are.equal(1, #found)
        assert.is_true(found[1].subscribed)
        assert.are.equal(2, found[1].added)
        assert.are.equal(12, found[1].current)
        assert.are.equal(14, found[1].live)

        -- Downloading it acknowledges the chapters in hand.
        WorkWatch.acknowledge(prefs, "401")
        assert.are.equal(0, WorkWatch.subscribedAdded(prefs, "401"))
        assert.is_nil(prefs.work_checks["401"].live)
    end)

    it("treats a subscribed work as due without a saved file", function()
        local prefs = { work_checks = {} }
        local item = { id = "401", title = "Followed", subscribed = true }
        local now = 1700000000

        assert.is_true(WorkWatch.due(prefs, item, now))
        WorkWatch.record(prefs, "401", 12, now, false, { subscribed = true })
        assert.is_false(WorkWatch.due(prefs, item, now + 60))
        assert.is_true(WorkWatch.due(prefs, item, now + WorkWatch.INTERVAL))
    end)
end)

describe("AO3 quiet watch on the plugin", function()
    local plugin, saved, requests, scheduled

    local function outside(label, code)
        return nil, label, code
    end

    before_each(function()
        clear_downloads()
        plugin = setmetatable({}, { __index = Ao3 })
        plugin.prefs = { work_checks = {}, updates_seen_ts = 0 }
        plugin.savePrefs = function() end
        plugin.afterWorkWatch = function() end
        requests, scheduled = {}, {}
        plugin.httpRequest = function(_, url, opts, timeout)
            requests[#requests + 1] = url
            assert.is_nil(opts and opts.cookie)
            assert.are.equal(12, timeout)
            return navigate(4), nil, 200
        end

        saved = {
            scheduleIn = UIManager.scheduleIn,
            unschedule = UIManager.unschedule,
            isConnected = require("ui/network/manager").isConnected,
            runWhenOnline = require("ui/network/manager").runWhenOnline,
            afterWifiAction = require("ui/network/manager").afterWifiAction,
            trapper = package.loaded["ui/trapper"],
        }
        UIManager.scheduleIn = function(_, delay) scheduled[#scheduled + 1] = delay end
        UIManager.unschedule = function() end
        require("ui/network/manager").isConnected = function() return true end
    end)

    after_each(function()
        UIManager.scheduleIn = saved.scheduleIn
        UIManager.unschedule = saved.unschedule
        local NetworkMgr = require("ui/network/manager")
        NetworkMgr.isConnected = saved.isConnected
        NetworkMgr.runWhenOnline = saved.runWhenOnline
        NetworkMgr.afterWifiAction = saved.afterWifiAction
        package.loaded["ui/trapper"] = saved.trapper
        clear_downloads()
    end)

    it("asks the chapter menu and remembers the answer", function()
        write_work("WIP [201].html", "3/?")
        write_work("Also WIP [202].html", "2/?")

        plugin:watchStep()

        assert.are.equal(1, #requests)
        assert.are.equal(Account.workUrl("201") .. "/navigate", requests[1])
        assert.are.equal(4, plugin.prefs.work_checks["201"].chapters)
        -- One work checked, one still queued: the next tick is the spacing.
        assert.are.equal(WorkWatch.SPACING, scheduled[1])
    end)

    it("reads the Stats row of a real AO3 download", function()
        -- The file the plugin saves has no class="chapters" cell; its preface
        -- spells the count out in one Stats row.
        local path = download_dir() .. "/Real [301].html"
        local f = assert(io.open(path, "wb"))
        f:write('<html><body><div id="preface"><div class="meta">'
            .. '<dl class="tags"><dt>Stats:</dt><dd> Published: 2024-07-03'
            .. ' Words: 675,137 Chapters: 3/7 </dd></dl></div></div>'
            .. '<div id="chapters" class="userstuff"></div></body></html>')
        f:close()

        plugin:watchStep()

        assert.are.equal(4, plugin.prefs.work_checks["301"].chapters)
        assert.are.equal(Account.workUrl("301") .. "/navigate", requests[1])
    end)

    it("reads the subscription list once, then baselines its works", function()
        plugin.prefs = {
            work_checks = {},
            work_subscriptions = {},
            updates_seen_ts = 0,
            check_subscriptions = true,
            subscription_check_ts = 0,
        }
        plugin.session = {
            username = "tester",
            cookies = { _otwarchive_session = "x" },
        }
        local subs = read_fixture("account/subscriptions.html")
        plugin.httpRequest = function(_, url)
            requests[#requests + 1] = url
            if url:find("/subscriptions", 1, true) then
                return subs, nil, 200
            end
            return navigate(15), nil, 200
        end

        plugin:watchStep()  -- the list page
        assert.are.equal(1, #requests)
        assert.are.equal(Account.listUrl("tester", "/subscriptions"), requests[1])
        assert.are.equal(1, #plugin.prefs.work_subscriptions)
        assert.are.equal("111", plugin.prefs.work_subscriptions[1].id)

        plugin:watchStep()  -- one work per tick
        assert.are.equal(2, #requests)
        assert.are.equal(Account.workUrl("111") .. "/navigate", requests[2])
        assert.are.equal(15, plugin.prefs.work_checks["111"].chapters)
        -- The first answer is the baseline, not fifteen new chapters.
        assert.are.equal(0, WorkWatch.subscribedAdded(plugin.prefs, "111"))
    end)

    it("follows the next page of subscriptions", function()
        plugin.prefs = {
            work_checks = {},
            work_subscriptions = {},
            updates_seen_ts = 0,
            check_subscriptions = true,
            subscription_check_ts = 0,
        }
        plugin.session = {
            username = "tester",
            cookies = { _otwarchive_session = "x" },
        }
        local page1 = read_fixture("account/subscriptions.html"):gsub(
            "</body>", '<ol class="pagination"><li class="next">'
            .. '<a href="/users/tester/subscriptions?page=2">Next</a></li></ol></body>')
        local page2 = '<h2 class="heading">My Subscriptions</h2>'
            .. '<dl class="subscription index group"><dt>'
            .. '<a href="/works/333">Third Work</a> (Work) by '
            .. '<a rel="author" href="/users/x">X</a></dt><dd></dd></dl>'
        plugin.httpRequest = function(_, url)
            requests[#requests + 1] = url
            if url:find("page=2", 1, true) then return page2, nil, 200 end
            if url:find("/subscriptions", 1, true) then return page1, nil, 200 end
            return navigate(15), nil, 200
        end

        plugin:watchStep()
        plugin:watchStep()

        assert.are.equal(2, #requests)
        assert.are.equal(2, #plugin.prefs.work_subscriptions)
        assert.are.equal("111", plugin.prefs.work_subscriptions[1].id)
        assert.are.equal("333", plugin.prefs.work_subscriptions[2].id)
    end)

    it("asks nothing about subscriptions when switched off", function()
        write_work("WIP [201].html", "3/?")
        plugin.session = {
            username = "tester",
            cookies = { _otwarchive_session = "x" },
        }
        plugin.prefs = {
            work_checks = {},
            work_subscriptions = {},
            updates_seen_ts = 0,
            check_subscriptions = false,
            subscription_check_ts = 0,
        }

        plugin:watchStep()

        assert.are.equal(1, #requests)
        assert.are.equal(Account.workUrl("201") .. "/navigate", requests[1])
    end)

    it("keeps the cached list when AO3 answers with the login page", function()
        plugin.prefs = {
            work_checks = {},
            work_subscriptions = { { id = "111", title = "Kept" } },
            updates_seen_ts = 0,
            check_subscriptions = true,
            subscription_check_ts = 0,
        }
        plugin.session = {
            username = "tester",
            cookies = { _otwarchive_session = "x" },
        }
        plugin.httpRequest = function(_, url)
            requests[#requests + 1] = url
            return read_fixture("account/login.html"), nil, 200
        end

        plugin:watchStep()

        assert.are.equal(1, #requests)
        assert.are.equal(1, #plugin.prefs.work_subscriptions)
        assert.are.equal("Kept", plugin.prefs.work_subscriptions[1].title)
        assert.are.equal(0, plugin.prefs.subscription_check_ts)
    end)

    it("acknowledges a subscription when the work is downloaded", function()
        plugin.prefs = {
            work_checks = { ["111"] = { ts = 1, chapters = 3, live = 5 } },
            work_subscriptions = { { id = "111", title = "Followed" } },
            updates_seen_ts = 0,
        }
        plugin.downloadWork = function() return "/tmp/followed.html" end
        plugin.openWorkReader = function() end
        package.loaded["ui/trapper"] = {
            wrap = function(_, f) f() end,
            info = function() end,
            reset = function() end,
        }
        local NetworkMgr = require("ui/network/manager")
        NetworkMgr.runWhenOnline = function(_, f) f() end
        NetworkMgr.afterWifiAction = function() end

        plugin:readWork("111", "Followed", true)

        assert.are.equal(0, WorkWatch.subscribedAdded(plugin.prefs, "111"))
        assert.is_nil(plugin.prefs.work_checks["111"].live)
    end)

    it("makes no request for a work checked today", function()
        write_work("WIP [201].html", "3/?")
        plugin.prefs.work_checks["201"] = { ts = os.time(), chapters = 4 }

        plugin:watchStep()

        assert.are.equal(0, #requests)
        assert.are.equal(0, #scheduled)
        assert.is_nil(plugin.watch_queue)
    end)

    it("marks a 404 as gone instead of asking again", function()
        write_work("WIP [201].html", "3/?")
        plugin.httpRequest = function() return outside("Not found", 404) end

        plugin:watchStep()

        assert.is_true(plugin.prefs.work_checks["201"].gone)
        -- A 404 is an answer: the run finished rather than stopping early.
        assert.are.equal(0, #scheduled)
    end)

    it("stops the run on a refusal instead of retrying", function()
        write_work("WIP [201].html", "3/?")
        write_work("WIP [202].html", "2/?")
        plugin.httpRequest = function(_, url)
            requests[#requests + 1] = url
            return outside("Blocked", 429)
        end

        plugin:watchStep()

        assert.are.equal(1, #requests)
        assert.is_nil(plugin.watch_queue)
        assert.is_nil(plugin.prefs.work_checks["201"])
        assert.are.equal(0, #scheduled)
    end)

    it("asks nothing while offline", function()
        write_work("WIP [201].html", "3/?")
        require("ui/network/manager").isConnected = function() return false end

        plugin:watchStep()

        assert.are.equal(0, #requests)
        assert.is_nil(plugin.watch_queue)
    end)

    it("checks every saved work in progress on a manual run", function()
        write_work("One [201].html", "3/7")
        write_work("Two [202].html", "5/?")
        write_work("Done [203].html", "4/4")

        local NetworkMgr = require("ui/network/manager")
        NetworkMgr.runWhenOnline = function(_, callback) callback() end
        NetworkMgr.afterWifiAction = function() end
        local Trapper = { wrap = function(_, f) f() end, info = function() end, reset = function() end }
        package.loaded["ui/trapper"] = Trapper

        plugin.httpRequest = function(_, url)
            requests[#requests + 1] = url
            return navigate(5), nil, 200
        end

        plugin:checkAllSavedWorks()

        assert.are.equal(2, #requests)
        assert.are.equal(5, plugin.prefs.work_checks["201"].chapters)
        assert.are.equal(5, plugin.prefs.work_checks["202"].chapters)
        assert.is_nil(plugin.prefs.work_checks["203"])
    end)
end)

describe("AO3 updates screen and badges", function()
    local plugin, rows, pushed

    before_each(function()
        clear_downloads()
        plugin = setmetatable({}, { __index = Ao3 })
        plugin.prefs = { work_checks = {}, updates_seen_ts = 0 }
        plugin.savePrefs = function() end
        rows, pushed = nil, nil
        plugin.pushRows = function(_, title, built) rows, pushed = built, title end
        plugin.replaceRows = function(_, title, built) rows, pushed = built, title end
    end)

    after_each(clear_downloads)

    it("marks found chapters as seen when the list opens", function()
        write_work("A [201].html", "3/7")
        plugin.prefs.work_checks["201"] = { ts = 1, chapters = 5 }

        plugin:showUpdates(false)

        assert.are.equal("Updates", pushed)
        assert.is_true(plugin.prefs.updates_seen_ts > 0)
        local item = role(rows, "update_item")
        assert.is_truthy(item)
        assert.are.equal("A", item.text)
        assert.are.equal("2 new · 3/7 → 5/7", item.mandatory)
        assert.is_truthy(role(rows, "updates_check"))
    end)

    it("says so when nothing was found", function()
        write_work("A [201].html", "3/7")
        plugin.prefs.work_checks["201"] = { ts = 1, chapters = 3 }

        plugin:showUpdates(false)

        assert.is_truthy(role(rows, "updates_empty"))
        assert.is_nil(role(rows, "update_item"))
        -- The manual check row, then the empty message.
        assert.are.equal(2, #rows)
    end)

    it("names a saved work AO3 no longer serves", function()
        write_work("Gone [202].html", "2/2")
        plugin.prefs.work_checks["202"] = { ts = 1, gone = true }

        plugin:showUpdates(false)

        local gone = role(rows, "update_gone")
        assert.is_truthy(gone)
        assert.are.equal("Gone", gone.text)
        assert.are.equal("No longer on AO3", gone.mandatory)
    end)

    it("lists a followed work that gained chapters", function()
        plugin.prefs = {
            work_checks = { ["111"] = { ts = 1, chapters = 3, live = 5 } },
            work_subscriptions = { { id = "111", title = "Followed" } },
            updates_seen_ts = 0,
        }

        plugin:showUpdates(false)

        local row = role(rows, "update_subscription")
        assert.is_truthy(row)
        assert.are.equal("Followed", row.text)
        assert.are.equal("2 new · 3 → 5", row.mandatory)
        assert.is_nil(row.hold_action)
    end)

    it("wears the dot for a subscribed work", function()
        plugin.prefs = {
            work_checks = { ["111"] = { ts = 10, chapters = 3, live = 5 } },
            work_subscriptions = { { id = "111", title = "Followed" } },
            updates_seen_ts = 0,
        }

        assert.is_true(plugin:updatesUnread())
    end)

    it("hides followed works when the switch is off", function()
        plugin.prefs = {
            work_checks = { ["111"] = { ts = 10, chapters = 3, live = 5 } },
            work_subscriptions = { { id = "111", title = "Followed" } },
            updates_seen_ts = 0,
            check_subscriptions = false,
        }

        plugin:showUpdates(false)

        assert.is_nil(role(rows, "update_subscription"))
        assert.is_false(plugin:updatesUnread())
    end)

    it("puts the gap on the Downloads row", function()
        write_work("A [201].html", "3/7")
        plugin.prefs.work_checks["201"] = { ts = 1, chapters = 5 }

        plugin:showDownloads(true)

        local row = role(rows, "download")
        assert.are.equal("#201 · 2 new", row.mandatory)
    end)

    it("keeps the plain id when a saved copy is current", function()
        write_work("A [201].html", "5/7")
        plugin.prefs.work_checks["201"] = { ts = 1, chapters = 5 }

        plugin:showDownloads(true)

        assert.are.equal("#201", role(rows, "download").mandatory)
    end)

    it("wears the dot only until the list is opened", function()
        local item = { id = "201", path = write_work("A [201].html", "3/7") }
        plugin.prefs.work_checks["201"] = { ts = 10, chapters = 5 }
        plugin.listDownloads = function() return { item } end

        assert.is_true(plugin:updatesUnread())
        plugin.prefs.updates_seen_ts = 10
        assert.is_false(plugin:updatesUnread())
    end)
end)
