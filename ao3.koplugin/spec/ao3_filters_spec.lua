-- KOReader busted spec for the listing filter dialog and its URL.
--
-- Offline: `fixtures/filters.html` is a realistic work listing carrying AO3's
-- `form#work-filters` sidebar (include and exclude facets, counts, ids) and a
-- pagination link that already carries filter params.

require("commonrequire")

local UIManager = require("ui/uimanager")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")

local fixture_dir = "plugins/ao3.koplugin/spec/fixtures/"

local function read_fixture(name)
    local f = assert(io.open(fixture_dir .. name, "rb"))
    local body = f:read("*a")
    f:close()
    return body
end

describe("AO3 listing filters", function()
    local plugin

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
    end)

    after_each(function()
        plugin.menu = nil
    end)

    local function fixture_listing()
        local listing, err = plugin:parseListing(read_fixture("filters.html"))
        assert.is_nil(err)
        assert.is_truthy(listing)
        return listing
    end

    local function open_listing(listing, state)
        listing = listing or fixture_listing()
        state = state or plugin:newFilterState(listing,
            "https://archiveofourown.org/tags/Time%20Travel/works", "Time Travel")
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        plugin:showListing(listing, "Time Travel", false, state)
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

    it("parses include and exclude facets with ids, names, counts and controls", function()
        local facets = fixture_listing().facets
        assert.is_truthy(facets)

        -- Rating: AO3's include list is a radio group, exclude is not offered
        -- as a radio because excluding ratings is a set.
        assert.are.equal(5, #facets.rating.include)
        local general = facets.rating.include[2]
        assert.are.equal("10", general.id)
        assert.are.equal("General Audiences", general.name)
        assert.are.equal(1889081, general.count)
        assert.are.equal("rating", general.type)
        assert.are.equal("include", general.action)
        assert.are.equal("radio", general.control)

        assert.are.equal(2, #facets.rating.exclude)
        assert.are.equal("exclude", facets.rating.exclude[1].action)
        assert.are.equal("checkbox", facets.rating.exclude[1].control)

        -- A name with its own parentheses keeps them; the final "(n)" is the
        -- work count.
        local lucifer = facets.fandom.include[2]
        assert.are.equal("136512", lucifer.id)
        assert.are.equal("Lucifer (TV)", lucifer.name)
        assert.are.equal(12, lucifer.count)
        assert.are.equal("fandom", lucifer.type)
        assert.are.equal("checkbox", lucifer.control)

        assert.are.equal(3, #facets.category.include)
        assert.are.equal(2, #facets.character.include)
        assert.are.equal(2, #facets.relationship.include)
        assert.are.equal(3, #facets.freeform.include)
        assert.are.equal(1, #facets.freeform.exclude)
        assert.are.equal(2, #facets.archive_warning.exclude)

        -- The free-text boxes and sort controls are out of scope.
        assert.is_nil(facets.other_tag_names)
        assert.is_nil(facets.sort_column)
        assert.is_nil(facets.query)
    end)

    it("keeps a listing without a filter form free of facets", function()
        local listing = plugin:parseListing(read_fixture("search.html"))
        assert.is_truthy(listing)
        assert.is_nil(next(listing.facets or {}))
        assert.is_nil(plugin:newFilterState(listing,
            "https://archiveofourown.org/works/search", "Search"))
    end)

    it("builds include/exclude params and drops untouched dimensions", function()
        local listing = fixture_listing()
        local state = assert(plugin:newFilterState(listing,
            "https://archiveofourown.org/tags/Time%20Travel/works", "Time Travel"))

        plugin:toggleFacet(state, listing.facets.rating.include[2])
        plugin:toggleFacet(state, listing.facets.archive_warning.exclude[1])
        plugin:toggleFacet(state, listing.facets.freeform.exclude[1])

        local url = plugin:filterUrl(state.base_url, state)
        assert.are.equal(
            "https://archiveofourown.org/tags/Time%20Travel/works"
                .. "?include_work_search%5Brating_ids%5D%5B%5D=10"
                .. "&exclude_work_search%5Barchive_warning_ids%5D%5B%5D=17"
                .. "&exclude_work_search%5Bfreeform_ids%5D%5B%5D=44003",
            url)
        assert.is_nil(url:find("category_ids", 1, true))
        assert.is_nil(url:find("character_ids", 1, true))
        assert.is_nil(url:find("page=", 1, true))
    end)

    it("keeps the rating include list single-select", function()
        local listing = fixture_listing()
        local state = plugin:newFilterState(listing,
            "https://archiveofourown.org/tags/Time%20Travel/works", "Time Travel")
        plugin:toggleFacet(state, listing.facets.rating.include[4]) -- Mature
        plugin:toggleFacet(state, listing.facets.rating.include[5]) -- Explicit
        local url = plugin:filterUrl(state.base_url, state)
        assert.is_truthy(url:find("include_work_search%5Brating_ids%5D%5B%5D=13", 1, true))
        assert.is_nil(url:find("rating_ids%5D%5B%5D=12", 1, true))
        -- Tapping the chosen rating again clears it.
        plugin:toggleFacet(state, listing.facets.rating.include[5])
        assert.are.equal(0, plugin:filterCount(state))
    end)

    it("adopts filters already on the URL and reflects them in the dialog", function()
        local listing = fixture_listing()
        local state = assert(plugin:newFilterState(listing,
            "https://archiveofourown.org/tags/Time%20Travel/works?"
                .. "include_work_search%5Bfandom_ids%5D%5B%5D=12345"
                .. "&exclude_work_search%5Barchive_warning_ids%5D%5B%5D=17",
            "Time Travel"))
        assert.is_truthy(state.selected.include.fandom["12345"])
        assert.is_truthy(state.selected.exclude.archive_warning["17"])
        assert.are.equal(2, plugin:filterCount(state))

        local rows = plugin:filterRootRows(state)
        local include_label = row_with(rows, "filter_group", { ao3_filter_group = "include" })
        local exclude_label = row_with(rows, "filter_group", { ao3_filter_group = "exclude" })
        assert.is_truthy(include_label)
        assert.is_truthy(exclude_label)

        local fandom = row_with(rows, "filter_dimension",
            { ao3_filter_action = "include", ao3_filter_type = "fandom" })
        assert.are.equal("Fandom", fandom.text)
        assert.are.equal("1 selected", fandom.mandatory)

        local excluded_warning = row_with(rows, "filter_dimension",
            { ao3_filter_action = "exclude", ao3_filter_type = "archive_warning" })
        assert.are.equal("1 selected", excluded_warning.mandatory)

        assert.are.equal("filter_apply", rows[#rows].role)
        assert.is_true(rows[#rows].ao3_filter_clear)
    end)

    it("marks chosen facets with KOReader's checkmark and their count", function()
        local listing = fixture_listing()
        local state = plugin:newFilterState(listing,
            "https://archiveofourown.org/tags/Time%20Travel/works"
                .. "?include_work_search%5Bfandom_ids%5D%5B%5D=136512",
            "Time Travel")
        local rows = plugin:filterFacetRows(state, "include", "fandom")
        local chosen = row_with(rows, "filter_facet", { text = "Lucifer (TV)" })
        assert.is_truthy(chosen)
        assert.are.equal("\u{2713} 12", chosen.mandatory)

        local unchosen = row_with(rows, "filter_facet", { text = "Doctor Who" })
        assert.is_truthy(unchosen)
        assert.are.equal("1,204", unchosen.mandatory)
        assert.is_nil(unchosen.mandatory:find("\u{2713}", 1, true))
    end)

    it("rebuilds the root's selected count after a facet is toggled", function()
        local listing = fixture_listing()
        local menu = open_listing(listing)
        local state = menu.item_table.ao3_filter_state
        assert.is_truthy(state)
        plugin:showFilterRoot(state)

        local include_fandom = row_with(menu.item_table, "filter_dimension",
            { ao3_filter_action = "include", ao3_filter_type = "fandom" })
        assert.is_nil(include_fandom.mandatory)

        plugin:showFilterDimension(state, "include", "fandom")
        local facet_row = row_with(menu.item_table, "filter_facet", { text = "Lucifer (TV)" })
        assert.is_truthy(facet_row)
        facet_row.action()
        -- Still the same screen; the tick is in place.
        local ticked = row_with(menu.item_table, "filter_facet", { text = "Lucifer (TV)" })
        assert.are.equal("\u{2713} 12", ticked.mandatory)

        menu:onClose()
        include_fandom = row_with(menu.item_table, "filter_dimension",
            { ao3_filter_action = "include", ao3_filter_type = "fandom" })
        assert.are.equal("1 selected", include_fandom.mandatory)
    end)

    it("preserves filters while paging and keeps the page number", function()
        local listing = fixture_listing()
        local state = plugin:newFilterState(listing,
            "https://archiveofourown.org/tags/Time%20Travel/works", "Time Travel")
        plugin:toggleFacet(state, listing.facets.rating.include[2])
        local menu = open_listing(listing, state)

        local captured
        plugin.loadListing = function(_, url, title, replace, filters)
            captured = { url = url, title = title, replace = replace, filters = filters }
        end
        local next_row = row_with(menu.item_table, nil, { text = "Next page →" })
        assert.is_truthy(next_row)
        next_row.action()

        assert.is_truthy(captured)
        assert.is_true(captured.replace)
        assert.are.equal(state, captured.filters)
        assert.is_truthy(captured.url:find("page=2", 1, true))
        assert.is_truthy(captured.url:find(
            "include_work_search%5Brating_ids%5D%5B%5D=10", 1, true))
        -- AO3's own link carried the params too; they are written once.
        local _, count = captured.url:gsub("include_work_search", "")
        assert.are.equal(1, count)
    end)

    it("shows the filter button only on a listing and fills it when active", function()
        local listing = fixture_listing()
        local menu = open_listing(listing)
        assert.is_true(menu.ao3_filter_visible)
        assert.are.equal(menu.ao3_filter_icons.off, menu.ao3_filter_button.image)

        local state = menu.item_table.ao3_filter_state
        plugin:toggleFacet(state, listing.facets.fandom.include[2])
        -- A tick is pending until Apply: the funnel stays outlined while the
        -- listing in front of the reader is still unfiltered.
        plugin:showListing(listing, "Time Travel", true, state)
        assert.are.equal(menu.ao3_filter_icons.off, menu.ao3_filter_button.image)

        -- Once the set has been applied, the funnel is filled.
        state.applied.include.fandom = state.selected.include.fandom
        plugin:showListing(listing, "Time Travel", true, state)
        assert.is_true(menu.ao3_filter_visible)
        assert.are.equal(menu.ao3_filter_icons.on, menu.ao3_filter_button.image)

        -- The dialog is not a listing: the button goes away while it is open.
        plugin:showFilterRoot(state)
        assert.is_false(menu.ao3_filter_visible)
        assert.is_true(menu.ao3_filter_button.image.hide)

        -- Back to the listing brings it back, filled.
        menu:onClose()
        assert.is_true(menu.ao3_filter_visible)
        assert.are.equal(menu.ao3_filter_icons.on, menu.ao3_filter_button.image)

        -- Leaving the listing drops the state, so the next screen has no
        -- button and the next listing starts clean.
        menu:onClose()
        assert.is_nil(menu.item_table.ao3_filter_state)
        assert.is_false(menu.ao3_filter_visible)
        assert.is_true(menu.ao3_filter_button.image.hide)
    end)

    it("drops pending ticks when the dialog is left without Apply", function()
        local listing = fixture_listing()
        local menu = open_listing(listing)
        local state = menu.item_table.ao3_filter_state
        plugin:showFilterRoot(state)
        local fandom = row_with(plugin:filterFacetRows(state, "include", "fandom"),
            "filter_facet", { text = "Lucifer (TV)" })
        plugin:toggleFacet(state, fandom.ao3_facet)
        assert.are.equal(1, plugin:filterCount(state))

        menu:onClose()
        assert.are.equal(0, plugin:filterCount(state))
        assert.are.equal(0, plugin:filterAppliedCount(state))
        assert.are.equal(menu.ao3_filter_icons.off, menu.ao3_filter_button.image)
    end)

    it("offers the same filter on an author's Works shelf only", function()
        plugin.menu = nil
        local menu = plugin:ensureMenu()
        plugin.author = {
            name = "astolat",
            profile = "https://archiveofourown.org/users/astolat",
            tab = "works",
            cache = {},
        }
        plugin:showAuthorRows("works", fixture_listing(), false)
        assert.is_truthy(menu.item_table.ao3_filter_state)
        assert.is_true(menu.ao3_filter_visible)
        assert.are.equal("Works", menu.ao3_title)

        -- Another shelf is not a work listing: no funnel, no state.
        plugin:showAuthorRows("series", { items = {} }, true)
        assert.is_nil(menu.item_table.ao3_filter_state)
        assert.is_false(menu.ao3_filter_visible)
    end)

    it("applies in one request, pops the dialog and replaces the listing at page 1", function()
        local listing = fixture_listing()
        local menu = open_listing(listing)
        local state = menu.item_table.ao3_filter_state
        plugin:toggleFacet(state, listing.facets.rating.include[2])
        plugin:showFilterRoot(state)
        assert.are.equal(2, #menu.item_table_stack)
        assert.are.equal("filter_apply", menu.item_table[#menu.item_table].role)

        local fetched
        local old_fetch = plugin.fetchPage
        plugin.fetchPage = function(_, url, parse, label, on_success)
            fetched = { url = url, label = label }
            on_success({
                items = { { id = "9", title = "Filtered Work", authors = "A" } },
                count = "1",
                facets = listing.facets,
            })
        end

        local ok, err = pcall(function()
            menu.item_table[#menu.item_table].action()
        end)
        plugin.fetchPage = old_fetch
        assert.is_true(ok, err)

        assert.is_truthy(fetched)
        assert.is_truthy(fetched.url:find("page=", 1, true) == nil)
        assert.is_truthy(fetched.url:find(
            "include_work_search%5Brating_ids%5D%5B%5D=10", 1, true))
        -- The filter screen is gone and the listing beneath it holds one
        -- fresh page, still with its filters attached for paging.
        assert.are.equal(1, #menu.item_table_stack)
        assert.are.equal("Filtered Work", menu.item_table[1].text)
        assert.are.equal(state, menu.item_table.ao3_filter_state)
        assert.is_true(menu.ao3_filter_visible)
        assert.are.equal(1, plugin:filterAppliedCount(state))
        assert.are.equal(menu.ao3_filter_icons.on, menu.ao3_filter_button.image)
    end)
end)
