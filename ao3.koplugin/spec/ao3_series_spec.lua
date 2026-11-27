-- KOReader busted spec for series membership on the work details page.
--
-- From a KOReader checkout with this plugin symlinked into plugins/:
--   ln -s ../../plugins/ao3.koplugin/spec/ao3_series_spec.lua spec/unit/
--   ./kodev test --busted=--pattern=ao3_series_spec front
--
-- AO3's series markup is synthetic here but follows the live work meta: one
-- dd.series holding a span.series (and span.position) per series. The tests
-- are offline; both parsers and the built rows are exercised for real.

require("commonrequire")

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")
local WorkPage = dofile("plugins/ao3.koplugin/workpage.lua")
local plugin = setmetatable({}, { __index = Ao3 })

local fixture_dir = "plugins/ao3.koplugin/spec/fixtures/"

local function read_fixture(name)
    local f = assert(io.open(fixture_dir .. name, "rb"))
    local body = f:read("*a")
    f:close()
    return body
end

local function remove_tree(path)
    local mode = lfs.attributes(path, "mode")
    if mode == "directory" then
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then
                remove_tree(path .. "/" .. entry)
            end
        end
        lfs.rmdir(path)
    elseif mode then
        os.remove(path)
    end
end

local tmp_root
local old_get_full_data_dir

setup(function()
    tmp_root = os.tmpname()
    os.remove(tmp_root)
    assert(lfs.mkdir(tmp_root))
    old_get_full_data_dir = DataStorage.getFullDataDir
    DataStorage.getFullDataDir = function() return tmp_root end
    -- Work details looks for a saved copy; the directory is empty, but it has
    -- to exist.
    assert(lfs.mkdir(tmp_root .. "/ao3"))
end)

teardown(function()
    if old_get_full_data_dir then
        DataStorage.getFullDataDir = old_get_full_data_dir
    end
    if tmp_root then
        remove_tree(tmp_root)
    end
end)

-- A work page with only the pieces parseWorkPage needs, plus whatever series
-- markup a test wants in the meta.
local function work_html(meta)
    return [[<!DOCTYPE html><html><body>
        <div class="work">
          <dl class="work meta group">
            ]] .. (meta or "") .. [[
          </dl>
          <div class="preface group">
            <h2 class="title heading">A Work</h2>
            <h3 class="byline heading">
              <a rel="author" href="/users/alice">Alice</a>
            </h3>
          </div>
        </div>
      </body></html>]]
end

local function parse_work(meta)
    local work, err = plugin:parseWorkPage(work_html(meta), "42")
    assert.is_nil(err)
    return work
end

describe("AO3 work page series parser", function()
    it("reads one series with its part number", function()
        local work = parse_work([[
            <dt class="series">Series:</dt>
            <dd class="series">
              <span class="series">
                <span class="position">Part 2 of
                  <a href="/series/12345">Coils AU</a></span>
              </span>
            </dd>
        ]])
        assert.are.equal(1, #work.series)
        assert.are.equal("Coils AU", work.series[1].name)
        assert.are.equal("/series/12345", work.series[1].url)
        assert.are.equal(2, work.series[1].position)
    end)

    it("reads every series in one dd and ignores previous/next work links", function()
        local work = parse_work([[
            <dt class="series">Series:</dt>
            <dd class="series">
              <span class="series">
                <a class="previous" href="/works/100">Previous Work</a>
                <span class="position">Part 3 of
                  <a href="/series/111">First Series</a></span>
                <a class="next" href="/works/103">Next Work</a>
              </span>
              <span class="series">
                <span class="position">Part 1 of
                  <a href="/series/222">Second &amp; Last</a></span>
              </span>
            </dd>
        ]])
        assert.are.equal(2, #work.series)
        assert.are.equal("First Series", work.series[1].name)
        assert.are.equal(3, work.series[1].position)
        assert.are.equal("/series/111", work.series[1].url)
        assert.are.equal("Second & Last", work.series[2].name)
        assert.are.equal(1, work.series[2].position)
        assert.are.equal("/series/222", work.series[2].url)
    end)

    it("falls back to span.series when there is no position span", function()
        local work = parse_work([[
            <dd class="series">
              <span class="series">Part 5 of
                <a href="/series/333">Older Markup</a></span>
            </dd>
        ]])
        assert.are.equal(1, #work.series)
        assert.are.equal("Older Markup", work.series[1].name)
        assert.are.equal(5, work.series[1].position)
    end)

    it("reads the repeated series module only when the meta is absent", function()
        local work = parse_work([[
        ]])
        assert.is_nil(work.series)

        local html = work_html("")
            :gsub("</body>", [[
              <div id="series" class="series module">
                <ul>
                  <li>Part 4 of
                    <a href="/series/444">Module Series</a></li>
                </ul>
              </div>
            </body>]])
        local with_module = assert(plugin:parseWorkPage(html, "42"))
        assert.are.equal(1, #with_module.series)
        assert.are.equal("Module Series", with_module.series[1].name)
        assert.are.equal(4, with_module.series[1].position)
    end)

    it("returns no series key when the dd is absent or malformed", function()
        assert.is_nil(parse_work("").series)
        assert.is_nil(parse_work([[
            <dd class="series">
              <span class="series">
                <a class="previous" href="/works/100">Previous Work</a>
              </span>
            </dd>
        ]]).series)
    end)
end)

local function walk(widget, visit)
    visit(widget)
    for _, child in ipairs(widget) do
        walk(child, visit)
    end
end

local function build(over)
    local o = {
        work = { id = "42", title = "A Work", authors = "Alice" },
        width = 570,
        font_size = 19,
        body_max_height = 300,
        state = { summary = false, tags = false },
        on_read = function() end,
        on_refresh = function() end,
        on_toggle = function() end,
        on_full_text = function() end,
        on_author = function() end,
        on_series = function() end,
        signed_in = false,
        social = {},
        on_action = function() end,
    }
    for key, value in pairs(over or {}) do o[key] = value end
    return WorkPage.build(o)
end

local function rows_with(rows, role)
    local found = {}
    for _, row in ipairs(rows) do
        if row.role == role then found[#found + 1] = row end
    end
    return found
end

describe("AO3 work details series section", function()
    it("draws a quiet Series label and one native row per series", function()
        local series = {
            { name = "Coils AU", url = "/series/12345", position = 2 },
            { name = "Standalone", url = "/series/67890" },
        }
        local rows = build{
            work = {
                id = "42", title = "A Work", authors = "Alice",
                series = series,
            },
        }

        local labels = rows_with(rows, "series_label")
        assert.are.equal(1, #labels)
        local label_text
        walk(labels[1].ao3_static, function(node)
            if not label_text and node.text then label_text = node.text end
        end)
        assert.are.equal("Series", label_text)

        local entries = rows_with(rows, "series")
        assert.are.equal(2, #entries)
        assert.are.equal("Part 2 of Coils AU", entries[1].text)
        assert.are.equal("Part of Standalone", entries[2].text)
        assert.are.equal(series[1], entries[1].entry)
        assert.are.equal(series[2], entries[2].entry)
    end)

    it("calls on_series with the row's own entry", function()
        local tapped
        local rows = build{
            work = {
                id = "42", title = "A Work", authors = "Alice",
                series = { { name = "Coils AU", url = "/series/12345", position = 2 } },
            },
            on_series = function(entry) tapped = entry end,
        }
        rows_with(rows, "series")[1].action()
        assert.are.equal("Coils AU", tapped.name)
        assert.are.equal("/series/12345", tapped.url)
    end)

    it("draws no series section when the work has none", function()
        local rows = build()
        assert.are.equal(0, #rows_with(rows, "series"))
        assert.are.equal(0, #rows_with(rows, "series_label"))
    end)
end)

describe("AO3 work details series wiring", function()
    it("passes on_series into the work page and opens the tapped series", function()
        local captured
        local opened
        local old_pushRows = plugin.pushRows
        local old_ensure = plugin.ensureWorkSocialLoaded
        local old_openSeries = plugin.openSeries
        plugin.menu = { font_size = 19 }
        plugin.ensureWorkSocialLoaded = function() end
        plugin.pushRows = function(_, title, rows) captured = rows end
        plugin.openSeries = function(_, entry) opened = entry end

        local ok, err = pcall(function()
            plugin:showWorkPage({
                id = "42", title = "A Work", authors = "Alice",
                series = { { name = "Coils AU", url = "/series/12345",
                    position = 2 } },
            }, false)

            local entries = rows_with(captured, "series")
            assert.are.equal(1, #entries)
            assert.are.equal("Part 2 of Coils AU", entries[1].text)
            entries[1].action()
            assert.are.equal("Coils AU", opened.name)
            assert.are.equal("/series/12345", opened.url)
        end)
        plugin.pushRows = old_pushRows
        plugin.ensureWorkSocialLoaded = old_ensure
        plugin.openSeries = old_openSeries
        assert.is_true(ok, err)
    end)

    it("opens a series listing at its absolute URL, named by the series", function()
        local opened_url, opened_title
        local old_loadListing = plugin.loadListing
        plugin.loadListing = function(_, url, title)
            opened_url, opened_title = url, title
        end
        local ok, err = pcall(function()
            plugin:openSeries{ name = "Coils AU", url = "/series/12345", position = 2 }
        end)
        plugin.loadListing = old_loadListing
        assert.is_true(ok, err)
        assert.are.equal("https://archiveofourown.org/series/12345", opened_url)
        assert.are.equal("Coils AU", opened_title)
    end)

    it("sends no request for a malformed series entry", function()
        local calls = 0
        local old_loadListing = plugin.loadListing
        plugin.loadListing = function() calls = calls + 1 end
        local ok, err = pcall(function()
            plugin:openSeries(nil)
            plugin:openSeries("Coils AU")
            plugin:openSeries{ name = "No URL" }
            plugin:openSeries{ name = "A work", url = "/works/12345" }
            plugin:openSeries{ name = "Elsewhere", url = "https://example.com/series/1" }
        end)
        plugin.loadListing = old_loadListing
        assert.is_true(ok, err)
        assert.are.equal(0, calls)
    end)
end)

describe("AO3 series listing", function()
    it("reads the usual work blurbs and pagination", function()
        local listing = plugin:parseListing(read_fixture("series.html"))
        assert.is_truthy(listing)
        assert.are.equal(2, #listing.items)
        assert.are.equal("First Coil", listing.items[1].title)
        assert.are.equal("Second Coil", listing.items[2].title)
        assert.are.equal("4", listing.count)
        assert.are.equal("https://archiveofourown.org/series/12345?page=2",
            listing.next_url)
    end)

    it("carries no filter sidebar, so no funnel is offered", function()
        local listing = plugin:parseListing(read_fixture("series.html"))
        -- A series page carries no #work-filters: nil state is what keeps the
        -- funnel off the title bar.
        assert.is_nil(plugin:newFilterState(listing,
            "https://archiveofourown.org/series/12345", "Coils AU"))
    end)
end)
