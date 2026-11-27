-- KOReader busted spec for bookmark-list filters.
--
-- Offline: `fixtures/bookmark_filters.html` is a realistic bookmark page
-- carrying AO3's `form#bookmark-filters` sidebar (all eight dimensions,
-- include and exclude facets, counts, ids) and a pagination link that already
-- carries `bookmark_search` params.

require("commonrequire")

local UIManager = require("ui/uimanager")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")
local AuthorPage = dofile("plugins/ao3.koplugin/authorpage.lua")

local fixture_dir = "plugins/ao3.koplugin/spec/fixtures/"

local function read_fixture(name)
    local f = assert(io.open(fixture_dir .. name, "rb"))
    local body = f:read("*a")
    f:close()
    return body
end

describe("AO3 bookmark filters", function()
    local plugin

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
    end)

    after_each(function()
        plugin.menu = nil
    end)

    local function fixture_listing()
        local listing, err = plugin:parseListing(read_fixture("bookmark_filters.html"))
        assert.is_nil(err)
        assert.is_truthy(listing)
        return listing
    end

    local function fixture_state(url)
        return assert(plugin:newFilterState(fixture_listing(),
            url or "https://archiveofourown.org/users/demo_reader/bookmarks",
            "Bookmarks"))
    end

    local function open_listing(listing, state)
        listing = listing or fixture_listing()
        state = state or plugin:newFilterState(listing,
            "https://archiveofourown.org/users/demo_reader/bookmarks", "Bookmarks")
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        plugin:showListing(listing, "Bookmarks", false, state)
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

    it("parses the bookmark sidebar's eight dimensions, including bookmarker tags", function()
        local listing = fixture_listing()
        local facets = listing.bookmark_facets
        assert.is_truthy(facets)
        -- A bookmark page has no work sidebar, so the work facets stay empty.
        assert.is_nil(next(listing.facets or {}))

        assert.is_truthy(facets.rating)
        assert.is_truthy(facets.archive_warning)
        assert.is_truthy(facets.category)
        assert.is_truthy(facets.fandom)
        assert.is_truthy(facets.character)
        assert.is_truthy(facets.relationship)
        assert.is_truthy(facets.freeform)
        assert.is_truthy(facets.tag)

        local general = facets.rating.include[2]
        assert.are.equal("10", general.id)
        assert.are.equal("General Audiences", general.name)
        assert.are.equal(8, general.count)
        assert.are.equal("rating", general.type)
        assert.are.equal("include", general.action)
        assert.are.equal("radio", general.control)

        local explicit = facets.rating.exclude[1]
        assert.are.equal("13", explicit.id)
        assert.are.equal("Explicit", explicit.name)
        assert.are.equal("exclude", explicit.action)
        assert.are.equal("checkbox", explicit.control)

        -- The extra dimension: the bookmarker's own tag, not the work's.
        local reread = facets.tag.include[1]
        assert.are.equal("55001", reread.id)
        assert.are.equal("Reread", reread.name)
        assert.are.equal(6, reread.count)
        assert.are.equal("tag", reread.type)
        assert.are.equal("include", reread.action)

        local abandoned = facets.tag.exclude[1]
        assert.are.equal("55003", abandoned.id)
        assert.are.equal("Abandoned", abandoned.name)
        assert.are.equal("exclude", abandoned.action)

        -- Free-text boxes and the sort control are out of scope.
        assert.is_nil(facets.other_tag_names)
        assert.is_nil(facets.other_bookmark_tag_names)
        assert.is_nil(facets.sort_column)
    end)

    it("builds bookmark_search params and never work_search ones", function()
        local listing = fixture_listing()
        local state = fixture_state()
        assert.are.equal("bookmark", state.scope)

        plugin:toggleFacet(state, listing.bookmark_facets.rating.include[2])
        plugin:toggleFacet(state, listing.bookmark_facets.tag.exclude[1])
        plugin:toggleFacet(state, listing.bookmark_facets.fandom.include[1])

        local url = plugin:filterUrl(state.base_url, state)
        assert.are.equal(
            "https://archiveofourown.org/users/demo_reader/bookmarks"
                .. "?include_bookmark_search%5Brating_ids%5D%5B%5D=10"
                .. "&include_bookmark_search%5Bfandom_ids%5D%5B%5D=12345"
                .. "&exclude_bookmark_search%5Btag_ids%5D%5B%5D=55003",
            url)
        assert.is_nil(url:find("work_search", 1, true))
    end)

    it("adopts bookmark filters already on the URL", function()
        local state = fixture_state(
            "https://archiveofourown.org/users/demo_reader/bookmarks?"
                .. "include_bookmark_search%5Btag_ids%5D%5B%5D=55001"
                .. "&exclude_bookmark_search%5Brating_ids%5D%5B%5D=13")
        assert.is_truthy(state.selected.include.tag["55001"])
        assert.is_truthy(state.selected.exclude.rating["13"])
        assert.are.equal(2, plugin:filterCount(state))
        assert.are.equal(2, plugin:filterAppliedCount(state))
    end)

    it("shows bookmark dimensions in the same dialog", function()
        local listing = fixture_listing()
        local state = plugin:newFilterState(listing,
            "https://archiveofourown.org/users/demo_reader/bookmarks", "Bookmarks")
        local rows = plugin:filterRootRows(state)

        local include_tag = row_with(rows, "filter_dimension",
            { ao3_filter_action = "include", ao3_filter_type = "tag" })
        assert.is_truthy(include_tag)
        assert.are.equal("Bookmarker's Tags", include_tag.text)

        local exclude_tag = row_with(rows, "filter_dimension",
            { ao3_filter_action = "exclude", ao3_filter_type = "tag" })
        assert.is_truthy(exclude_tag)

        local include_rating = row_with(rows, "filter_dimension",
            { ao3_filter_action = "include", ao3_filter_type = "rating" })
        assert.is_truthy(include_rating)
        assert.are.equal("filter_apply", rows[#rows].role)

        local menu = open_listing(listing, state)
        plugin:showFilterRoot(state)
        assert.are.equal("Filter bookmarks", menu.ao3_title)
        menu:onClose()

        plugin:toggleFacet(state, state.facets.tag.include[1])
        local facet_rows = plugin:filterFacetRows(state, "include", "tag")
        local reread = row_with(facet_rows, "filter_facet", { text = "Reread" })
        assert.are.equal("\u{2713} 6", reread.mandatory)
    end)

    it("preserves bookmark filters while paging", function()
        local listing = fixture_listing()
        local state = fixture_state()
        plugin:toggleFacet(state, listing.bookmark_facets.tag.include[1])
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
            "include_bookmark_search%5Btag_ids%5D%5B%5D=55001", 1, true))
        -- AO3's link carried a rating and a warning; the state replaces them.
        assert.is_nil(captured.url:find("rating_ids", 1, true))
        assert.is_nil(captured.url:find("work_search", 1, true))
        local _, count = captured.url:gsub("include_bookmark_search", "")
        assert.are.equal(1, count)
    end)

    it("shows the funnel only on a bookmark listing and drops a pending tick on leave", function()
        local listing = fixture_listing()
        local menu = open_listing(listing)
        assert.is_true(menu.ao3_filter_visible)
        local state = menu.item_table.ao3_filter_state
        assert.are.equal("bookmark", state.scope)

        plugin:showFilterRoot(state)
        local reread = row_with(plugin:filterFacetRows(state, "include", "tag"),
            "filter_facet", { text = "Reread" })
        plugin:toggleFacet(state, reread.ao3_facet)
        assert.are.equal(1, plugin:filterCount(state))

        menu:onClose()
        assert.are.equal(0, plugin:filterCount(state))
        assert.are.equal(0, plugin:filterAppliedCount(state))
        assert.are.equal(menu.ao3_filter_icons.off, menu.ao3_filter_button.image)

        -- Leaving the listing drops its state and the funnel.
        menu:onClose()
        assert.is_nil(menu.item_table.ao3_filter_state)
        assert.is_false(menu.ao3_filter_visible)
    end)

    it("gives the author Bookmarks shelf the bookmark funnel, not the series shelf", function()
        local listing = fixture_listing()
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        UIManager.show = old_show
        plugin.author = {
            name = "demo_reader",
            profile = "https://archiveofourown.org/users/demo_reader",
            tab = "bookmarks",
            cache = {},
        }

        plugin:showAuthorRows("bookmarks", listing, false)
        assert.is_truthy(menu.item_table.ao3_filter_state)
        assert.are.equal("bookmark", menu.item_table.ao3_filter_state.scope)
        assert.is_true(menu.ao3_filter_visible)

        plugin:showAuthorRows("series", { items = {} }, true)
        assert.is_nil(menu.item_table.ao3_filter_state)
        assert.is_false(menu.ao3_filter_visible)
    end)

    it("gives the account Bookmarks list the funnel and paging keeps its params", function()
        local listing = fixture_listing()
        plugin.session = { username = "demo_reader" }
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        local filters = plugin:newFilterState(listing,
            "https://archiveofourown.org/users/demo_reader/bookmarks", "Bookmarks")
        plugin:showAccountRows("bookmarks", listing, false, filters)
        UIManager.show = old_show

        assert.are.equal("bookmark", menu.item_table.ao3_filter_state.scope)
        assert.is_true(menu.ao3_filter_visible)
        local next_row = row_with(menu.item_table, nil, { text = "Next page →" })
        assert.is_truthy(next_row)
    end)

    it("parses bookmark facets through the author bookmark parser too", function()
        local data = AuthorPage.parseBookmarks(read_fixture("bookmark_filters.html"),
            function(root) return plugin:parseBookmarkFacets(root) end)
        assert.is_truthy(data)
        assert.are.equal(2, #data.items)
        assert.is_truthy(data.bookmark_facets.tag)
        assert.are.equal("Reread", data.bookmark_facets.tag.include[1].name)
        assert.are.equal("10", data.bookmark_facets.rating.include[2].id)
    end)

    it("offers typed tags on bookmark dimensions", function()
        local state = fixture_state()
        -- Work tags and the bookmarker's own tags both take a typed name.
        for _, kind in ipairs({ "fandom", "character", "relationship",
                "freeform", "tag" }) do
            assert.is_truthy(row_with(
                plugin:filterFacetRows(state, "include", kind), "filter_add_tag"),
                kind)
        end
        -- Ratings stay their fixed list.
        assert.is_nil(row_with(
            plugin:filterFacetRows(state, "include", "rating"), "filter_add_tag"))
    end)

    it("writes bookmark work tags and bookmarker tags to their own fields", function()
        local state = fixture_state()
        plugin:addTypedTag(state, "include", "fandom", "Hannibal (TV)")
        plugin:addTypedTag(state, "exclude", "freeform", "Hades (Video Game)")
        plugin:addTypedTag(state, "include", "tag", "Time Loop")
        plugin:addTypedTag(state, "exclude", "tag", "Dropped")

        local url = plugin:filterUrl(state.base_url, state)
        assert.are.equal(
            "https://archiveofourown.org/users/demo_reader/bookmarks"
                .. "?bookmark_search%5Bother_tag_names%5D=Hannibal%20%28TV%29"
                .. "&bookmark_search%5Bother_bookmark_tag_names%5D=Time%20Loop"
                .. "&bookmark_search%5Bexcluded_tag_names%5D=Hades%20%28Video%20Game%29"
                .. "&bookmark_search%5Bexcluded_bookmark_tag_names%5D=Dropped",
            url)
        assert.is_nil(url:find("work_search", 1, true))
    end)

    it("adopts typed bookmarker tags from a URL and keeps their own field", function()
        local state = fixture_state(
            "https://archiveofourown.org/users/demo_reader/bookmarks?"
                .. "bookmark_search%5Bother_bookmark_tag_names%5D=Reread%2CFluff"
                .. "&bookmark_search%5Bother_tag_names%5D=Angst")
        assert.are.equal(3, plugin:filterCount(state))
        assert.is_truthy(state.selected.include.tag["Reread"])

        local url = plugin:filterUrl(state.base_url, state)
        assert.are.equal(
            "https://archiveofourown.org/users/demo_reader/bookmarks"
                .. "?bookmark_search%5Bother_tag_names%5D=Angst"
                .. "&bookmark_search%5Bother_bookmark_tag_names%5D=Fluff,Reread",
            url)
    end)
end)
