-- KOReader busted spec for the local Downloads filter.
--
-- No AO3 page is involved: this screen lists files already on disk, so its
-- filter is a pure, case-insensitive substring match over that list and its
-- redraw makes no request.

require("commonrequire")

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local UIManager = require("ui/uimanager")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")

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

local function write_sample(name)
    local path = download_dir() .. "/" .. name
    local f = assert(io.open(path, "wb"))
    f:write("<html></html>")
    f:close()
    return path
end

describe("AO3 Downloads filter", function()
    local plugin

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
        plugin.downloads_query = nil
        clear_downloads()
        write_sample("The Winter Sea [101].html")
        write_sample("A Devil in the Details [202].html")
    end)

    after_each(function()
        clear_downloads()
        plugin.menu = nil
    end)

    local function open_downloads(query)
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        plugin:showDownloads(false, query)
        UIManager.show = old_show
        return menu
    end

    local function titled(rows)
        local titles = {}
        for _, row in ipairs(rows) do
            if row.role == "download" then titles[#titles + 1] = row.text end
        end
        return titles
    end

    local function row_with(rows, role)
        for _, row in ipairs(rows) do
            if row.role == role then return row end
        end
    end

    it("matches titles case-insensitively and the work number", function()
        local items = {
            { id = "101", title = "The Winter Sea" },
            { id = "202", title = "A Devil in the Details" },
        }
        assert.are.equal(1, #plugin:filterDownloads(items, "winter"))
        assert.are.equal(1, #plugin:filterDownloads(items, "WINTER"))
        assert.are.equal("The Winter Sea",
            plugin:filterDownloads(items, "winter")[1].title)
        assert.are.equal(1, #plugin:filterDownloads(items, "#202"))
        assert.are.equal(1, #plugin:filterDownloads(items, "202"))
        assert.are.equal(2, #plugin:filterDownloads(items, ""))
        assert.are.equal(2, #plugin:filterDownloads(items, nil))
        assert.are.equal(0, #plugin:filterDownloads(items, "no such work"))
    end)

    it("narrows the screen as a query arrives and restores it when cleared", function()
        local menu = open_downloads()
        assert.are.equal(2, #titled(menu.item_table))
        assert.are.equal("download_filter", menu.item_table[1].role)

        -- What each keystroke does: a new query redraws the same screen.
        plugin:showDownloads(true, "winter")
        assert.are.equal(1, #titled(menu.item_table))
        assert.are.equal("The Winter Sea", titled(menu.item_table)[1])
        assert.are.equal("Filter: winter", menu.item_table[1].text)
        assert.are.equal("1 of 2", menu.item_table[1].mandatory)

        -- Clearing restores every saved work.
        plugin:showDownloads(true, "")
        assert.are.equal(2, #titled(menu.item_table))
        assert.are.equal("Filter saved works…", menu.item_table[1].text)
        assert.is_nil(menu.item_table[1].mandatory)
    end)

    it("keeps the storage row and does not request anything", function()
        local requests = 0
        plugin.httpRequest = function() requests = requests + 1 return nil, "offline" end
        plugin.fetchPage = function() requests = requests + 1 end

        local menu = open_downloads("devil")
        assert.are.equal(0, requests)

        local storage = row_with(menu.item_table, "download_storage")
        assert.is_truthy(storage)
        assert.are.equal("Storage folder", storage.text)
        assert.are.equal("Show path", storage.mandatory)
        assert.are.equal("A Devil in the Details", titled(menu.item_table)[1])
    end)

    it("says so when the query matches nothing, without losing the folder row", function()
        local menu = open_downloads("zzz")
        assert.are.equal("Filter: zzz", menu.item_table[1].text)
        assert.are.equal("No saved works match.", row_with(menu.item_table,
            "download_empty").text)
        assert.is_truthy(row_with(menu.item_table, "download_storage"))
    end)

    it("leaves the empty state and its rows exactly as before", function()
        plugin.listDownloads = function() return {} end
        local menu = open_downloads()
        assert.are.equal("No saved works yet.", menu.item_table[1].text)
        assert.are.equal("Open a work and tap Read.", menu.item_table[2].text)
        assert.are.equal("Storage folder", menu.item_table[3].text)
        -- Nothing to filter, so no filter row takes the first slot.
        assert.is_nil(row_with(menu.item_table, "download_filter"))
    end)
end)
