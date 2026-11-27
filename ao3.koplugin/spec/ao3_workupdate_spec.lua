-- Offline tests for the saved-work update check.
--
-- Everything here either reads a file that is already on disk or hands the
-- plugin a stubbed fetchPage. No test reaches AO3, and opening Work details
-- must make no request at all: the live page it is handed already carries the
-- current chapter count.

require("commonrequire")

local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")

local Account = dofile("plugins/ao3.koplugin/account.lua")
local Ao3 = dofile("plugins/ao3.koplugin/main.lua")
local WorkPage = dofile("plugins/ao3.koplugin/workpage.lua")
local WorkUpdate = dofile("plugins/ao3.koplugin/workupdate.lua")

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
local function work_html(chapters, body)
    return '<html><body><div id="preface"><dl class="work meta group">'
        .. '<dt class="stats">Stats:</dt><dd class="stats"><dl class="stats">'
        .. '<dt class="chapters">Chapters:</dt><dd class="chapters">'
        .. chapters .. '</dd>'
        .. '<dt class="words">Words:</dt><dd class="words">1,234</dd>'
        .. '</dl></dd></dl></div>'
        .. (body or "") .. '</body></html>'
end

local function write_work(name, chapters, body)
    local dir = download_dir()
    if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
    local path = dir .. "/" .. name
    local f = assert(io.open(path, "wb"))
    f:write(work_html(chapters, body))
    f:close()
    return path
end

local function role(rows, name)
    for i, row in ipairs(rows) do
        if row.role == name then return row, i end
    end
end

local function button(dialog, label)
    for _, row in ipairs(dialog.buttons) do
        if row[1].text == label then return row[1] end
    end
end

local function button_index(dialog, label)
    for i, row in ipairs(dialog.buttons) do
        if row[1].text == label then return i end
    end
end

describe("WorkUpdate chapter counts", function()
    it("reads a current/total stat", function()
        local current, total = WorkUpdate.parseChapters("3/7")
        assert.are.equal(3, current)
        assert.are.equal(7, total)
    end)

    it("trims the whitespace AO3's markup leaves around the stat", function()
        local current, total = WorkUpdate.parseChapters("  3/7\n")
        assert.are.equal(3, current)
        assert.are.equal(7, total)
    end)

    it("reads an unknown total as a current count with no end", function()
        local current, total = WorkUpdate.parseChapters("3/?")
        assert.are.equal(3, current)
        assert.is_nil(total)
    end)

    it("treats a bare number as both counts", function()
        local current, total = WorkUpdate.parseChapters("12")
        assert.are.equal(12, current)
        assert.are.equal(12, total)
    end)

    it("refuses text it cannot read", function()
        assert.is_nil(WorkUpdate.parseChapters("n/a"))
        assert.is_nil(WorkUpdate.parseChapters(""))
        assert.is_nil(WorkUpdate.parseChapters(nil))
        assert.is_nil(WorkUpdate.parseChapters("3/7/9"))
    end)
end)

describe("WorkUpdate cached copy", function()
    before_each(clear_downloads)
    after_each(clear_downloads)

    it("reads the chapter stat from the saved preface", function()
        local path = write_work("The Winter Sea [101].html", "3/7")
        local current, total = WorkUpdate.cachedChapters(path)
        assert.are.equal(3, current)
        assert.are.equal(7, total)
    end)

    it("keeps an unknown total unknown", function()
        local path = write_work("Open Ended [102].html", "3/?")
        local current, total = WorkUpdate.cachedChapters(path)
        assert.are.equal(3, current)
        assert.is_nil(total)
    end)

    it("says nothing when the file is gone or has no stat", function()
        assert.is_nil(WorkUpdate.cachedChapters(nil))
        assert.is_nil(WorkUpdate.cachedChapters(download_dir() .. "/missing.html"))
        local path = write_work("Bare [103].html", "not a count")
        assert.is_nil(WorkUpdate.cachedChapters(path))
    end)

    it("reads only the preface, not the chapter bodies", function()
        -- A real save can run to megabytes after the preface. The stat that
        -- matters is the preface's; a later one must not win, and must not be
        -- reached at all.
        local path = write_work("Long [104].html", "3/7",
            string.rep("x", 200 * 1024)
            .. '<dl class="stats"><dd class="chapters">99/99</dd></dl>')
        local current, total = WorkUpdate.cachedChapters(path)
        assert.are.equal(3, current)
        assert.are.equal(7, total)
    end)

    it("does not scan past the bounded preface read", function()
        local path = download_dir() .. "/Deep [105].html"
        local f = assert(io.open(path, "wb"))
        f:write("<html><body>" .. string.rep("x", 200 * 1024)
            .. '<dd class="chapters">9/9</dd></body></html>')
        f:close()
        assert.is_nil(WorkUpdate.cachedChapters(path))
    end)
end)

describe("WorkUpdate comparison", function()
    it("counts the chapters the saved copy is missing", function()
        local result = WorkUpdate.compare({ current = 3, total = 7 },
            { current = 5, total = 7 })
        assert.are.equal(3, result.old_current)
        assert.are.equal(5, result.new_current)
        assert.are.equal(2, result.added)
        assert.is_false(result.up_to_date)
        assert.is_false(result.complete)
        assert.is_false(result.unknown)
        assert.is_true(WorkUpdate.isNew(result))
    end)

    it("is up to date when nothing was added", function()
        local result = WorkUpdate.compare("3/7", "3/7")
        assert.are.equal(0, result.added)
        assert.is_true(result.up_to_date)
        assert.is_false(WorkUpdate.isNew(result))
    end)

    it("reports a work that has just been completed", function()
        local result = WorkUpdate.compare("5/7", "7/7")
        assert.are.equal(2, result.added)
        assert.is_true(result.complete)
        assert.is_true(WorkUpdate.isNew(result))
    end)

    it("treats a newly known total at the current count as complete", function()
        -- "5/?" -> "5/5" adds no chapters but the work is finished.
        local result = WorkUpdate.compare("5/?", "5/5")
        assert.are.equal(0, result.added)
        assert.is_true(result.complete)
        assert.is_true(WorkUpdate.isNew(result))
    end)

    it("does not call an already complete work new", function()
        local result = WorkUpdate.compare("7/7", "7/7")
        assert.is_true(result.complete)
        assert.is_false(WorkUpdate.isNew(result))
        assert.are.equal("Up to date · 7/7", WorkUpdate.message(result))
    end)

    it("compares currents when the saved total is unknown", function()
        local result = WorkUpdate.compare("3/?", "5/?")
        assert.is_nil(result.old_total)
        assert.is_nil(result.new_total)
        assert.are.equal(2, result.added)
        assert.is_false(result.complete)
        assert.is_false(result.unknown)
    end)

    it("compares currents when the live total is unknown", function()
        local result = WorkUpdate.compare("5/7", "9/?")
        assert.are.equal(4, result.added)
        assert.is_nil(result.new_total)
        assert.is_false(result.complete)
    end)

    it("never goes backwards when the count shrinks", function()
        local result = WorkUpdate.compare("7/7", "3/7")
        assert.are.equal(0, result.added)
        assert.is_true(result.up_to_date)
        assert.is_false(WorkUpdate.isNew(result))
    end)

    it("marks an unreadable side as unknown instead of new", function()
        local result = WorkUpdate.compare(nil, "5/7")
        assert.is_true(result.unknown)
        assert.are.equal(0, result.added)
        assert.is_false(WorkUpdate.isNew(result))
    end)

    it("says so when the count is unavailable", function()
        assert.are.equal("Chapter count unavailable",
            WorkUpdate.message(WorkUpdate.compare(nil, "5/7")))
        assert.are.equal("Chapter count unavailable",
            WorkUpdate.message(WorkUpdate.compare("3/7", nil)))
    end)
end)

describe("WorkUpdate message", function()
    it("names the new chapters and the move", function()
        assert.are.equal("2 new chapters · 3/7 → 5/7",
            WorkUpdate.message(WorkUpdate.compare("3/7", "5/7")))
    end)

    it("keeps unknown totals as ? in the sentence", function()
        assert.are.equal("2 new chapters · 3/? → 5/?",
            WorkUpdate.message(WorkUpdate.compare("3/?", "5/?")))
    end)

    it("says a saved copy is up to date", function()
        assert.are.equal("Up to date · 3/7",
            WorkUpdate.message(WorkUpdate.compare("3/7", "3/7")))
    end)

    it("says a work has just been completed", function()
        assert.are.equal("The work is now complete · 7/7",
            WorkUpdate.message(WorkUpdate.compare("5/7", "7/7")))
    end)
end)

describe("WorkUpdate isWip", function()
    it("knows a work that can still grow", function()
        assert.is_true(WorkUpdate.isWip("3/7"))
        assert.is_true(WorkUpdate.isWip("3/?"))
        assert.is_true(WorkUpdate.isWip("2/2"))
    end)

    it("leaves a one-shot alone", function()
        assert.is_false(WorkUpdate.isWip("1/1"))
        assert.is_false(WorkUpdate.isWip("1"))
        assert.is_false(WorkUpdate.isWip(""))
        assert.is_false(WorkUpdate.isWip(nil))
    end)
end)

describe("AO3 saved-work update check", function()
    local plugin
    local shown, closed, fetched, read
    local old_show, old_close

    local function actions(item)
        local dialog
        local old = UIManager.show
        UIManager.show = function(_, widget) dialog = widget end
        plugin:downloadItemActions(item)
        UIManager.show = old
        return dialog
    end

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
        clear_downloads()
        shown, closed, fetched, read = {}, 0, {}, {}
        old_show, old_close = UIManager.show, UIManager.close
        UIManager.show = function(_, widget) shown[#shown + 1] = widget end
        UIManager.close = function() closed = closed + 1 end
        plugin.fetchPage = function(_, url, parse, label, on_success)
            fetched[#fetched + 1] = {
                url = url, parse = parse, label = label,
                on_success = on_success,
            }
        end
        plugin.parseWorkPage = function(_, html, id)
            return { id = id, chapters = html }
        end
        plugin.readWork = function(_, id, title, refresh)
            read[#read + 1] = { id = id, title = title, refresh = refresh }
        end
    end)

    after_each(function()
        clear_downloads()
        UIManager.show, UIManager.close = old_show, old_close
    end)

    it("offers the check for a saved work in progress, above Refresh", function()
        local path = write_work("The Winter Sea [101].html", "3/7")
        local dialog = actions({ id = "101", title = "The Winter Sea", path = path })

        local check = button(dialog, "Check for updates")
        assert.is_truthy(check)
        assert.is_true(button_index(dialog, "Check for updates")
            < button_index(dialog, "Refresh from AO3"))
        -- Opening the action sheet is local only.
        assert.are.equal(0, #fetched)
        assert.are.equal(0, closed)
    end)

    it("leaves a one-shot without the check", function()
        local path = write_work("One Shot [102].html", "1/1")
        local dialog = actions({ id = "102", title = "One Shot", path = path })

        assert.is_nil(button(dialog, "Check for updates"))
        assert.is_truthy(button(dialog, "Refresh from AO3"))
    end)

    it("leaves an unreadable save without the check", function()
        local dialog = actions({ id = "103", title = "Gone", path = "nope.html" })
        assert.is_nil(button(dialog, "Check for updates"))
    end)

    it("makes exactly one page request, to the work's own URL", function()
        local path = write_work("The Winter Sea [101].html", "3/7")
        local dialog = actions({ id = "101", title = "The Winter Sea", path = path })

        button(dialog, "Check for updates").callback()

        assert.are.equal(1, #fetched)
        assert.are.equal(Account.workUrl("101"), fetched[1].url)
        assert.are.equal("Checking for updates…", fetched[1].label)
        assert.are.equal(1, closed)
        -- The parse is the work page parser, so the caller gets a work table.
        local work = fetched[1].parse("<html>")
        assert.are.equal("101", work.id)
    end)

    it("says up to date and downloads nothing when the save is current", function()
        local path = write_work("The Winter Sea [101].html", "3/7")
        local dialog = actions({ id = "101", title = "The Winter Sea", path = path })

        button(dialog, "Check for updates").callback()
        fetched[1].on_success({ id = "101", chapters = "3/7" })

        assert.are.equal(1, #shown)
        assert.are.equal(InfoMessage, getmetatable(shown[1]).__index)
        assert.are.equal("Up to date · 3/7", shown[1].text)
        assert.are.equal(0, #read)
    end)

    it("asks before fetching new chapters", function()
        local path = write_work("The Winter Sea [101].html", "3/7")
        local dialog = actions({ id = "101", title = "The Winter Sea", path = path })

        button(dialog, "Check for updates").callback()
        fetched[1].on_success({ id = "101", chapters = "5/7" })

        assert.are.equal(1, #shown)
        local confirm = shown[1]
        assert.are.equal("Get new chapters", confirm.ok_text)
        assert.are.equal("Not now", confirm.cancel_text)
        assert.is_truthy(confirm.text:find("2 new chapters · 3/7 → 5/7", 1, true))
        -- Offering is not downloading.
        assert.are.equal(0, #read)

        confirm.ok_callback()
        assert.are.equal(1, #read)
        assert.are.equal("101", read[1].id)
        assert.are.equal("The Winter Sea", read[1].title)
        assert.is_true(read[1].refresh)
    end)

    it("offers a newly completed work even without a new chapter", function()
        local path = write_work("Open Ended [106].html", "5/?")
        local dialog = actions({ id = "106", title = "Open Ended", path = path })

        button(dialog, "Check for updates").callback()
        fetched[1].on_success({ id = "106", chapters = "5/5" })

        local confirm = shown[1]
        assert.are.equal("Get new chapters", confirm.ok_text)
        assert.is_truthy(confirm.text:find("The work is now complete · 5/5", 1, true))
    end)

    it("never offers a download when the live count is unreadable", function()
        local path = write_work("The Winter Sea [101].html", "3/7")
        local dialog = actions({ id = "101", title = "The Winter Sea", path = path })

        button(dialog, "Check for updates").callback()
        fetched[1].on_success({ id = "101", chapters = "" })

        assert.are.equal(1, #shown)
        assert.are.equal(InfoMessage, getmetatable(shown[1]).__index)
        assert.are.equal("Chapter count unavailable", shown[1].text)
        assert.are.equal(0, #read)
    end)
end)

describe("AO3 work details update row", function()
    local plugin, rows, requests

    local function work(chapters)
        return {
            id = "101",
            title = "The Winter Sea",
            authors = "harborlight",
            chapters = chapters,
            summary = "A summary.",
        }
    end

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
        clear_downloads()
        rows, requests = nil, 0
        plugin.pushRows = function(_, _, built) rows = built end
        plugin.fetchPage = function() requests = requests + 1 end
        plugin.httpRequest = function() requests = requests + 1 end
    end)

    after_each(clear_downloads)

    it("shows the gap without asking AO3 anything", function()
        write_work("The Winter Sea [101].html", "3/7")

        plugin:showWorkPage(work("5/7"), false)

        assert.are.equal(0, requests)
        local update = role(rows, "update")
        assert.is_truthy(update)
        assert.are.equal("2 new chapters", update.text)
        assert.are.equal("3/7 → 5/7", update.mandatory)
        -- It sits among the facts, before the folded text.
        local _, update_at = role(rows, "update")
        local _, summary_at = role(rows, "summary")
        assert.is_true(update_at < summary_at)
    end)

    it("is silent for a save that is already current", function()
        write_work("The Winter Sea [101].html", "5/7")

        plugin:showWorkPage(work("5/7"), false)

        assert.are.equal(0, requests)
        assert.is_nil(role(rows, "update"))
    end)

    it("is silent when nothing is saved or the count is unreadable", function()
        plugin:showWorkPage(work("5/7"), false)
        assert.is_nil(role(rows, "update"))

        local path = write_work("Bare [101].html", "n/a")
        assert.is_truthy(path)
        plugin:showWorkPage(work("5/7"), false)
        assert.is_nil(role(rows, "update"))
    end)

    it("names a newly completed work", function()
        write_work("The Winter Sea [101].html", "5/?")
        plugin:showWorkPage(work("5/5"), false)

        local update = role(rows, "update")
        assert.is_truthy(update)
        assert.are.equal("Work complete", update.text)
        assert.are.equal("5/? → 5/5", update.mandatory)
    end)

    it("refreshes from the row through the normal validated path", function()
        write_work("The Winter Sea [101].html", "3/7")
        local refreshed = 0
        plugin.readWork = function(_, id, title, refresh)
            assert.are.equal("101", id)
            assert.are.equal("The Winter Sea", title)
            assert.is_true(refresh)
            refreshed = refreshed + 1
        end

        plugin:showWorkPage(work("5/7"), false)
        role(rows, "update").action()

        assert.are.equal(1, refreshed)
        assert.are.equal(0, requests)
    end)
end)

describe("WorkPage update row", function()
    local function build(update)
        return WorkPage.build{
            work = {
                id = "101",
                title = "The Winter Sea",
                authors = "harborlight",
                chapters = "5/7",
                summary = "A summary.",
                tags = "One, Two",
            },
            width = 570,
            font_size = 19,
            body_max_height = 300,
            state = { summary = false, tags = false },
            on_read = function() end,
            on_refresh = function() end,
            on_toggle = function() end,
            on_full_text = function() end,
            on_author = function() end,
            social = {},
            signed_in = true,
            on_action = function() end,
            update = update,
        }
    end

    it("emits the update row only when the caller found something new", function()
        local plain = build(nil)
        assert.is_nil(role(plain, "update"))

        local rows = build(WorkUpdate.compare("3/7", "5/7"))
        local update = role(rows, "update")
        assert.is_truthy(update)
        assert.are.equal("2 new chapters", update.text)
        assert.are.equal("3/7 → 5/7", update.mandatory)
    end)

    it("keeps the row tappable through Refresh", function()
        local refreshed = 0
        local rows = WorkPage.build{
            work = { id = "101", title = "The Winter Sea" },
            width = 570,
            font_size = 19,
            body_max_height = 300,
            state = { summary = false, tags = false },
            on_read = function() end,
            on_refresh = function() refreshed = refreshed + 1 end,
            on_toggle = function() end,
            on_full_text = function() end,
            on_author = function() end,
            social = {},
            signed_in = true,
            on_action = function() end,
            update = WorkUpdate.compare("3/7", "5/7"),
        }
        role(rows, "update").action()
        assert.are.equal(1, refreshed)
    end)
end)
