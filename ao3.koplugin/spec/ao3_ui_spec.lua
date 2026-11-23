-- KOReader busted spec for the AO3 work-list cards.
--
-- From a KOReader checkout with this plugin symlinked into plugins/:
--   ln -s ../../plugins/ao3.koplugin/spec/ao3_ui_spec.lua spec/unit/ao3_ui_spec.lua
--   ./kodev test --busted=--pattern=ao3_ui_spec front
--
-- This spec covers the presentation contract only. It builds the real Menu
-- and work-item widgets so font sizes, row counts and summary clamping are
-- exercised against the same frontend modules the device uses.

require("commonrequire")

local UIManager = require("ui/uimanager")
local Screen = require("device").screen
local Blitbuffer = require("ffi/blitbuffer")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")

local function work(id, title, authors, summary)
    return {
        id = id,
        title = title,
        authors = authors,
        summary = summary,
    }
end

local function listing_with(items, extra)
    local listing = { items = items }
    for key, value in pairs(extra or {}) do
        listing[key] = value
    end
    return listing
end

describe("AO3 work-list cards", function()
    local plugin

    local function open_listing(listing)
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        plugin.menu = menu
        plugin:showListing(listing, "Search: test")
        UIManager.show = old_show
        return menu
    end

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
    end)

    after_each(function()
        plugin.menu = nil
    end)

    it("renders one selectable item per work instead of a title row plus a summary row", function()
        local one = work("1", "Test Work", "Test Author", "A short summary of the story.")
        local two = work("2", "Second Work", "Someone Else", "Another summary.")
        local menu = open_listing(listing_with({ one, two }))

        assert.are.equal(2, #menu.item_table)
        assert.are.equal("Test Work", menu.item_table[1].text)
        assert.are.equal("Test Author", menu.item_table[1].mandatory)
        assert.are.equal(one, menu.item_table[1].ao3_work)
        assert.are.equal("A short summary of the story.", menu.item_table[1].summary)
        assert.are.equal("Second Work", menu.item_table[2].text)
        assert.is_function(menu.item_table[1].action)
    end)

    it("selecting a card opens that card's work", function()
        local first = work("1", "First", "A", "One.")
        local second = work("2", "Second", "B", "Two.")
        local opened
        plugin.showWork = function(_, selected)
            opened = selected
        end

        local menu = open_listing(listing_with({ first, second }))
        menu.item_table[2].action(menu)
        assert.are.equal(second, opened)
    end)

    it("activates a rendered work card on tap", function()
        local chosen = work("91", "Tap target", "Writer", "A readable summary.")
        local opened
        plugin.showWork = function(_, selected) opened = selected end
        local menu = open_listing(listing_with({ chosen }))
        menu:paintTo(Screen.bb, 0, 0)
        local item = menu.item_group[1]
        assert.is_truthy(item[1].dimen)
        item:onTapSelect(nil, { pos = {
            x = item[1].dimen.x + 10,
            y = item[1].dimen.y + 10,
        } })
        assert.are.equal(chosen, opened)
    end)

    it("keeps a short summary intact and bounds a long one for three lines", function()
        local short = work("1", "Short", "A", "A short summary of the story.")
        local long = work("2", "Long", "B", string.rep("word ", 100))
        local menu = open_listing(listing_with({ short, long }))

        assert.are.equal("A short summary of the story.", menu.item_table[1].summary)
        local summary = menu.item_table[2].summary
        assert.is_truthy(summary:find("…", 1, true))
        assert.is_true(#summary <= 330)
    end)

    it("leaves paging rows as compact, non-work rows", function()
        local menu = open_listing(listing_with(
            { work("1", "Work", "Author", "Summary.") },
            {
                next_url = "https://archiveofourown.org/works?page=2",
                prev_url = "https://archiveofourown.org/works?page=0",
            }
        ))

        assert.are.equal(3, #menu.item_table)
        assert.is_nil(menu.item_table[2].ao3_work)
        assert.are.equal("Next page →", menu.item_table[2].text)
        assert.are.equal("← Previous page", menu.item_table[3].text)
        assert.is_function(menu.item_table[2].action)
        assert.is_true(menu.item_table[2].height < menu.item_table[1].height)
    end)

    it("does not reserve blank summary space for a work without a summary", function()
        local with_summary = work("1", "With Summary", "Author", "A summary.")
        local without_summary = work("2", "Without Summary", "Author", "")
        local menu = open_listing(listing_with({ with_summary, without_summary }))

        assert.is_true(menu.item_table[2].height < menu.item_table[1].height)
        assert.is_true(menu.item_group[2].summary_widget:getSize().h <= 1)
    end)

    it("pages cards without dropping or splitting a work", function()
        local items = {}
        for i = 1, 30 do
            items[i] = work(tostring(i), "Work " .. i, "Author", "Summary " .. i)
        end
        local menu = open_listing(listing_with(items))

        assert.is_true(menu.page_num > 1)
        local seen = 0
        for _, indices in ipairs(menu.page_items) do
            assert.is_true(#indices > 0)
            for _, index in ipairs(indices) do
                assert.are.equal(items[index], menu.item_table[index].ao3_work)
                seen = seen + 1
            end
        end
        assert.are.equal(30, seen)
    end)

    it("pushes the first listing and replaces later pages", function()
        local calls = {}
        plugin.pushRows = function(_, title)
            calls[#calls + 1] = "push:" .. title
        end
        plugin.replaceRows = function(_, title)
            calls[#calls + 1] = "replace:" .. title
        end

        local listing = listing_with({ work("1", "Work", "Author", "Summary.") })
        plugin:showListing(listing, "Search")
        plugin:showListing(listing, "Search", true)

        assert.are.same({ "push:Search", "replace:Search" }, calls)
    end)

    it("keeps compact rows left-aligned with their detail at the right edge", function()
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        plugin:showHome()
        UIManager.show = old_show

        local menu = plugin.menu
        local row = menu.item_group[2] -- "Latest works" + "Newest on AO3"
        assert.are.equal("Latest works", row.entry.text)
        assert.are.equal("Newest on AO3", row.mandatory_widget.text)
        assert.are.equal(row.content_width, row.content_group:getSize().w)
    end)

    it("turns off per-row keyboard shortcut boxes", function()
        local menu = open_listing(listing_with(
            { work("1", "Work", "Author", "Summary.") }
        ))
        assert.is_false(menu.is_enable_shortcut)
    end)

    it("builds one card widget with a bold title, smaller author and a three-line summary", function()
        local summary = string.rep("word ", 100)
        local menu = open_listing(listing_with(
            { work("1", "Test Work", "Test Author", summary) }
        ))

        local card = menu.item_group[1]
        assert.are.equal(menu.item_table[1], card.entry)
        assert.are.equal("Test Work", card.title_widget.text)
        assert.are.equal("Test Author", card.author_widget.text)
        assert.is_truthy(card.summary_widget)
        assert.is_true(card.title_widget.bold)
        assert.is_true(card.summary_widget.face.size < card.title_widget.face.size)
        assert.is_true(card.author_widget.face.size < card.title_widget.face.size)
        assert.are.equal("smallinfofont", card.author_widget.face.orig_font)
        assert.are.equal("smallinfofont", card.summary_widget.face.orig_font)
        assert.are.same(Blitbuffer.COLOR_GRAY_6, card.author_widget.fgcolor)
        assert.are.same(Blitbuffer.COLOR_GRAY_6, card.summary_widget.fgcolor)

        local line_h = card.summary_widget.line_height_px
        assert.is_true(card.summary_widget.height >= 2 * line_h)
        assert.is_true(card.summary_widget.height <= 3 * line_h)
        -- The summary overflows three lines and gets an ellipsis from the
        -- TextBoxWidget, so the card never becomes an unbounded wall of text.
        assert.is_truthy(card.summary_widget.line_with_ellipsis)
    end)

    it("keeps title and summary inside one content group with no inner divider", function()
        local menu = open_listing(listing_with(
            { work("1", "Test Work", "Test Author", "A summary.") }
        ))

        local card = menu.item_group[1]
        assert.are.equal(card._underline_container, card._focus_indicator)
        assert.is_truthy(card.content_group)
        assert.is_true(#card.content_group >= 3)
        -- Only the card's bottom underline is present: every child of the
        -- content group is text or spacing, never a LineWidget.
        for _, child in ipairs(card.content_group) do
            assert.is_nil(child.is_line_widget)
        end
    end)
end)
