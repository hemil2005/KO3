-- KOReader busted spec for typed tag filtering: AO3's /autocomplete routes,
-- the JSON (and gzip) answer, the request generation, and the names AO3
-- receives on Apply.
--
-- Offline: `fixtures/autocomplete/*` are representative answers from AO3's
-- picker, plus a malformed body, a gzip copy and a rate-limited page.

require("commonrequire")

local NetworkMgr = require("ui/network/manager")

local Autocomplete = dofile("plugins/ao3.koplugin/autocomplete.lua")
local Ao3 = dofile("plugins/ao3.koplugin/main.lua")

local fixture_dir = "plugins/ao3.koplugin/spec/fixtures/"

local function read_fixture(name)
    local f = assert(io.open(fixture_dir .. name, "rb"))
    local body = f:read("*a")
    f:close()
    return body
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

describe("AO3 tag autocomplete", function()
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

    local function fixture_state(url)
        return assert(plugin:newFilterState(fixture_listing(),
            url or "https://archiveofourown.org/tags/Time%20Travel/works",
            "Time Travel"))
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

    it("asks /autocomplete/<type> with an encoded term", function()
        assert.are.equal(
            "https://archiveofourown.org/autocomplete/fandom?term=Harry%20Potter",
            Autocomplete.url("https://archiveofourown.org", "fandom", "Harry Potter"))
        assert.are.equal(
            "https://archiveofourown.org/autocomplete/character?term=Hijinks%20%26%20Shenanigans",
            Autocomplete.url("https://archiveofourown.org", "character",
                "Hijinks & Shenanigans"))
        assert.are.equal(
            "https://archiveofourown.org/autocomplete/freeform?term=Hurt%2FComfort",
            Autocomplete.url("https://archiveofourown.org", "freeform", "Hurt/Comfort"))
        assert.is_true(Autocomplete.isType("relationship"))
        assert.is_false(Autocomplete.isType("rating"))
    end)

    it("parses the JSON name list and keeps at most ten", function()
        local names = Autocomplete.parse(read_fixture("autocomplete/fandom.json"))
        assert.are.equal(10, #names)
        assert.are.equal("Harry Potter - J. K. Rowling", names[1])
        assert.are.equal("Highlander (Movies)", names[10])

        assert.are.equal(4, #Autocomplete.parse(
            read_fixture("autocomplete/freeform.json")))
        assert.are.equal(0, #Autocomplete.parse("[]"))
        assert.is_nil(Autocomplete.parse(read_fixture("autocomplete/malformed.json")))
        assert.is_nil(Autocomplete.parse(""))
    end)

    it("requests suggestions with the plugin's JSON GET and the session", function()
        local requested
        plugin.httpRequest = function(_, url, opts)
            requested = { url = url, opts = opts }
            return read_fixture("autocomplete/fandom.json"), nil, 200, {}
        end

        local names = plugin:tagSuggestions("fandom", "har")
        assert.are.equal(10, #names)
        assert.are.equal(
            "https://archiveofourown.org/autocomplete/fandom?term=har", requested.url)
        assert.are.equal("application/json", requested.opts.headers["Accept"])
        assert.are.equal("identity", requested.opts.headers["Accept-Encoding"])
        assert.is_false(requested.opts.retry_on_403)
    end)

    it("does not repeat a request for the same term", function()
        local calls = 0
        plugin.httpRequest = function()
            calls = calls + 1
            return read_fixture("autocomplete/fandom.json"), nil, 200, {}
        end
        assert.are.equal(10, #plugin:tagSuggestions("fandom", "har"))
        -- A repaint, a repeated strike or a typed echo of the same text is the
        -- same page AO3 already answered.
        assert.are.equal(10, #plugin:tagSuggestions("fandom", "HAR"))
        assert.are.equal(1, calls)

        -- A different term is a new page.
        plugin:tagSuggestions("fandom", "harr")
        assert.are.equal(2, calls)
    end)

    it("inflates a gzipped answer before decoding it", function()
        local gz = read_fixture("autocomplete/fandom.json.gz")
        plugin.httpRequest = function()
            return gz, nil, 200, { ["content-encoding"] = "gzip" }
        end
        local names = assert(plugin:tagSuggestions("fandom", "ha"))
        assert.are.equal(10, #names)
        assert.are.equal("Harry Potter - J. K. Rowling", names[1])

        -- A server that forgets the header is caught by the gzip magic.
        plugin = setmetatable({}, { __index = Ao3 })
        plugin.httpRequest = function() return gz, nil, 200, {} end
        assert.are.equal(10, #plugin:tagSuggestions("fandom", "ha"))
    end)

    it("discards an answer from a generation the reader has left", function()
        plugin.tag_suggest_token = 1
        plugin.httpRequest = function()
            -- The reader kept typing while the request was in flight.
            plugin.tag_suggest_token = 2
            return read_fixture("autocomplete/fandom.json"), nil, 200, {}
        end
        local names, err = plugin:tagSuggestions("fandom", "har", 1)
        assert.is_nil(names)
        assert.are.equal("stale", err)
    end)

    it("does not retry a 429 and reports no suggestions", function()
        local calls = 0
        plugin.httpRequest = function()
            calls = calls + 1
            return read_fixture("autocomplete/rate_limited.html"), nil, 429, {}
        end
        local names, err = plugin:tagSuggestions("fandom", "har")
        assert.is_nil(names)
        assert.are.equal("AO3 answered HTTP 429.", err)
        -- Same term, next keystroke: the back-off answers without a request.
        names = plugin:tagSuggestions("fandom", "harr")
        assert.is_nil(names)
        assert.are.equal(1, calls)
    end)

    it("does not retry a malformed answer", function()
        local calls = 0
        plugin.httpRequest = function()
            calls = calls + 1
            return read_fixture("autocomplete/malformed.json"), nil, 200, {}
        end
        local names, err = plugin:tagSuggestions("freeform", "hu")
        assert.is_nil(names)
        assert.are.equal("malformed", err)
        assert.is_nil(plugin:tagSuggestions("freeform", "hur"))
        assert.are.equal(1, calls)
    end)

    it("answers offline without touching the network", function()
        local saved = NetworkMgr.isConnected
        NetworkMgr.isConnected = function() return false end
        local calls = 0
        plugin.httpRequest = function() calls = calls + 1 end

        local result, reason
        plugin:fetchTagSuggestions("fandom", "har", 1, function(names, err)
            result, reason = names, err
        end)
        NetworkMgr.isConnected = saved

        assert.is_nil(result)
        assert.are.equal("offline", reason)
        assert.are.equal(0, calls)
    end)

    it("applies chosen names as other_tag_names/excluded_tag_names", function()
        local state = fixture_state()
        plugin:addTypedTag(state, "include", "fandom", "Hannibal (TV)")
        plugin:addTypedTag(state, "include", "freeform", "Hurt/Comfort")
        plugin:addTypedTag(state, "exclude", "character", "Hades (Video Game)")

        local url = plugin:filterUrl(state.base_url, state)
        assert.are.equal(
            "https://archiveofourown.org/tags/Time%20Travel/works"
                .. "?work_search%5Bother_tag_names%5D=Hannibal%20%28TV%29,Hurt%2FComfort"
                .. "&work_search%5Bexcluded_tag_names%5D=Hades%20%28Video%20Game%29"
                .. "&work_search%5Bsort_column%5D=revised_at",
            url)
        -- A typed tag never becomes an id param.
        assert.is_nil(url:find("fandom_ids", 1, true))
        assert.is_nil(url:find("character_ids", 1, true))
    end)

    it("selects an embedded facet by id when the typed name is already there", function()
        local state = fixture_state()
        plugin:addTypedTag(state, "include", "fandom",
            "Harry Potter - J. K. Rowling")
        assert.are.equal("12345", state.selected.include.fandom["12345"].id)
        assert.is_nil((plugin:filterUrl(state.base_url, state))
            :find("other_tag_names", 1, true))

        -- The same canonical name typed twice is one tag.
        plugin:addTypedTag(state, "include", "fandom", "Hannibal (TV)")
        plugin:addTypedTag(state, "include", "relationship", "Hannibal (TV)")
        assert.are.equal(2, plugin:filterCount(state))
    end)

    it("shows typed names in the dimension and counts them on the root", function()
        local state = fixture_state()
        plugin:addTypedTag(state, "include", "freeform", "Hurt/Comfort")

        local rows = plugin:filterFacetRows(state, "include", "freeform")
        local typed = row_with(rows, "filter_facet", { text = "Hurt/Comfort" })
        assert.is_truthy(typed)
        assert.is_true(typed.ao3_typed)
        assert.are.equal("\u{2713}", typed.mandatory)

        local add = row_with(rows, nil, { role = "filter_add_tag" })
        assert.are.equal("Search for a tag…", add.text)
        assert.are.equal("filter_add_tag", rows[#rows].role)

        -- Untyped dimensions do not offer a tag box.
        local rating = plugin:filterFacetRows(state, "include", "rating")
        assert.is_nil(row_with(rating, "filter_add_tag"))

        local root = plugin:filterRootRows(state)
        local freeform = dimension_tile(root, "freeform")
        assert.are.equal("1 included", freeform.ao3_filter_hint)
    end)

    it("adopts typed names from a pasted URL and rewrites them on Apply", function()
        local state = fixture_state(
            "https://archiveofourown.org/tags/Time%20Travel/works"
                .. "?work_search%5Bother_tag_names%5D=Fluff%2CAngst")
        assert.are.equal(2, plugin:filterCount(state))
        assert.is_truthy(state.selected.include.tag["Fluff"])

        local url = plugin:filterUrl(state.base_url, state)
        assert.are.equal(
            "https://archiveofourown.org/tags/Time%20Travel/works"
                .. "?work_search%5Bother_tag_names%5D=Angst,Fluff"
                .. "&work_search%5Bsort_column%5D=revised_at",
            url)
    end)

    it("repaints a suggestion window after the list grows", function()
        -- The hint row measures the window first; replacing it with ten names
        -- must drop the cached offsets, or the next paint walks off the end.
        local FilterPage = dofile("plugins/ao3.koplugin/filterpage.lua")
        local Blitbuffer = require("ffi/blitbuffer")
        local panel = FilterPage.suggestionArea{ width = 300, font_size = 20 }
        local bb = Blitbuffer.new(300, 400)

        FilterPage.fillSuggestions(panel, nil,
            { width = 300, font_size = 20, hint = "Type…" })
        panel:paintTo(bb, 0, 0)

        FilterPage.fillSuggestions(panel,
            { "One", "Two", "Three", "Four", "Five", "Six" },
            { width = 300, font_size = 20, on_pick = function() end })
        panel:paintTo(bb, 0, 0)

        FilterPage.fillSuggestions(panel, nil,
            { width = 300, font_size = 20, hint = "No matching tags." })
        panel:paintTo(bb, 0, 0)
        bb:free()
    end)
end)
