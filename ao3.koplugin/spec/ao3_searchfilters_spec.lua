-- KOReader busted spec for filters on AO3's keyword search.
--
-- A search results page carries no `#work-filters` sidebar (proven by
-- `fixtures/search.html`), so the dialog is built from the fixed lists the
-- search action reads. `fixtures/search_form.html` is a trimmed copy of AO3's
-- live Edit Search form: every id and name this module carries must appear in
-- it, so a re-seed that moved one fails here instead of in a filter.

require("commonrequire")

local UIManager = require("ui/uimanager")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")
local SearchFilters = dofile("plugins/ao3.koplugin/searchfilters.lua")

local fixture_dir = "plugins/ao3.koplugin/spec/fixtures/"

local SEARCH = "https://archiveofourown.org/works/search"
    .. "?work_search%5Bquery%5D=echoes%20in%20eternity"

local function read_fixture(name)
    local f = assert(io.open(fixture_dir .. name, "rb"))
    local body = f:read("*a")
    f:close()
    return body
end

describe("AO3 search filters", function()
    local plugin

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
    end)

    after_each(function()
        plugin.menu = nil
    end)

    local function search_state(url, title)
        return assert(plugin:newSearchFilterState(url or SEARCH,
            title or "Search: echoes in eternity"))
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

    local function dimension_tile(rows, kind)
        for _, row in ipairs(rows) do
            for _, tile in ipairs(row.tiles or {}) do
                if tile.role == "filter_dimension"
                        and tile.ao3_filter_type == kind then
                    return tile, row
                end
            end
        end
    end

    it("recognises the search results URL and no other listing", function()
        assert.is_true(SearchFilters.isSearchUrl(SEARCH))
        assert.is_true(SearchFilters.isSearchUrl(
            "https://archiveofourown.org/works/search"))
        -- A hand-written index URL that carries a query is the same search.
        assert.is_true(SearchFilters.isSearchUrl(
            "https://archiveofourown.org/works?work_search%5Bquery%5D=x"))
        assert.is_false(SearchFilters.isSearchUrl(
            "https://archiveofourown.org/works"))
        assert.is_false(SearchFilters.isSearchUrl(
            "https://archiveofourown.org/tags/Time%20Travel/works"))
        assert.is_false(SearchFilters.isSearchUrl(
            "https://archiveofourown.org/users/demo_reader/bookmarks"))
    end)

    it("pins every static facet to AO3's live edit-search form", function()
        local html = read_fixture("search_form.html")
        local groups = {
            { kind = "rating", list = SearchFilters.RATINGS,
                name = "work_search[rating_ids]" },
            { kind = "archive_warning", list = SearchFilters.WARNINGS,
                name = "work_search[archive_warning_ids][]" },
            { kind = "category", list = SearchFilters.CATEGORIES,
                name = "work_search[category_ids][]" },
        }
        for _, group in ipairs(groups) do
            assert.is_truthy(html:find(group.name, 1, true), group.kind)
            for _, entry in ipairs(group.list) do
                local id, name = entry[1], entry[2]
                assert.is_truthy(html:find('value="' .. id .. '"', 1, true),
                    group.kind .. " id " .. id)
                assert.is_truthy(html:find(">" .. name .. "<", 1, true),
                    group.kind .. " name " .. name)
            end
        end
    end)

    it("builds a state only for a search listing", function()
        assert.is_truthy(plugin:newSearchFilterState(SEARCH, "Search"))
        assert.is_nil(plugin:newSearchFilterState(
            "https://archiveofourown.org/tags/Time%20Travel/works", "Time Travel"))
        local state = search_state()
        assert.are.equal("search", state.scope)
        assert.are.equal(SEARCH, state.base_url)
    end)

    it("offers the fixed lists and the typed tag dimensions", function()
        local state = search_state()
        local rows = plugin:filterRootRows(state)

        for _, kind in ipairs({ "rating", "archive_warning", "category",
                "complete", "crossover", "fandom", "character",
                "relationship", "freeform" }) do
            assert.is_truthy(dimension_tile(rows, kind), kind)
        end
        -- One tile per dimension, and no Include/Exclude group rows.
        assert.is_nil(row_with(rows, "filter_group"))
        for _, kind in ipairs({ "fandom", "character", "relationship",
                "freeform" }) do
            assert.is_truthy(row_with(
                plugin:filterFacetRows(state, "include", kind), "filter_add_tag"),
                kind)
        end

        -- The side switch lives on the dimension page. AO3's search form has
        -- no exclude side for its fixed lists, so that page simply has no
        -- facets to tick, while the typed tag dimensions keep both sides.
        local rating_rows = plugin:filterFacetRows(state, "include", "rating")
        assert.is_truthy(row_with(rating_rows, "filter_facet"))
        assert.are.equal("\u{2713}", row_with(rating_rows, "filter_side",
            { ao3_filter_action = "include" }).mandatory)
        assert.is_nil(row_with(plugin:filterFacetRows(state, "exclude", "rating"),
            "filter_facet"))
        assert.is_truthy(row_with(plugin:filterFacetRows(state, "exclude", "freeform"),
            "filter_add_tag"))
        assert.is_truthy(row_with(rows, "filter_sort"))
        assert.are.equal("filter_apply", rows[#rows].role)
    end)

    it("applies the fixed lists and typed tags while keeping the query", function()
        local state = search_state()
        local rating = plugin:filterDimension(state, "rating").include[4]
        assert.are.equal("12", rating.id)
        plugin:toggleFacet(state, rating)

        local warnings = plugin:filterDimension(state, "archive_warning").include
        plugin:toggleFacet(state, warnings[1])
        plugin:toggleFacet(state, warnings[4])

        plugin:toggleFacet(state,
            plugin:filterDimension(state, "category").include[1])
        plugin:toggleFacet(state,
            plugin:filterDimension(state, "complete").include[1])
        plugin:addTypedTag(state, "include", "fandom", "Hannibal (TV)")

        local url = plugin:filterUrl(state.base_url, state)
        assert.are.equal(
            SEARCH
                .. "&work_search%5Brating_ids%5D%5B%5D=12"
                .. "&work_search%5Barchive_warning_ids%5D%5B%5D=14"
                .. "&work_search%5Barchive_warning_ids%5D%5B%5D=16"
                .. "&work_search%5Bcategory_ids%5D%5B%5D=116"
                .. "&work_search%5Bcomplete%5D=T"
                .. "&work_search%5Bother_tag_names%5D=Hannibal%20%28TV%29"
                .. "&work_search%5Bsort_column%5D=_score"
                .. "&work_search%5Bsort_direction%5D=desc",
            url)
        -- A listing-filter parameter must never leak into a search.
        assert.is_nil(url:find("include_work_search", 1, true))
        assert.is_nil(url:find("exclude_work_search", 1, true))
    end)

    it("adopts filters from a pasted search URL", function()
        local state = search_state(SEARCH
            .. "&work_search%5Brating_ids%5D%5B%5D=13"
            .. "&work_search%5Bcomplete%5D=F"
            .. "&work_search%5Bcategory_ids%5D%5B%5D=23"
            .. "&work_search%5Bother_tag_names%5D=Fluff%2CAngst")
        assert.are.equal(5, plugin:filterCount(state))
        assert.are.equal(5, plugin:filterAppliedCount(state))
        assert.is_truthy(state.selected.include.rating["13"])
        assert.is_truthy(state.selected.include.complete["F"])
        assert.is_truthy(state.selected.include.category["23"])
        -- Adopted typed names have no dimension on AO3's form, so they land in
        -- the typed bucket and still travel as work tags.
        assert.is_truthy(state.selected.include.tag["Angst"])
        -- The selected facet is AO3's own name, not the bare id.
        assert.are.equal("Explicit", state.selected.include.rating["13"].name)

        local url = plugin:filterUrl(state.base_url, state)
        assert.are.equal(
            SEARCH
                .. "&work_search%5Brating_ids%5D%5B%5D=13"
                .. "&work_search%5Bcategory_ids%5D%5B%5D=23"
                .. "&work_search%5Bcomplete%5D=F"
                .. "&work_search%5Bother_tag_names%5D=Angst,Fluff"
                .. "&work_search%5Bsort_column%5D=_score"
                .. "&work_search%5Bsort_direction%5D=desc",
            url)
    end)

    it("keeps its filters and its page while paging", function()
        local state = search_state()
        plugin:toggleFacet(state,
            plugin:filterDimension(state, "complete").include[2])
        local url = plugin:filterUrl(SEARCH .. "&page=2", state, true)
        assert.are.equal(
            SEARCH .. "&page=2&work_search%5Bcomplete%5D=F"
                .. "&work_search%5Bsort_column%5D=_score"
                .. "&work_search%5Bsort_direction%5D=desc", url)
        local first = plugin:filterUrl(SEARCH .. "&page=2", state, false)
        assert.are.equal(
            SEARCH .. "&work_search%5Bcomplete%5D=F"
                .. "&work_search%5Bsort_column%5D=_score"
                .. "&work_search%5Bsort_direction%5D=desc", first)
    end)

    it("shows the funnel on a search listing and drops it on leave", function()
        local listing = assert(plugin:parseListing(read_fixture("search.html")))
        assert.is_nil(next(listing.facets or {}))

        local state = search_state()
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        plugin:showListing(listing, "Search: echoes in eternity", false, state)
        UIManager.show = old_show

        assert.is_true(menu.ao3_filter_visible)
        assert.are.equal("search", menu.item_table.ao3_filter_state.scope)

        plugin:showFilterRoot(state)
        assert.are.equal("Filter search results", menu.ao3_title)

        -- Back from the filter screen returns to the listing with its state.
        menu:onClose()
        assert.are.equal("search", menu.item_table.ao3_filter_state.scope)
        assert.is_true(menu.ao3_filter_visible)

        -- Leaving the listing itself drops the state and the funnel.
        menu:onClose()
        assert.is_nil(menu.item_table.ao3_filter_state)
        assert.is_false(menu.ao3_filter_visible)
    end)

    it("keeps the shared dimension labels in step with the sidebar ones", function()
        local by_key = {}
        for _, dimension in ipairs(SearchFilters.DIMENSIONS) do
            by_key[dimension.key] = dimension.label
        end
        for _, dimension in ipairs(Ao3.FILTER_DIMENSIONS) do
            if by_key[dimension.key] then
                assert.are.equal(dimension.label, by_key[dimension.key],
                    dimension.key)
            end
        end
    end)
end)
