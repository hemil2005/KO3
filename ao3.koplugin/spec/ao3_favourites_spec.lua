-- KOReader busted spec for pinned (favourite) fandoms.
--
-- The list lives in settings/ao3_prefs.lua, not the AO3 session, so logging
-- out never unpins a fandom. Everything here is offline: the fandom rows are
-- built from plain entry tables and the listing opener is stubbed.

require("commonrequire")

local lfs = require("libs/libkoreader-lfs")
local DataStorage = require("datastorage")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")

local Preferences = dofile("plugins/ao3.koplugin/preferences.lua")
local Uikit = dofile("plugins/ao3.koplugin/uikit.lua")
local HomePage = dofile("plugins/ao3.koplugin/homepage.lua")
local Ao3 = dofile("plugins/ao3.koplugin/main.lua")

local function entry(name, url, count)
    return { name = name, url = url, count = count or "" }
end

local function roles(rows)
    local out = {}
    for _, row in ipairs(rows) do out[#out + 1] = row.role end
    return out
end

local function role_index(rows, role)
    for index, row in ipairs(rows) do
        if row.role == role then return index end
    end
end

describe("AO3 favourite fandom storage", function()
    local dir, path

    before_each(function()
        dir = DataStorage:getFullDataDir() .. "/ao3_favourites_spec"
        if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
        path = dir .. "/ao3_prefs.lua"
        os.remove(path)
        os.remove(path .. ".old")
    end)

    after_each(function()
        os.remove(path)
        os.remove(path .. ".old")
    end)

    it("round-trips pinned fandoms in order", function()
        local favourites = {
            entry("Time Travel", "/tags/Time%20Travel/works", "2,523"),
            entry("Fluff", "/tags/Fluff/works", "418,902"),
        }
        assert.is_true(Preferences.save({ favourites = favourites }, path))
        assert.are.same(favourites, Preferences.load(path).favourites)
    end)

    it("drops malformed entries and coerces strings", function()
        local list = Preferences.favourites({
            "not a table",
            7,
            { url = "/tags/No%20Name/works" },
            { name = "No url" },
            { name = "", url = "/tags/Empty/works" },
            { name = 42, url = 7, count = 9 },
        })
        assert.are.equal(1, #list)
        assert.are.equal("42", list[1].name)
        assert.are.equal("7", list[1].url)
        assert.are.equal("9", list[1].count)
    end)

    it("drops a non-table value on load", function()
        local f = assert(io.open(path, "wb"))
        f:write('return { ["favourites"] = "pinned" }\n')
        f:close()
        assert.are.same({}, Preferences.load(path).favourites)
    end)

    it("normalises a hand-edited file on load", function()
        local f = assert(io.open(path, "wb"))
        f:write('return { ["favourites"] = { "nope", { ["name"] = "No url" },'
            .. ' { ["name"] = "Time Travel",'
            .. ' ["url"] = "/tags/Time%20Travel/works", ["count"] = 5 } } }\n')
        f:close()
        local favourites = Preferences.load(path).favourites
        assert.are.equal(1, #favourites)
        assert.are.equal("Time Travel", favourites[1].name)
        assert.are.equal("5", favourites[1].count)
    end)

    it("dedupes by url and then by name, case-insensitively", function()
        local list = Preferences.favourites({
            entry("Alpha", "/tags/Alpha/works", "1"),
            entry("Another name", "/tags/ALPHA/works", "2"),
            entry("Beta", "/tags/Beta/works", "3"),
            entry("alpha", "/tags/Elsewhere/works", "4"),
        })
        assert.are.equal(2, #list)
        assert.are.equal("Alpha", list[1].name)
        assert.are.equal("Beta", list[2].name)
    end)

    it("keeps at most twelve, newest first, in order", function()
        local input = {}
        for i = 1, 15 do
            input[i] = entry("Fandom " .. i, "/tags/Fandom" .. i .. "/works", tostring(i))
        end
        local list = Preferences.favourites(input)
        assert.are.equal(12, #list)
        assert.are.equal("Fandom 1", list[1].name)
        assert.are.equal("Fandom 12", list[12].name)
    end)

    it("normalises on save too", function()
        assert.is_true(Preferences.save({
            favourites = {
                "nope",
                entry("Kept", "/tags/Kept/works", "8"),
            },
        }, path))
        local favourites = Preferences.load(path).favourites
        assert.are.equal(1, #favourites)
        assert.are.equal("Kept", favourites[1].name)
    end)

    it("keeps favourites when another preference is saved", function()
        -- Toggling a display setting saves the whole table; pinned fandoms must
        -- survive that the same way a dismissed release does.
        local prefs = Preferences.load(path)
        prefs.favourites = { entry("Kept", "/tags/Kept/works", "8") }
        assert.is_true(Preferences.save(prefs, path))
        prefs.tags_expanded = true
        assert.is_true(Preferences.save(prefs, path))
        local reread = Preferences.load(path)
        assert.is_true(reread.tags_expanded)
        assert.are.equal(1, #reread.favourites)
        assert.are.equal("Kept", reread.favourites[1].name)
    end)
end)

describe("AO3 favourite fandom actions", function()
    local plugin, shown, saves, old_show

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
        plugin.prefs = { favourites = {} }
        saves = 0
        plugin.savePrefs = function() saves = saves + 1 end
        shown = {}
        old_show = UIManager.show
        UIManager.show = function(_, widget) shown[#shown + 1] = widget end
    end)

    after_each(function()
        UIManager.show = old_show
        plugin.menu = nil
    end)

    it("matches a pinned fandom by url, whatever its case", function()
        plugin.prefs = {
            favourites = { entry("Time Travel", "/tags/Time%20Travel/works", "2,523") },
        }
        assert.is_true(plugin:isFavouriteFandom("time travel",
            "/tags/time%20travel/works"))
        assert.is_false(plugin:isFavouriteFandom("Fluff", "/tags/Fluff/works"))
    end)

    it("falls back to the name when there is no url", function()
        plugin.prefs = { favourites = { entry("Fluff", "/tags/Fluff/works", "1") } }
        assert.is_true(plugin:isFavouriteFandom("FLUFF"))
        assert.is_false(plugin:isFavouriteFandom("Angst"))
    end)

    it("pins newest first, saves once and says so", function()
        local time_travel = entry("Time Travel", "/tags/Time%20Travel/works", "2,523")
        local fluff = entry("Fluff", "/tags/Fluff/works", "418,902")

        assert.is_true(plugin:toggleFavouriteFandom(fluff))
        assert.is_true(plugin:toggleFavouriteFandom(time_travel))

        assert.are.equal(2, #plugin.prefs.favourites)
        assert.are.equal("Time Travel", plugin.prefs.favourites[1].name)
        assert.are.equal("Fluff", plugin.prefs.favourites[2].name)
        assert.are.equal(2, saves)
        assert.are.equal("Added to favourites", shown[1].text)
        assert.is_true(plugin:isFavouriteFandom("Fluff", fluff.url))
    end)

    it("unpins a fandom that is already pinned", function()
        local fluff = entry("Fluff", "/tags/Fluff/works", "418,902")
        assert.is_true(plugin:toggleFavouriteFandom(fluff))
        shown = {}
        assert.is_false(plugin:toggleFavouriteFandom(fluff))
        assert.are.equal(0, #plugin.prefs.favourites)
        assert.are.equal(2, saves)
        assert.are.equal("Removed from favourites", shown[1].text)
    end)

    it("keeps the list at twelve pins, dropping the oldest", function()
        for i = 1, 13 do
            plugin:toggleFavouriteFandom(entry("Fandom " .. i,
                "/tags/Fandom" .. i .. "/works", tostring(i)))
        end
        assert.are.equal(Preferences.MAX_FAVOURITES, #plugin.prefs.favourites)
        assert.are.equal("Fandom 13", plugin.prefs.favourites[1].name)
        assert.are.equal("Fandom 2", plugin.prefs.favourites[12].name)
    end)

    it("marks a pinned fandom row with a heart and toggles it on hold", function()
        plugin.prefs = {
            favourites = { entry("Fluff", "/tags/Fluff/works", "418,902") },
        }
        local opened, updated
        plugin.loadListing = function(_, url, title)
            opened = { url = url, title = title }
        end
        plugin.menu = {
            page = 3,
            updateItems = function(_, page) updated = page end,
        }

        local row = plugin:fandomRecordRow(entry("Fluff", "/tags/Fluff/works", "418,902"))
        assert.are.equal("heart", row.ao3_icon)
        assert.is_function(row.hold_action)
        assert.are.equal("Fluff", row.text)
        assert.are.equal("418,902", row.mandatory)

        row.action()
        assert.is_truthy(opened.url:find("/tags/Fluff/works", 1, true))
        assert.are.equal("Fluff", opened.title)

        -- First hold unpins: the mark clears and the same page repaints.
        row.hold_action()
        assert.is_nil(row.ao3_icon)
        assert.is_false(plugin:isFavouriteFandom("Fluff", "/tags/Fluff/works"))
        assert.are.equal(3, updated)
        assert.are.equal("Removed from favourites", shown[1].text)

        -- Second hold pins it again without leaving the letter.
        row.hold_action()
        assert.are.equal("heart", row.ao3_icon)
        assert.are.equal("Added to favourites", shown[2].text)
        assert.are.equal(3, updated)
    end)

    it("leaves an unpinned fandom row without a heart", function()
        local row = plugin:fandomRecordRow(entry("Fluff", "/tags/Fluff/works", "1"))
        assert.is_nil(row.ao3_icon)
        assert.is_function(row.hold_action)
        row.hold_action()
        assert.are.equal("heart", row.ao3_icon)
    end)
end)

describe("AO3 favourite fandom home shelf", function()
    local plugin

    local function plugin_with(favourites)
        plugin = setmetatable({}, { __index = Ao3 })
        plugin.prefs = { favourites = favourites or {} }
        plugin.savePrefs = function() end
        plugin.loadListing = function() end
        return plugin
    end

    local function build(favourites)
        plugin_with(favourites)
        return plugin:homeRows()
    end

    it("emits no Favourites section when nothing is pinned", function()
        local rows = build({})
        assert.is_nil(role_index(rows, "favourites_label"))
        assert.is_nil(role_index(rows, "favourites_row_1"))
        assert.is_nil(role_index(rows, "favourites_all"))
        -- Search is still followed directly by Browse.
        assert.are.equal("browse_label", rows[3].role)
    end)

    it("puts the shelf between Search and Browse", function()
        local rows = build({
            entry("Time Travel", "/tags/Time%20Travel/works", "2,523"),
        })
        local search = role_index(rows, "search")
        local label = role_index(rows, "favourites_label")
        local browse = role_index(rows, "browse_label")
        assert.is_truthy(search and label and browse)
        assert.is_true(search < label)
        assert.is_true(label < browse)
        assert.is_true(rows[label].keep_with_next)
    end)

    it("shows up to four two-up tiles with name, count and a heart", function()
        local rows = build({
            entry("Time Travel", "/tags/Time%20Travel/works", "2,523"),
            entry("Fluff", "/tags/Fluff/works", "418,902"),
            entry("Angst", "/tags/Angst/works", ""),
        })
        local first = rows[role_index(rows, "favourites_row_1")]
        local second = rows[role_index(rows, "favourites_row_2")]
        assert.are.equal(2, #first.tiles)
        assert.are.equal(1, #second.tiles)
        assert.is_nil(role_index(rows, "favourites_all"))

        local tile = first.tiles[1]
        assert.are.equal("Time Travel", tile.text)
        assert.are.equal("2,523 works", tile.hint)
        assert.are.equal("heart", tile.icon)
        assert.are.equal("favourite", tile.role)
        assert.is_function(tile.action)
        assert.is_function(tile.hold_action)
        assert.are.equal("Time Travel", tile.favourite.name)

        -- A fandom with no count says what it is rather than showing " works".
        assert.are.equal("Fandom", second.tiles[1].hint)
    end)

    it("caps the shelf at four and adds All favourites beyond that", function()
        local favourites = {}
        for i = 1, 6 do
            favourites[i] = entry("Fandom " .. i,
                "/tags/Fandom" .. i .. "/works", tostring(i))
        end
        local rows = build(favourites)
        assert.are.equal(2, #rows[role_index(rows, "favourites_row_1")].tiles)
        assert.are.equal(2, #rows[role_index(rows, "favourites_row_2")].tiles)
        local all = rows[role_index(rows, "favourites_all")]
        assert.are.equal("All favourites", all.tiles[1].text)
        assert.are.equal("6 pinned", all.tiles[1].hint)
        assert.are.equal("favourites_all", all.tiles[1].role)
        assert.is_function(all.tiles[1].action)
    end)

    it("opens the fandom listing from a tile", function()
        local opened
        plugin_with({
            entry("Time Travel", "/tags/Time%20Travel/works", "2,523"),
        })
        plugin.loadListing = function(_, url, title)
            opened = { url = url, title = title }
        end
        local rows = plugin:homeRows()
        rows[role_index(rows, "favourites_row_1")].tiles[1].action()
        assert.is_truthy(opened.url:find("/tags/Time%20Travel/works", 1, true))
        assert.are.equal("Time Travel", opened.title)
    end)

    it("unpins from a tile hold and redraws Home in place", function()
        local toggled, replaced
        plugin_with({
            entry("Time Travel", "/tags/Time%20Travel/works", "2,523"),
        })
        plugin.toggleFavouriteFandom = function(_, entry_value)
            toggled = entry_value
            return false
        end
        plugin.replaceRows = function(_, title, rows)
            replaced = { title = title, rows = rows }
        end
        local rows = plugin:homeRows()
        rows[role_index(rows, "favourites_row_1")].tiles[1].hold_action()
        assert.are.equal("Time Travel", toggled.name)
        assert.are.equal("", replaced.title)
        assert.is_truthy(replaced.rows and #replaced.rows > 0)
    end)

    it("opens the All favourites list from its wide tile", function()
        local asked
        plugin_with({
            entry("A", "/tags/A/works", "1"),
            entry("B", "/tags/B/works", "2"),
            entry("C", "/tags/C/works", "3"),
            entry("D", "/tags/D/works", "4"),
            entry("E", "/tags/E/works", "5"),
        })
        plugin.showFavourites = function() asked = true end
        local rows = plugin:homeRows()
        rows[role_index(rows, "favourites_all")].tiles[1].action()
        assert.is_true(asked)
    end)
end)

describe("AO3 tap areas with a hold action", function()
    it("registers both tap and hold when a hold callback is given", function()
        local tapped, held = 0, 0
        local area = Uikit.tapArea(TextWidget:new{ text = "tile" }, 100, 50,
            function() tapped = tapped + 1 end,
            function() held = held + 1 end)

        assert.are.equal("tap", area.ges_events.Tap[1].ges)
        assert.are.equal("hold", area.ges_events.Hold[1].ges)
        assert.are.same(area.dimen, area.ges_events.Hold[1].range)
        assert.is_true(area.onTap())
        assert.is_true(area.onHold())
        assert.are.equal(1, tapped)
        assert.are.equal(1, held)
    end)

    it("keeps a tap-only area free of the hold gesture", function()
        local tapped = 0
        local area = Uikit.tapArea(TextWidget:new{ text = "bar" }, 100, 50,
            function() tapped = tapped + 1 end)

        assert.are.equal("tap", area.ges_events.Tap[1].ges)
        assert.is_nil(area.ges_events.Hold)
        assert.is_nil(area.onHold)
        assert.is_true(area.onTap())
        assert.are.equal(1, tapped)
    end)

    it("carries a tile's hold_action into its tap area", function()
        local held = 0
        local card = HomePage.card({
            text = "Time Travel",
            hint = "2,523 works",
            icon = "heart",
            action = function() end,
            hold_action = function() held = held + 1 end,
        }, 280, 81, { width = 280, font_size = 20 })

        assert.is_function(card.onHold)
        assert.is_true(card.onHold())
        assert.are.equal(1, held)
    end)
end)
