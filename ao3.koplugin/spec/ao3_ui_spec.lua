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

    it("measures card heights on builds without TextWidget.getTextHeight", function()
        -- Regression: a physical Kindle on an older KOReader build crashed on
        -- opening the AO3 menu with "attempt to call field 'getTextHeight'".
        local TextWidget = require("ui/widget/textwidget")
        local saved = TextWidget.getTextHeight
        TextWidget.getTextHeight = nil
        local ok, menu_or_err = pcall(open_listing,
            listing_with({ work("1", "Old Build", "A", "Summary.") }))
        TextWidget.getTextHeight = saved
        assert.is_true(ok, menu_or_err)
        assert.is_true(menu_or_err.item_table[1].height > 0)
    end)

    it("opens the menu on builds without mergeTitleBarIntoLayout", function()
        -- The title-bar merge helper is newer than some device builds; the
        -- menu must still render work rows without it.
        local Menu = require("ui/widget/menu")
        local saved = Menu.mergeTitleBarIntoLayout
        Menu.mergeTitleBarIntoLayout = nil
        local ok, menu_or_err = pcall(open_listing,
            listing_with({ work("2", "Old Menu", "B", "Summary.") }))
        Menu.mergeTitleBarIntoLayout = saved
        assert.is_true(ok, menu_or_err)
        assert.is_true(menu_or_err.item_table[1].height > 0)
    end)

    it("opens the menu on debug builds that reject unknown Size.line keys", function()
        -- Older releases have no Size.line.focus_row, and debug builds install
        -- an __index metatable on Size.line that raises for missing keys. The
        -- card must read the key with rawget and fall back to Size.line.thick.
        local Size = require("ui/size")
        local saved_focus_row = rawget(Size.line, "focus_row")
        local saved_mt = getmetatable(Size.line)
        rawset(Size.line, "focus_row", nil)
        setmetatable(Size.line, {
            __index = function(_, key)
                error("Size: this property does not exist: Size.line."
                    .. tostring(key))
            end,
        })
        local ok, menu_or_err = pcall(open_listing,
            listing_with({ work("3", "Debug Build", "C", "Summary.") }))
        rawset(Size.line, "focus_row", saved_focus_row)
        setmetatable(Size.line, saved_mt)
        assert.is_true(ok, menu_or_err)
        assert.is_true(#menu_or_err.item_group > 0)
    end)

    it("rebuilds rows on builds whose Menu never computes page_items", function()
        -- Before 2024.07 Menu._recalculateDimen neither called
        -- setupItemHeights nor set available_height, so page_items stayed nil
        -- and the listing rendered blank. updateItems must build the heights
        -- itself and setupItemHeights must fall back to a height budget.
        local Menu = require("ui/widget/menu")
        local Geom = require("ui/geometry")
        local saved = Menu._recalculateDimen
        Menu._recalculateDimen = function(self, no_recalculate_dimen)
            if no_recalculate_dimen then return end
            local perpage = self.perpage or self.items_per_page_default
            self.perpage = perpage
            self.font_size = self.font_size or Menu.getItemFontSize(perpage)
            self.item_dimen = Geom:new{
                x = 0, y = 0,
                w = self.inner_dimen.w,
                h = math.floor(self.inner_dimen.h / perpage),
            }
            self.page_num = math.max(1,
                math.ceil(#self.item_table / perpage))
        end
        local ok, menu_or_err = pcall(function()
            local menu = open_listing(listing_with({
                work("1", "Old Build One", "A", "Summary."),
                work("2", "Old Build Two", "B", "Summary."),
            }))
            menu.page_items = nil
            menu.available_height = nil
            menu:updateItems(1)
            return menu
        end)
        Menu._recalculateDimen = saved
        assert.is_true(ok, menu_or_err)
        assert.is_true(#menu_or_err.item_group > 0)
        assert.is_true(#menu_or_err.page_items > 0)
    end)

    it("survives builds whose UnderlineContainer lacks the focus API", function()
        -- FocusManager on newer builds calls these item methods; older
        -- UnderlineContainer classes have neither, so the card must report
        -- "no fast repaint" instead of calling a nil method.
        local UnderlineContainer =
            require("ui/widget/container/underlinecontainer")
        local saved_region = UnderlineContainer.getFocusIndicatorRegion
        local saved_repaint = UnderlineContainer.repaintFocusIndicator
        UnderlineContainer.getFocusIndicatorRegion = nil
        UnderlineContainer.repaintFocusIndicator = nil
        local ok, result = pcall(function()
            local menu = open_listing(listing_with(
                { work("4", "Old Underline", "D", "Summary.") }))
            local card = menu.item_group[1]
            return {
                menu = menu,
                region = card:getFocusIndicatorRegion(),
                repainted = card:repaintFocusIndicator(Screen.bb),
            }
        end)
        UnderlineContainer.getFocusIndicatorRegion = saved_region
        UnderlineContainer.repaintFocusIndicator = saved_repaint
        assert.is_true(ok, result)
        assert.is_true(#result.menu.item_group > 0)
        assert.is_nil(result.region)
        assert.is_false(result.repainted)
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
        plugin:showWork({
            id = "1", title = "Work", authors = "A Writer",
            author_names = { "A Writer" }, author_urls = { "/users/a" },
        })
        UIManager.show = old_show

        local menu = plugin.menu
        local item
        for _, row in ipairs(menu.item_table) do
            if row.role == "author" then
                item = row
                break
            end
        end
        assert.is_truthy(item)
        local row
        for _, widget in ipairs(menu.item_group) do
            if widget.entry == item then
                row = widget
                break
            end
        end
        assert.is_truthy(row)
        assert.are.equal("A Writer", row.entry.text)
        assert.are.equal("Author page", row.mandatory_widget.text)
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
