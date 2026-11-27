-- KOReader busted spec for listing sort.
--
-- Offline: the sort controls are parsed from the pinned filter fixtures
-- (`filters.html` carries work_search Date Updated/Kudos/Hits, bookmark_filters
-- carries bookmark_search Date Bookmarked/Word Count), and the search form's
-- fixed list is pinned against AO3's work_search_form.rb values in
-- searchfilters.lua. Sorting is pending state until Apply, exactly like a tick.

require("commonrequire")

local UIManager = require("ui/uimanager")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")
local AuthorPage = dofile("plugins/ao3.koplugin/authorpage.lua")
local SearchFilters = dofile("plugins/ao3.koplugin/searchfilters.lua")

local fixture_dir = "plugins/ao3.koplugin/spec/fixtures/"
local WORK_URL = "https://archiveofourown.org/tags/Time%20Travel/works"
local SEARCH = "https://archiveofourown.org/works/search"
    .. "?work_search%5Bquery%5D=echoes%20in%20eternity"

local function read_fixture(name)
    local f = assert(io.open(fixture_dir .. name, "rb"))
    local body = f:read("*a")
    f:close()
    return body
end

describe("AO3 listing sort", function()
    local plugin

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
    end)

    after_each(function()
        plugin.menu = nil
    end)

    local function work_listing(html)
        return assert(plugin:parseListing(html or read_fixture("filters.html")))
    end

    local function work_state(url)
        return assert(plugin:newFilterState(work_listing(),
            url or WORK_URL, "Time Travel"))
    end

    local function bookmark_state(url)
        return assert(plugin:newFilterState(
            assert(plugin:parseListing(read_fixture("bookmark_filters.html"))),
            url or "https://archiveofourown.org/users/demo_reader/bookmarks",
            "Bookmarks"))
    end

    local function search_state(url)
        return assert(plugin:newSearchFilterState(url or SEARCH, "Search"))
    end

    local function open_listing(state)
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        local listing = state.scope == "bookmark"
            and assert(plugin:parseListing(read_fixture("bookmark_filters.html")))
            or work_listing()
        if state.scope == "search" then
            listing = assert(plugin:parseListing(read_fixture("search.html")))
        end
        plugin:showListing(listing, state.title or "Listing", false, state)
        UIManager.show = old_show
        return menu
    end

    local function row_with(rows, role, extra)
        for _, row in ipairs(rows) do
            local match = (role == nil or row.role == role)
            if match and extra then
                for key, value in pairs(extra) do
                    if row[key] ~= value then match = false break end
                end
            end
            if match then return row end
        end
    end

    it("parses the work sidebar's sort select without guessing", function()
        local sort = work_listing().sort
        assert.is_truthy(sort)
        assert.are.equal("work_search", sort.param)
        assert.are.equal(3, #sort.columns)
        assert.are.equal("revised_at", sort.columns[1].value)
        assert.are.equal("Date Updated", sort.columns[1].label)
        assert.are.equal("kudos_count", sort.columns[2].value)
        assert.are.equal("Kudos", sort.columns[2].label)
        assert.are.equal("hits", sort.columns[3].value)
        assert.are.equal("Hits", sort.columns[3].label)
        -- Tag sidebars have no direction control.
        assert.is_nil(sort.directions)
        assert.are.equal("revised_at", sort.column)
        assert.are.equal("revised_at", sort.default_column)
    end)

    it("parses the bookmark sidebar's sort and no direction field", function()
        local listing = assert(plugin:parseListing(
            read_fixture("bookmark_filters.html")))
        assert.are.equal("bookmark_search", listing.sort.param)
        assert.are.equal(2, #listing.sort.columns)
        assert.are.equal("created_at", listing.sort.columns[1].value)
        assert.are.equal("Date Bookmarked", listing.sort.columns[1].label)
        assert.are.equal("word_count", listing.sort.columns[2].value)
        assert.are.equal("Word Count", listing.sort.columns[2].label)
        assert.is_nil(listing.sort.directions)
        assert.are.equal("created_at", listing.sort.column)

        -- The author bookmark parser attaches the same sort table.
        local data = AuthorPage.parseBookmarks(
            read_fixture("bookmark_filters.html"), function(root)
                return plugin:parseBookmarkFacets(root)
            end)
        assert.are.equal("bookmark_search", data.sort.param)
        assert.are.equal("created_at", data.sort.column)
    end)

    it("parses a direction select when the page carries one", function()
        local root = require("htmlparser").parse([[
<html><body><form id="work-filters">
  <select name="work_search[sort_column]">
    <option value="revised_at" selected>Date Updated</option>
    <option value="hits">Hits</option>
  </select>
  <select name="work_search[sort_direction]">
    <option value="desc" selected>Descending</option>
    <option value="asc">Ascending</option>
  </select>
</form></body></html>]], 5000)
        local sort = assert(plugin:parseSortOptions(root, "work_search"))
        assert.are.equal("revised_at", sort.column)
        assert.are.equal("desc", sort.direction)
        assert.are.equal(2, #sort.directions)
        assert.are.equal("asc", sort.directions[2].value)
        assert.are.equal("Ascending", sort.directions[2].label)
    end)

    it("pins the search form's full fixed sort list", function()
        local sort = SearchFilters.sorts()
        assert.are.equal("work_search", sort.param)
        local expected = {
            { "_score", "Best Match" },
            { "authors_to_sort_on", "Creator" },
            { "title_to_sort_on", "Title" },
            { "created_at", "Date Posted" },
            { "revised_at", "Date Updated" },
            { "word_count", "Word Count" },
            { "hits", "Hits" },
            { "kudos_count", "Kudos" },
            { "comments_count", "Comments" },
            { "bookmarks_count", "Bookmarks" },
        }
        assert.are.equal(#expected, #sort.columns)
        for index, entry in ipairs(expected) do
            assert.are.equal(entry[1], sort.columns[index].value)
            assert.are.equal(entry[2], sort.columns[index].label)
        end
        assert.are.equal(2, #sort.directions)
        assert.are.equal("desc", sort.directions[1].value)
        assert.are.equal("Descending", sort.directions[1].label)
        assert.are.equal("asc", sort.directions[2].value)
        assert.are.equal("Ascending", sort.directions[2].label)
        -- Best Match descending is the search default.
        assert.are.equal("_score", sort.column)
        assert.are.equal("desc", sort.direction)
        assert.is_false(plugin:sortChanged(search_state()))
    end)

    it("adopts a sort from a pasted URL and keeps it out of page 1", function()
        local state = work_state(WORK_URL
            .. "?page=2&work_search%5Bsort_column%5D=hits")
        assert.are.equal("hits", state.sort.column)
        assert.are.equal("hits", state.applied_sort.column)
        -- Not the page's own first option: the funnel can say "changed".
        assert.are.equal("revised_at", state.sort.default_column)
        assert.is_true(plugin:sortChanged(state))
        -- Base URL keeps the page's sort (no state passed) but drops page 2.
        assert.are.equal(WORK_URL .. "?work_search%5Bsort_column%5D=hits",
            state.base_url)
        -- Apply writes the chosen sort once, not twice.
        local url = plugin:filterUrl(state.base_url, state)
        assert.are.equal(WORK_URL .. "?work_search%5Bsort_column%5D=hits", url)
        local _, count = url:gsub("sort_column", "")
        assert.are.equal(1, count)
    end)

    it("keeps an unknown raw sort value as its own option", function()
        local state = work_state(WORK_URL
            .. "?work_search%5Bsort_column%5D=surprise")
        assert.are.equal("surprise", state.sort.column)
        local found
        for _, option in ipairs(state.sort.columns) do
            if option.value == "surprise" then found = option end
        end
        assert.is_truthy(found)
        assert.are.equal("surprise", found.label)
        assert.is_truthy(plugin:filterUrl(state.base_url, state)
            :find("work_search%5Bsort_column%5D=surprise", 1, true))
    end)

    it("appends exactly one sort pair on Apply and keeps the query", function()
        local state = search_state()
        plugin:toggleFacet(state,
            plugin:filterDimension(state, "complete").include[1])
        state.sort.column = "kudos_count"
        state.sort.direction = "asc"
        local url = plugin:filterUrl(SEARCH, state, false)
        assert.are.equal(
            SEARCH
                .. "&work_search%5Bcomplete%5D=T"
                .. "&work_search%5Bsort_column%5D=kudos_count"
                .. "&work_search%5Bsort_direction%5D=asc",
            url)
        local _, sort_columns = url:gsub("sort_column", "")
        local _, sort_directions = url:gsub("sort_direction", "")
        assert.are.equal(1, sort_columns)
        assert.are.equal(1, sort_directions)
        assert.is_truthy(url:find("work_search%5Bquery%5D=echoes", 1, true))

        -- A paging link that already carried a sort is rewritten, not doubled.
        local paged = plugin:filterUrl(SEARCH
            .. "&page=2&work_search%5Bsort_column%5D=title_to_sort_on"
            .. "&work_search%5Bsort_direction%5D=asc", state, true)
        assert.are.equal(
            SEARCH .. "&page=2&work_search%5Bcomplete%5D=T"
                .. "&work_search%5Bsort_column%5D=kudos_count"
                .. "&work_search%5Bsort_direction%5D=asc", paged)
    end)

    it("keeps sort while paging and never writes a bookmark direction", function()
        local state = bookmark_state()
        state.sort.column = "word_count"
        local url = plugin:filterUrl(
            "https://archiveofourown.org/users/demo_reader/bookmarks?page=2",
            state, true)
        assert.are.equal(
            "https://archiveofourown.org/users/demo_reader/bookmarks?page=2"
                .. "&bookmark_search%5Bsort_column%5D=word_count", url)
        assert.is_nil(url:find("sort_direction", 1, true))
    end)

    it("clearing facets leaves the sort alone", function()
        local state = work_state()
        plugin:toggleFacet(state, work_listing().facets.rating.include[2])
        state.sort.column = "hits"
        plugin:clearFilters(state)
        assert.are.equal(0, plugin:filterCount(state))
        assert.are.equal("hits", state.sort.column)
        assert.are.equal(WORK_URL .. "?work_search%5Bsort_column%5D=hits",
            plugin:filterUrl(state.base_url, state))
    end)

    it("offers a Default sort row that restores the page's own choice", function()
        local state = work_state()
        local menu = open_listing(state)
        plugin:showFilterSort(state)
        local hits = row_with(menu.item_table, "filter_sort_column",
            { ao3_sort_value = "hits" })
        assert.is_truthy(hits)
        assert.is_nil(hits.mandatory)
        -- The current column carries the same checkmark the facets use.
        assert.are.equal("\u{2713}", row_with(menu.item_table,
            "filter_sort_column", { ao3_sort_value = "revised_at" }).mandatory)
        -- No direction section when the page has no direction select.
        assert.is_nil(row_with(menu.item_table, "filter_sort_direction"))
        assert.is_nil(row_with(menu.item_table, "filter_sort_direction_label"))

        hits.action()
        assert.are.equal("hits", state.sort.column)
        assert.are.equal("\u{2713}", row_with(menu.item_table,
            "filter_sort_column", { ao3_sort_value = "hits" }).mandatory)

        local default = row_with(menu.item_table, "filter_sort_default")
        assert.are.equal("Default sort", default.text)
        default.action()
        assert.are.equal("revised_at", state.sort.column)
    end)

    it("shows a Direction section only for a source that has one", function()
        local state = search_state()
        local menu = open_listing(state)
        plugin:showFilterSort(state)
        assert.are.equal("Sort by", menu.ao3_title)
        assert.is_truthy(row_with(menu.item_table, "filter_sort_direction_label"))
        assert.are.equal("\u{2713}", row_with(menu.item_table,
            "filter_sort_direction", { ao3_sort_value = "desc" }).mandatory)

        local asc = row_with(menu.item_table, "filter_sort_direction",
            { ao3_sort_value = "asc" })
        asc.action()
        assert.are.equal("asc", state.sort.direction)

        row_with(menu.item_table, "filter_sort_default").action()
        assert.are.equal("_score", state.sort.column)
        assert.are.equal("desc", state.sort.direction)
    end)

    it("fills the funnel when only the sort changed", function()
        local state = work_state()
        local menu = open_listing(state)
        assert.are.equal(menu.ao3_filter_icons.off, menu.ao3_filter_button.image)

        plugin:showFilterSort(state)
        row_with(menu.item_table, "filter_sort_column",
            { ao3_sort_value = "kudos_count" }).action()
        -- Pending: the listing in front of the reader has not changed yet.
        assert.are.equal(0, plugin:filterAppliedCount(state))
        assert.are.equal(menu.ao3_filter_icons.off, menu.ao3_filter_button.image)

        local old_fetch = plugin.fetchPage
        plugin.fetchPage = function(_, url, parse, label, on_success)
            on_success(work_listing())
        end
        local ok, err = pcall(function()
            plugin:applyFilters(state)
        end)
        plugin.fetchPage = old_fetch
        assert.is_true(ok, err)

        assert.are.equal(0, plugin:filterAppliedCount(state))
        assert.is_true(plugin:sortChanged(state))
        assert.are.equal(menu.ao3_filter_icons.on, menu.ao3_filter_button.image)

        -- Back out without another Apply keeps the applied sort.
        menu:onClose()
        assert.are.equal("kudos_count", state.sort.column)
    end)

    it("draws the Sort section only when the page has sort options", function()
        local listing = work_listing()
        listing.sort = nil
        local state = assert(plugin:newFilterState(listing, WORK_URL, "Time Travel"))
        local rows = plugin:filterRootRows(state)
        assert.is_nil(row_with(rows, "filter_sort"))
        assert.is_nil(row_with(rows, "filter_sort_label"))
        assert.are.equal("filter_label", rows[1].role)
        assert.are.equal("filter_apply", rows[#rows].role)
    end)

    it("keeps Sort, the grid and Apply on one 600x800 page", function()
        -- The reference canvas: eight bookmark tiles and nine search tiles
        -- must not push the Apply bar onto a second page.
        local cases = {
            bookmark_state(),
            search_state(),
        }
        for _, state in ipairs(cases) do
            local menu = open_listing(state)
            plugin:showFilterRoot(state)
            menu:updateItems()
            assert.are.equal(1, #menu.page_items, state.scope)
        end
    end)
end)
