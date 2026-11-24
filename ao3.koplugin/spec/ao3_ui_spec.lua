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
local Size = require("ui/size")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")

local function work(id, title, authors, summary, extra)
    local item = {
        id = id,
        title = title,
        authors = authors,
        summary = summary,
    }
    for key, value in pairs(extra or {}) do item[key] = value end
    return item
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
        -- No summary means no summary widget at all, not an empty one.
        assert.is_nil(menu.item_group[2].summary_widget)
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
        assert.are.equal("by Test Author", card.author_widget.text)
        assert.is_truthy(card.summary_widget)
        assert.is_true(card.title_widget.bold)
        assert.is_true(card.summary_widget.face.size < card.title_widget.face.size)
        assert.is_true(card.author_widget.face.size < card.title_widget.face.size)
        assert.are.equal("smallinfofont", card.author_widget.face.orig_font)
        assert.are.equal("smallinfofont", card.summary_widget.face.orig_font)
        assert.are.same(Blitbuffer.COLOR_GRAY_6, card.author_widget.fgcolor)
        assert.are.same(Blitbuffer.COLOR_GRAY_6, card.summary_widget.fgcolor)

        local line_h = card.summary_widget.line_height_px
        assert.is_true(card.summary_widget.lines_per_page <= 3)
        assert.is_true(card.summary_widget.height <= 3 * line_h + 2)
        -- The row is measured from what the widget actually draws, so the
        -- card's hairline never cuts through the last line of the blurb.
        assert.is_true(card.summary_widget:getSize().h
            <= menu.ao3_metrics.summary_h)
        assert.is_true(card.content_group:getSize().h
            <= card.dimen.h - card.linesize)
        -- The summary overflows three lines and gets an ellipsis from the
        -- TextBoxWidget, so the card never becomes an unbounded wall of text.
        assert.is_truthy(card.summary_widget.line_with_ellipsis)
    end)

    it("puts the byline beside a short title and under a long one", function()
        local short = work("1", "Short", "Writer", "A summary.")
        local long = work("2", string.rep("A very long title ", 6), "Writer",
            "A summary.")
        local menu = open_listing(listing_with({ short, long }))

        -- Same author and summary: the only difference is whether the byline
        -- shared the title's line or paid for one of its own.
        local metrics = menu.item_group[1].ao3_metrics
        assert.are.equal(menu.item_table[1].height + metrics.meta_h
            + Size.span.vertical_default, menu.item_table[2].height)
    end)

    it("shares a line between fandom and relationships when they fit", function()
        local compact = work("1", "Compact", "Writer", "A summary.", {
            fandoms = "Fandom",
            relationships = "A/B",
        })
        local wide = work("2", "Wide", "Writer", "A summary.", {
            fandoms = string.rep("Fandom name ", 8),
            relationships = string.rep("Someone/Someone ", 8),
        })
        local menu = open_listing(listing_with({ compact, wide }))

        assert.is_true(menu.item_table[2].height > menu.item_table[1].height)
    end)

    it("leaves air above the first line of every card", function()
        local menu = open_listing(listing_with({ work("1", "Padded", "Writer",
            "A summary.") }))
        local card = menu.item_group[1]
        -- The card begins with a spacer, so neither the title nor the symbol
        -- grid sits flush against the separator of the card above.
        local spacer = card.content_group[1]
        assert.is_truthy(spacer.width)
        assert.is_true(spacer.width > 0)
    end)

    it("measures each card for exactly the height it draws", function()
        local menu = open_listing(listing_with({
            work("1", "Short", "Writer", "A summary."),
            work("2", "Long", "Writer", string.rep("word ", 100)),
            work("3", "Tagged", "Writer", "A summary.", {
                fandoms = "Fandom One, Fandom Two",
                relationships = "A/B",
                tag_list = { "One", "Two", "Three", "Four" },
                rating_key = "rating-teen",
                words = "4,913",
                chapters = "1/1",
                updated = "4 Jul 2020",
            }),
        }))
        menu:paintTo(Screen.bb, 0, 0)
        for _, card in ipairs(menu.item_group) do
            assert.are.equal(card.content_group:getSize().h + card.linesize,
                card.entry.height)
        end
    end)

    it("fits at least three works on a page with the tags folded", function()
        local items = {}
        for i = 1, 5 do
            items[i] = work(tostring(i), "Work " .. i, "Author " .. i,
                "A summary.")
        end
        local menu = open_listing(listing_with(items))
        assert.is_true(#menu.page_items[1] >= 3)
    end)

    it("closes the last menu without touching the closed widget", function()
        -- Older builds free the menu inside Menu.onClose. The landing page's
        -- X is the one close that takes this path; reading the footer arrow
        -- afterwards raised an error and took KOReader down with the menu.
        local Menu = require("ui/widget/menu")
        local saved = Menu.onClose
        local calls = 0
        Menu.onClose = function(menu_self)
            calls = calls + 1
            menu_self.item_table_stack = {}
            menu_self.page_return_arrow = {
                enableDisable = function() error("closed widget touched") end,
            }
            return true
        end
        local menu = open_listing(listing_with(
            { work("1", "Closed", "Writer", "A summary.") }))
        menu.item_table_stack = {}
        local ok, err = pcall(function() menu:onClose() end)
        Menu.onClose = saved
        assert.is_true(ok, err)
        assert.are.equal(1, calls)
    end)

    it("returns to the file manager when the plugin menu was the last window", function()
        -- Opening a work closes KOReader's file manager while the plugin menu
        -- stays beneath the reader. Closing that menu must not leave UIManager
        -- with an empty stack, or KOReader quits with it.
        local FileManager = require("apps/filemanager/filemanager")
        local saved_show = FileManager.showFiles
        local saved_stack = UIManager._window_stack
        local shown = 0
        FileManager.showFiles = function() shown = shown + 1 end
        UIManager._window_stack = {}
        local ok, err = pcall(function() plugin:onMenuClosed() end)
        UIManager._window_stack = saved_stack
        FileManager.showFiles = saved_show
        assert.is_true(ok, err)
        assert.are.equal(1, shown)
    end)

    it("leaves the window beneath alone when one is still open", function()
        local FileManager = require("apps/filemanager/filemanager")
        local saved_show = FileManager.showFiles
        local saved_stack = UIManager._window_stack
        local shown = 0
        FileManager.showFiles = function() shown = shown + 1 end
        UIManager._window_stack = { { widget = {} } }
        local ok, err = pcall(function() plugin:onMenuClosed() end)
        UIManager._window_stack = saved_stack
        FileManager.showFiles = saved_show
        assert.is_true(ok, err)
        assert.are.equal(0, shown)
    end)

    it("marks a work with AO3's symbols, fandoms, ships and numbers", function()
        local tagged = work("1", "Tagged", "Writer", "A summary.", {
            rating_key = "rating-teen",
            warning_key = "warning-yes",
            category_key = "category-slash",
            complete_key = "complete-yes",
            fandoms = "Fandom One, Fandom Two",
            relationships = "A/B",
            words = "4,913",
            chapters = "1/1",
            updated = "4 Jul 2020",
        })
        local menu = open_listing(listing_with({ tagged }))
        local card = menu.item_group[1]

        -- Two cells square, drawn in ink: rating, warning, category, state.
        assert.is_truthy(card.symbol_grid)
        assert.are.equal(3, #card.symbol_grid)
        local texts = {}
        local function walk(widget)
            if widget.text and widget.text ~= "" then texts[#texts + 1] = widget.text end
            for _, child in ipairs(widget) do walk(child) end
        end
        walk(card.symbol_grid)
        assert.is_truthy(table.concat(texts, "|"):find("T", 1, true))
        assert.is_truthy(table.concat(texts, "|"):find("!", 1, true))
        assert.is_truthy(table.concat(texts, "|"):find("✓", 1, true))

        assert.are.equal("Fandom One, Fandom Two", card.fandom_widget.text)
        assert.are.equal("A/B", card.ships_widget.text)
        assert.are.same(Blitbuffer.COLOR_GRAY_6, card.fandom_widget.fgcolor)

        -- Labels in Slate, values in bold ink.
        local labels, values = {}, {}
        for _, child in ipairs(card.stats_widget) do
            if child.text == "Words" or child.text == "Chapters"
                    or child.text == "Updated" then
                labels[#labels + 1] = child.text
                assert.are.same(Blitbuffer.COLOR_DARK_GRAY, child.fgcolor)
            elseif child.text and child.bold then
                values[#values + 1] = child.text
            end
        end
        assert.are.same({ "Words", "Chapters", "Updated" }, labels)
        assert.are.same({ "4,913", "1/1", "4 Jul 2020" }, values)
    end)

    it("folds the tags to one line and opens them on a tap without opening the work", function()
        local Event = require("ui/event")
        local Geom = require("ui/geometry")
        local tags = {}
        for i = 1, 12 do tags[i] = "Tag number " .. i end
        local tagged = work("1", "Tagged", "Writer", "A summary.", {
            tag_list = tags,
            rating_key = "rating-general-audience",
            warning_key = "warning-no",
            category_key = "category-gen",
            complete_key = "complete-yes",
        })
        local opened
        plugin.showWork = function(_, selected) opened = selected end
        local menu = open_listing(listing_with({ tagged }))
        menu:paintTo(Screen.bb, 0, 0)

        local card = menu.item_group[1]
        assert.is_truthy(card.tags_widget)
        -- The closed box is one line of whole tags plus the count of the rest.
        local closed = card.tags_text_widget.text
        assert.is_truthy(closed:find("more", 1, true))
        assert.is_true(#closed < 120)

        local height = menu.item_table[1].height
        local depth = #menu.item_table_stack
        local tag_area = card.tags_widget
        local pos = Geom:new{
            x = tag_area.dimen.x + 5,
            y = tag_area.dimen.y + 5,
        }
        -- The real gesture path: the tap reaches the tag box through the
        -- card's widget tree, so the box consumes it before the row does.
        assert.is_true(card:handleEvent(Event:new("Gesture",
            { ges = "tap", pos = pos, time = 0 })))
        assert.is_true(menu.item_table[1].tags_expanded)
        assert.is_nil(opened)
        assert.is_true(menu.item_table[1].height > height)
        assert.are.equal(table.concat(tags, ", "),
            menu.item_group[1].tags_text_widget.text)

        -- The menu still holds one card and one page: the tap did not push a
        -- screen, so Back still returns to the listing that opened the work.
        assert.are.equal(1, #menu.item_table)
        assert.are.equal(depth, #menu.item_table_stack)

        -- A second tap on the box folds it again.
        menu:paintTo(Screen.bb, 0, 0)
        local open_area = menu.item_group[1].tags_widget
        assert.is_true(menu.item_group[1]:handleEvent(Event:new("Gesture",
            { ges = "tap", time = 0,
                pos = Geom:new{ x = open_area.dimen.x + 5,
                    y = open_area.dimen.y + 5 } })))
        assert.is_false(menu.item_table[1].tags_expanded)

        -- A tap outside the box still opens the work.
        menu:paintTo(Screen.bb, 0, 0)
        assert.is_true(menu.item_group[1]:handleEvent(Event:new("Gesture",
            { ges = "tap", pos = Geom:new{ x = 150, y = 75 }, time = 0 })))
        assert.are.equal(tagged, opened)
    end)

    it("starts the tag box open when the setting says so", function()
        local tagged = work("1", "Tagged", "Writer", "A summary.", {
            tag_list = { "friendship", "slow burn", "fix-it" },
            rating_key = "rating-general-audience",
        })
        plugin.prefs = { tags_expanded = true }
        local menu = open_listing(listing_with({ tagged }))
        assert.is_true(menu.item_table[1].tags_expanded)
        local text = menu.item_group[1].tags_text_widget
        assert.are.equal("friendship, slow burn, fix-it", text.text)
        assert.is_nil(menu.item_group[1].tags_text_widget.line_with_ellipsis)
    end)

    it("keeps title and summary inside one content group with no inner divider", function()
        local menu = open_listing(listing_with(
            { work("1", "Test Work", "Test Author", "A summary.") }
        ))

        local card = menu.item_group[1]
        assert.are.equal(card._underline_container, card._focus_indicator)
        assert.is_truthy(card.content_group)
        assert.is_true(#card.content_group >= 2)
        -- Only the card's bottom underline is present: every child of the
        -- content group is text or spacing, never a LineWidget.
        for _, child in ipairs(card.content_group) do
            assert.is_nil(child.is_line_widget)
        end
    end)
end)

describe("AO3 fandom index", function()
    local plugin

    -- The shipped letter files are not needed to test the presentation: the
    -- paging source is stubbed, so only the index and its rows are built.
    local function open_letter(names, letter)
        plugin.loadFandomLetter = function(_, _, _, offset)
            local rows = {}
            for i, name in ipairs(names) do
                rows[i] = { text = name, mandatory = tostring(i), ao3_fandom = true }
            end
            return rows, {
                entries = rows,
                total = #names,
                offset = offset or 0,
                page_size = 100,
            }
        end
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        plugin.menu = menu
        plugin:showFandomLetterPage({
            index = 1,
            name = "Test Media",
            letters = { "A", "B", "#" },
        }, letter or "A", 0, false)
        UIManager.show = old_show
        return menu
    end

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
    end)

    after_each(function()
        plugin.menu = nil
    end)

    it("opens a category straight into its letter index, not a page of letters", function()
        local opened
        plugin.showFandomLetterPage = function(_, category, letter, offset, replace)
            opened = { category = category, letter = letter, offset = offset, replace = replace }
        end
        local rows = plugin:fandomRows({
            { index = 1, name = "Test Media", count = 5, letters = { "C", "D" } },
        })
        rows[2].action()
        assert.are.equal("Test Media", opened.category.name)
        assert.are.equal("C", opened.letter)
        assert.are.equal(0, opened.offset)
        assert.is_false(opened.replace)
    end)

    it("lays the whole alphabet out as one index with the open letter inverted", function()
        local letters = {}
        for i = string.byte("A"), string.byte("Z") do
            letters[#letters + 1] = string.char(i)
        end
        letters[#letters + 1] = "#"

        local picked
        local strip = plugin:fandomLetterIndex({ letters = letters }, "C", 600,
            function(letter) picked = letter end)
        assert.is_truthy(strip)
        -- Air above and below, and three shelves of nine.
        assert.are.equal(5, #strip)
        for shelf = 2, 4 do
            assert.are.equal(11, #strip[shelf])
        end

        local open_cell = strip[2][4]
        assert.are.equal("C", open_cell[1][1][1].text)
        assert.are.same(Blitbuffer.COLOR_BLACK, open_cell[1].background)
        assert.are.same(Blitbuffer.COLOR_WHITE, strip[2][2][1].background)
        assert.are.same(Blitbuffer.COLOR_WHITE, strip[3][2][1].background)

        strip[3][4].onTap()
        assert.are.equal("L", picked)
    end)

    it("pins the letter index above every page of a letter", function()
        local names = {}
        for i = 1, 40 do
            names[i] = "Fandom " .. i
        end
        local menu = open_letter(names, "B")
        local strip = menu.item_table[1].ao3_tabs
        assert.is_truthy(strip)
        assert.is_true(menu.item_table[1].ao3_sticky)
        assert.are.equal(strip, menu.item_group[1])
        -- The strip is the open letter's marker, not a paged row.
        assert.are.equal("Find in this letter…", menu.item_table[2].text)
        for _, indices in ipairs(menu.page_items) do
            for _, index in ipairs(indices) do
                assert.are_not.equal(1, index)
            end
        end

        assert.is_true(#menu.page_items > 1)
        menu:onNextPage()
        assert.are.equal(strip, menu.item_group[1])
        -- Page two starts on a record, not on the search row.
        local first_row = menu.item_group[2]
        assert.is_truthy(first_row.entry)
        assert.is_truthy(first_row.entry.text:match("^Fandom %d+$"))
    end)

    it("gives the search row a magnifier", function()
        local menu = open_letter({ "Short Fandom" }, "A")
        local row = menu.item_group[2]
        assert.are.equal("Find in this letter…", row.entry.text)
        assert.are.equal("search", row.entry.ao3_icon)
        assert.is_truthy(row.icon_widget)
        assert.is_true(row.icon_widget:getSize().w > 0)
    end)

    it("gives a long fandom name two lines and then an ellipsis", function()
        local menu = open_letter({
            "Short Fandom",
            string.rep("word ", 80),
        }, "A")

        -- Strip, search row, then the two records.
        local single = menu.item_table[3]
        local double = menu.item_table[4]
        assert.are.equal("Short Fandom", single.text)
        assert.is_true(double.height > single.height)

        local row = menu.item_group[4]
        assert.is_truthy(row.fandom_name_widget)
        assert.is_true(row.fandom_name_widget.lines_per_page <= 2)
        -- Two lines plus the descender overflow the face actually draws. The
        -- widget's own height is adjusted down to whole line boxes, so the
        -- record's allotted metric is the yardstick.
        assert.is_true(row.fandom_name_widget:getSize().h
            <= menu.ao3_metrics.fandom_name_h)
        assert.is_truthy(row.fandom_name_widget.line_with_ellipsis)
        assert.are.equal("2", row.fandom_count_widget.text)
    end)
end)


describe("AO3 fandom search", function()
    local plugin

    local category = { index = 1, name = "Test Media", letters = { "A", "C", "#" } }

    local function records(count)
        local rows = {}
        for i = 1, count do
            rows[i] = {
                text = "Cyber Fandom " .. i,
                mandatory = tostring(i),
                ao3_fandom = true,
                action = function() end,
            }
        end
        return rows
    end

    -- The shipped letter files are not needed to test the presentation: the
    -- search source is stubbed, so only the result rows and their paging are
    -- built here.
    local function open_search(count, extra)
        extra = extra or {}
        plugin.searchFandomLetter = function()
            return records(count), {
                entries = {},
                total = extra.total or count,
                offset = extra.offset or 0,
                page_size = 100,
                next_offset = extra.next_offset,
                query = "cyber",
            }
        end
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        plugin.menu = menu
        plugin:showFandomSearch(category, "C", "cyber", extra.offset or 0, extra.replace)
        UIManager.show = old_show
        return menu
    end

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
    end)

    after_each(function()
        plugin.menu = nil
    end)

    it("lists every match under the letter strip instead of jumping to one hit", function()
        local menu = open_search(3)

        -- Strip, the search row, then the three records it found.
        assert.is_true(menu.item_table[1].ao3_sticky)
        local search_row = menu.item_table[2]
        assert.are.equal("Find in this letter…", search_row.text)
        assert.are.equal("“cyber”", search_row.mandatory)
        assert.are.equal("search", search_row.ao3_icon)
        for i = 1, 3 do
            local row = menu.item_table[2 + i]
            assert.are.equal("Cyber Fandom " .. i, row.text)
            assert.is_true(row.ao3_fandom)
        end
        assert.are.equal("Test Media · 3 matches", menu.ao3_title)
    end)

    it("says one match rather than one matches", function()
        local menu = open_search(1)
        assert.are.equal("Test Media · 1 match", menu.ao3_title)
    end)

    it("draws the magnifier beside the search label", function()
        local menu = open_search(2)
        local row = menu.item_group[2]
        assert.are.equal("search", row.entry.ao3_icon)
        assert.is_truthy(row.icon_widget)
        assert.is_true(row.icon_widget:getSize().w > 0)
        -- The mark takes its space from the label, not from the count column.
        assert.is_true(row.title_widget.max_width < row.content_width)
    end)

    it("offers the rest of the matches as pages of the same search", function()
        local menu = open_search(100, { total = 250, offset = 100, next_offset = 200 })
        local count = #menu.item_table
        assert.are.equal("← Previous 100 matches", menu.item_table[count - 1].text)
        assert.are.equal("Next 100 matches →", menu.item_table[count].text)

        local asked
        plugin.showFandomSearch = function(_, _, letter, query, offset, replace)
            asked = { letter = letter, query = query, offset = offset, replace = replace }
        end
        menu.item_table[count].action()
        assert.are.equal("C", asked.letter)
        assert.are.equal("cyber", asked.query)
        assert.are.equal(200, asked.offset)
        assert.is_true(asked.replace)
    end)

    it("pushes a first search and replaces it when refining", function()
        local menu = open_search(2)
        assert.are.equal(1, #menu.item_table_stack)

        plugin:showFandomSearch(category, "C", "cyber", 0, true)
        assert.are.equal(1, #menu.item_table_stack)

        plugin:showFandomSearch(category, "C", "cyber", 0, false)
        assert.are.equal(2, #menu.item_table_stack)
    end)

    it("keeps the term in the search row when refining it", function()
        local menu = open_search(2)
        local asked
        plugin.findFandomDialog = function(_, _, letter, replace, current)
            asked = { letter = letter, replace = replace, current = current }
        end
        menu.item_table[2].action()
        assert.are.equal("C", asked.letter)
        assert.is_true(asked.replace)
        assert.are.equal("cyber", asked.current)
    end)

    it("says so and stays put when nothing matches", function()
        local InfoMessage = require("ui/widget/infomessage")
        plugin.searchFandomLetter = function()
            return {}, {
                entries = {}, total = 0, offset = 0, page_size = 100, query = "zzz",
            }
        end
        plugin.menu = nil
        local menu = plugin:ensureMenu()
        plugin.menu = menu

        local shown
        local old_show = UIManager.show
        UIManager.show = function(_, widget) shown = widget end
        local ok, err = pcall(function()
            plugin:showFandomSearch(category, "C", "zzz", 0, false)
        end)
        UIManager.show = old_show

        assert.is_true(ok, err)
        assert.is_truthy(shown)
        assert.are.equal(InfoMessage, getmetatable(shown).__index)
        assert.is_truthy(shown.text:find("No fandom under C", 1, true))
        -- Nothing was pushed or replaced: the reader stays where they were.
        assert.are.equal(0, #menu.item_table_stack)
        assert.are.equal("AO3", menu.ao3_title)
    end)

    it("searches the letter the dialog was opened from", function()
        local opened
        local old_show = UIManager.show
        UIManager.show = function(_, widget) opened = widget end
        plugin:findFandomDialog(category, "C")
        UIManager.show = old_show

        assert.is_truthy(opened)
        assert.are.equal("", opened.input)
        assert.is_nil(opened.description)

        opened.getInputValue = function() return "  Cyber  " end
        local asked
        plugin.showFandomSearch = function(_, _, letter, query, offset, replace)
            asked = { letter = letter, query = query, offset = offset, replace = replace }
        end
        local old_close = UIManager.close
        UIManager.close = function() end
        opened.buttons[1][2].callback()
        UIManager.close = old_close

        assert.are.equal("C", asked.letter)
        assert.are.equal("Cyber", asked.query)
        assert.are.equal(0, asked.offset)
        assert.is_nil(asked.replace)
    end)
end)


describe("AO3 author search", function()
    local plugin

    -- Results as parsePeopleSearch returns them; the URLs are the profile
    -- links AO3 gives each hit.
    local function matches(rows)
        local data = { items = {} }
        for i, row in ipairs(rows) do
            data.items[i] = {
                name = row[1],
                user = row[2],
                url = "https://archiveofourown.org/users/" .. row[2],
            }
        end
        return data
    end

    local query_url = "https://archiveofourown.org/people/search?people_search%5Bq%5D=harbor"

    local function open_matches(query, data, url, replace)
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        plugin.menu = menu
        plugin:showAuthorMatches(query, data, url or query_url, replace)
        UIManager.show = old_show
        return menu
    end

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
    end)

    after_each(function()
        plugin.menu = nil
    end)

    it("opens the author when the name is exact", function()
        local opened
        plugin.showAuthor = function(_, name, url)
            opened = { name = name, url = url }
        end

        plugin:showAuthorMatches("harborlight", matches({
            { "harborlight", "harborlight" },
            { "harborlight_2", "harborlight_2" },
        }), query_url, false)

        assert.are.equal("harborlight", opened.name)
        assert.are.equal(
            "https://archiveofourown.org/users/harborlight", opened.url)
    end)

    it("recognises an exact login whose display name is a pseud", function()
        local opened
        plugin.showAuthor = function(_, name) opened = name end

        plugin:showAuthorMatches("harbor_lights", matches({
            { "Harbor Lights", "harbor_lights" },
            { "harborlight", "harborlight" },
        }), query_url, false)

        assert.are.equal("Harbor Lights", opened)
    end)

    it("lists the matches when the name is only part of them", function()
        local menu = open_matches("harbor", matches({
            { "harborlight", "harborlight" },
            { "Harbor Lights", "harbor_lights" },
        }))

        assert.are.equal("Authors matching “harbor”", menu.ao3_title)
        local search_row = menu.item_table[1]
        assert.are.equal("Search authors…", search_row.text)
        assert.are.equal("“harbor”", search_row.mandatory)
        assert.is_truthy(search_row.ao3_icon)

        assert.are.equal("harborlight", menu.item_table[2].text)
        assert.is_nil(menu.item_table[2].mandatory)
        assert.are.equal("Harbor Lights", menu.item_table[3].text)
        assert.are.equal("harbor_lights", menu.item_table[3].mandatory)
    end)

    it("opens the author tapped in the list", function()
        local menu = open_matches("harbor", matches({
            { "harborlight", "harborlight" },
            { "Harbor Lights", "harbor_lights" },
        }))
        local opened
        plugin.showAuthor = function(_, name, url)
            opened = { name = name, url = url }
        end

        menu.item_table[3].action()
        assert.are.equal("Harbor Lights", opened.name)
        assert.are.equal(
            "https://archiveofourown.org/users/harbor_lights", opened.url)
    end)

    it("does not jump into an author while paging the results", function()
        local opened
        plugin.showAuthor = function() opened = true end

        local menu = open_matches("harborlight", matches({
            { "harborlight", "harborlight" },
        }), query_url .. "&page=2")

        assert.is_nil(opened)
        assert.are.equal("Authors matching “harborlight”", menu.ao3_title)
    end)

    it("pages the list with the next and previous links", function()
        local asked
        local menu = open_matches("harbor", {
            items = {
                { name = "harborlight", user = "harborlight",
                  url = "https://archiveofourown.org/users/harborlight" },
            },
            next_url = query_url .. "&page=2",
            prev_url = query_url,
        })
        plugin.searchAuthorsAt = function(_, query, url, replace)
            asked = { query = query, url = url, replace = replace }
        end

        local count = #menu.item_table
        assert.are.equal("← Previous authors", menu.item_table[count - 1].text)
        assert.are.equal("Next authors →", menu.item_table[count].text)

        menu.item_table[count].action()
        assert.are.equal("harbor", asked.query)
        assert.are.equal(query_url .. "&page=2", asked.url)
        assert.is_true(asked.replace)
    end)

    it("falls back to opening the name when AO3 returns no matches", function()
        local opened
        plugin.showAuthor = function(_, name, url)
            opened = { name = name, url = url }
        end

        plugin:showAuthorMatches("harborlight", { items = {} }, query_url, false)

        assert.are.equal("harborlight", opened.name)
        assert.are.equal(
            "https://archiveofourown.org/users/harborlight/works", opened.url)
    end)

    it("searches a name and opens a pasted profile link", function()
        local searched, opened
        plugin.searchAuthors = function(_, query) searched = query end
        plugin.showAuthor = function(_, name) opened = name end

        local old_show, old_close = UIManager.show, UIManager.close
        local dialog
        UIManager.show = function(_, widget) dialog = widget end
        UIManager.close = function() end
        plugin:authorDialog("harbor")
        assert.are.equal("harbor", dialog.input)

        dialog.getInputValue = function() return "harborlight" end
        dialog.buttons[1][2].callback()
        assert.are.equal("harborlight", searched)
        assert.is_nil(opened)

        dialog.getInputValue = function()
            return "https://archiveofourown.org/users/foo"
        end
        dialog.buttons[1][2].callback()
        assert.are.equal("https://archiveofourown.org/users/foo", opened)

        UIManager.show, UIManager.close = old_show, old_close
    end)
end)


-- Work actions and the account screen are built by their own modules, so they
-- are exercised as widgets: labels, tap targets and the marks that say a
-- state is already on.
local WorkPage = dofile("plugins/ao3.koplugin/workpage.lua")
local AccountPage = dofile("plugins/ao3.koplugin/accountpage.lua")

local function walk(widget, visit)
    visit(widget)
    for _, child in ipairs(widget) do
        walk(child, visit)
    end
end

local function tappables(widget)
    local out = {}
    walk(widget, function(node)
        if node.onTap then out[#out + 1] = node end
    end)
    return out
end

describe("AO3 work actions", function()
    it("lays kudos, bookmark, subscribe and mark for later out in one grid", function()
        local panel = WorkPage.social(570, 19, {}, true, function() end)
        local labels = {}
        for _, area in ipairs(tappables(panel)) do
            local label
            walk(area, function(node)
                if not label and node.text then label = node.text end
            end)
            labels[#labels + 1] = label
        end
        assert.are.same({ "Kudos", "Bookmark", "Subscribe", "Mark for later" },
            labels)
    end)

    it("reports the action id when a button is tapped", function()
        local tapped = {}
        local panel = WorkPage.social(570, 19, {}, true, function(id)
            tapped[#tapped + 1] = id
        end)
        for _, area in ipairs(tappables(panel)) do
            area.onTap()
        end
        assert.are.same({ "kudos", "bookmark", "subscribe", "later" }, tapped)
    end)

    it("marks an action that is already on with KOReader's checkmark", function()
        local panel = WorkPage.social(570, 19, { kudos = true }, true,
            function() end)
        local marked
        walk(panel, function(node)
            if node.text and node.text:find("✓", 1, true) then
                marked = node.text
            end
        end)
        assert.are.equal("Kudos  ✓", marked)
    end)

    it("keeps the buttons in full contrast for a signed-out reader", function()
        local panel = WorkPage.social(570, 19, {}, false, function() end)
        assert.are.equal(4, #tappables(panel))
        local hint
        walk(panel, function(node)
            if node.text and node.text:find("Sign in", 1, true) then
                hint = node.text
            end
        end)
        assert.are.equal("Sign in to your AO3 account to use these.", hint)
    end)
end)

describe("AO3 account screen", function()
    local function build(callbacks)
        callbacks = callbacks or {}
        return AccountPage.build{
            name = "demo_reader",
            width = 570,
            font_size = 19,
            on_list = callbacks.on_list or function() end,
            on_works = callbacks.on_works or function() end,
            on_logout = callbacks.on_logout or function() end,
        }
    end

    it("lists AO3's four account lists, the author page and the way out", function()
        local rows = build()
        local roles = {}
        for _, row in ipairs(rows) do
            roles[#roles + 1] = row.role
        end
        assert.are.same({ "account_hero", "lists_label", "list_bookmarks",
            "list_marked", "list_history", "list_subscriptions",
            "author_label", "works", "session" }, roles)
        assert.are.equal("Works by demo_reader", rows[8].text)
    end)

    it("keeps the name as the headline and names the session", function()
        local hero = build()[1].ao3_static
        local texts = {}
        walk(hero, function(node)
            if node.text and node.text ~= "" then
                texts[#texts + 1] = node.text
            end
        end)
        assert.are.same({ "demo_reader", "Signed in to AO3" }, texts)
    end)

    it("routes each list row to its own AO3 list", function()
        local opened = {}
        local rows = build{ on_list = function(kind)
            opened[#opened + 1] = kind
        end }
        for i = 3, 6 do rows[i].action() end
        assert.are.same({ "bookmarks", "marked", "history", "subscriptions" },
            opened)
    end)

    it("puts one outlined Log out under the lists, not a second primary", function()
        local logged_out = 0
        local rows = build{ on_logout = function() logged_out = logged_out + 1 end }
        local panel = rows[#rows].ao3_static
        local buttons = tappables(panel)
        assert.are.equal(1, #buttons)
        local frame = buttons[1][1]
        assert.is_true(frame.bordersize > 0)
        assert.are.same(Blitbuffer.COLOR_WHITE, frame.background)
        buttons[1].onTap()
        assert.are.equal(1, logged_out)
    end)
end)

describe("AO3 listing navigation", function()
    local plugin

    -- Cards are taller than native rows, so a few dozen works is several pages.
    local function listing_menu(count)
        local items = {}
        for i = 1, count do
            items[i] = work(tostring(i), "Work " .. i, "Author " .. i,
                "A summary.")
        end
        plugin.menu = nil
        local old_show = UIManager.show
        UIManager.show = function() end
        local menu = plugin:ensureMenu()
        plugin.menu = menu
        plugin:showListing(listing_with(items), "Search: test")
        UIManager.show = old_show
        return menu
    end

    local function screen(rows)
        local out = {}
        for i = 1, rows do out[i] = { text = "Row " .. i } end
        return out
    end

    before_each(function()
        plugin = setmetatable({}, { __index = Ao3 })
    end)

    after_each(function()
        plugin.menu = nil
    end)

    it("returns a listing to the page it was left on", function()
        -- Regression: Menu:onClose reopens the parent table through
        -- switchItemTable without an itemnumber, which sets page = 1, so
        -- Back from a work always dropped the reader on the listing's first
        -- page.
        local menu = listing_menu(33)
        assert.is_true(#menu.page_items >= 3)
        menu:onGotoPage(3)

        plugin:pushRows("Work details", screen(3))
        assert.are.equal(1, menu.page)

        menu:onClose()
        assert.are.equal(3, menu.page)
    end)

    it("restores a page at every level of a nested drill-down", function()
        local menu = listing_menu(33)
        menu:onGotoPage(3)

        -- Work details is several screens long on its own; the author screen
        -- sits on top of the page the reader was reading.
        plugin:pushRows("Work details", screen(25))
        assert.is_true(#menu.page_items >= 2)
        menu:onGotoPage(2)
        plugin:pushRows("Author", screen(2))

        menu:onClose()
        assert.are.equal(2, menu.page)
        menu:onClose()
        assert.are.equal(3, menu.page)
    end)

    it("restores the page through the X as well as the Back key", function()
        local menu = listing_menu(33)
        menu:onGotoPage(3)
        plugin:pushRows("Work details", screen(3))
        assert.is_true(menu:onReturn())
        assert.are.equal(3, menu.page)
    end)

    it("does not repaint page 1 when that is where the listing was", function()
        local menu = listing_menu(9)
        local followed = {}
        local saved = menu.onGotoPage
        menu.onGotoPage = function(menu_self, page)
            followed[#followed + 1] = page
            return saved(menu_self, page)
        end

        plugin:pushRows("Work details", screen(3))
        menu:onClose()

        assert.are.equal(1, menu.page)
        assert.are.same({}, followed)
    end)

    it("does not jump past a listing that got shorter", function()
        local menu = listing_menu(33)
        menu:onGotoPage(3)
        plugin:pushRows("Work details", screen(3))

        -- The list that was page 3 long now fits on one page.
        local parent = menu.item_table_stack[#menu.item_table_stack]
        while #parent > 3 do table.remove(parent) end

        local ok, err = pcall(function() menu:onClose() end)
        assert.is_true(ok, err)
        assert.are.equal(1, menu.page)
    end)

    it("keeps paging inside a listing off the navigation stack", function()
        local menu = listing_menu(33)
        menu:onGotoPage(2)
        local depth = #menu.item_table_stack

        -- Fetched pages replace the table in place; the stack (and so the
        -- recorded page) belongs to the screen that was pushed, not the page.
        plugin:replaceRows("Search: test", menu.item_table, 1)

        assert.are.equal(depth, #menu.item_table_stack)
        assert.are.equal(depth, #menu.ao3_page_stack)
    end)
end)
