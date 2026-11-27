--[[--
The filter screen of a work listing.

AO3 puts its filter sidebar in the same HTML as the results, so KO3 can offer
the facets the page already carries without a second request. This module only
draws that form: a Sort tile, a two-up grid of dimension tiles, the facets of
the chosen dimension as native rows, and a sort page built from the page's own
select. main.lua owns the selection, the URL and the one request Apply makes.

The root borrows the landing page's grammar (DESIGN.md): quiet section labels,
7px tiles with a 1px ink border, one bold noun and one grey hint. The dimension
page is a list of facets and stays native rows; the sort page is native rows
too. The one solid bar is Apply, because committing the choice is what the
screen exists for.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Screen = require("device").screen
local ScrollableContainer = require("ui/widget/container/scrollablecontainer")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template

local SOURCE = debug.getinfo(1, "S").source:sub(2)
local Uikit = dofile((SOURCE:gsub("filterpage%.lua$", "uikit.lua")))

local FilterPage = {}

-- The tiles' symbols, in the same 24x24 stroke style as the landing page's.
-- Character and both tag dimensions reuse the icons the app already ships.
local DIMENSION_ICONS = {
    rating = "star",
    archive_warning = "alert",
    category = "layers",
    fandom = "book",
    character = "user",
    relationship = "heart",
    freeform = "tag",
    tag = "tag",
    complete = "complete-no",
    crossover = "layers",
}

-- The dimension page's fixed header: one "Show" label and the two side rows.
-- Facet rows start after it, so an in-place rebuild can keep its place.
FilterPage.DIMENSION_HEADER_ROWS = 3

-- 1,889,081. Facet counts arrive as numbers; the page prints them the way
-- AO3 does, so a row's right column stays scannable.
function FilterPage.formatCount(count)
    local text = tostring(count or "")
    if not text:match("^%d+$") then return text end
    local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    return (grouped:gsub("^,", ""))
end

-- The checkmark the app already uses on work actions and tabs, in the row's
-- value column: states line up down the page and a long tag name never
-- swallows its own mark.
function FilterPage.value(facet, checked)
    local count = facet.count and FilterPage.formatCount(facet.count) or nil
    if checked then
        return count and ("\u{2713} " .. count) or "\u{2713}"
    end
    return count
end

function FilterPage.section_label(text, width, font_size, top)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = top or Size.padding.large }
    group[#group + 1] = Uikit.label(text, width, font_size)
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = group:getSize().h },
        group,
    }
end

local function lineHeight(face, bold)
    if TextWidget.getTextHeight then
        local ok, h = pcall(TextWidget.getTextHeight, "Ag", face, bold)
        if ok and h then return h end
    end
    local probe = TextWidget:new{ text = "Ag", face = face, bold = bold }
    local h = probe:getSize().h
    if probe.free then probe:free() end
    return h
end

-- An icon from assets/icons/. A build without SVG simply leaves the text-only
-- tile intact, like the landing page.
local function icon(o, name, size)
    if not o.icons_dir or not name then return nil end
    local ok, widget = pcall(ImageWidget.new, ImageWidget, {
        file = o.icons_dir .. name .. ".svg",
        width = size,
        height = size,
        alpha = true,
    })
    if ok and widget then return widget end
end

local function hintText(included, excluded)
    if included > 0 and excluded > 0 then
        return T(_("%1 included · %2 excluded"), included, excluded)
    elseif included > 0 then
        return T(_("%1 included"), included)
    elseif excluded > 0 then
        return T(_("%1 excluded"), excluded)
    end
    return _("None yet")
end

local function optionLabel(options, value)
    for _, option in ipairs(options or {}) do
        if option.value == value then return option.label end
    end
    return value
end

-- "Date Updated · Descending", or just the column when the page has no
-- direction control (AO3's bookmark sort is descending only).
function FilterPage.sortSummary(sort)
    if not sort then return nil end
    local label = optionLabel(sort.columns, sort.column)
    if not label or label == "" then label = _("Default") end
    if sort.directions and sort.direction then
        return T(_("%1 · %2"), label, optionLabel(sort.directions, sort.direction))
    end
    return label
end

-- A card in the catalogue's tile grammar: white paper, 1px ink border, 7px
-- radius, an icon beside the bold name and one grey hint underneath. Fixed
-- height, so a grid row aligns and the Apply bar stays on the page.
local function tile(entry, width, height, o)
    local pad = Size.padding.large
    local border = Size.border.default
    local inner_w = math.max(1, width - 2 * (pad + border))
    local inner_h = math.max(1, height - 2 * (pad + border))
    local mark_size = Screen:scaleBySize(24)
    local mark = icon(o, entry.icon, mark_size)
    local mark_w = mark and (mark_size + Size.span.horizontal_default) or 0

    local top = HorizontalGroup:new{ align = "center" }
    if mark then
        top[#top + 1] = mark
        top[#top + 1] = HorizontalSpan:new{ width = Size.span.horizontal_default }
    end
    top[#top + 1] = TextWidget:new{
        text = entry.text,
        face = Font:getFace("smallinfofont", o.font_size),
        bold = true,
        max_width = math.max(1, inner_w - mark_w),
    }

    local content = VerticalGroup:new{ align = "left" }
    content[#content + 1] = top
    if entry.hint then
        content[#content + 1] = VerticalSpan:new{
            width = Size.span.vertical_default,
        }
        content[#content + 1] = TextWidget:new{
            text = entry.hint,
            face = Font:getFace("smallinfofont", o.font_size - 5),
            -- The work card's detail ink, not the paler chrome grey.
            fgcolor = Uikit.CARD_DETAIL,
            max_width = inner_w,
        }
    end

    local frame = FrameContainer:new{
        bordersize = border,
        color = Blitbuffer.COLOR_BLACK,
        radius = Size.radius.button,
        background = Blitbuffer.COLOR_WHITE,
        padding = pad,
        LeftContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            content,
        },
    }
    return Uikit.tapArea(frame, width, height, entry.action)
end

local function tileHeight(o)
    local pad = Size.padding.large
    local border = Size.border.default
    local measured = 2 * (pad + border)
        + math.max(Screen:scaleBySize(24),
            lineHeight(Font:getFace("smallinfofont", o.font_size), true))
        + Size.span.vertical_default
        + lineHeight(Font:getFace("smallinfofont", o.font_size - 5), false)
    -- Comfortable at the reference, measured from the reader's own fonts.
    return math.max(Screen:scaleBySize(72), measured)
end

-- `dimensions` are the facets the page carried, one entry per AO3 dimension
-- with its include list and exclude list already split. `selected_count(action,
-- type)` is read per tile so a returned-to root page can be rebuilt with fresh
-- hints.
function FilterPage.build_root(o)
    local rows = {}
    local height = tileHeight(o)
    local gap = Size.span.horizontal_default
    local tile_w = math.floor((o.width - gap) / 2)
    local first_group = true

    local function addLabel(text, role)
        rows[#rows + 1] = {
            ao3_static = Uikit.padded(FilterPage.section_label(
                text, o.width, o.font_size,
                first_group and Size.padding.default or Size.padding.large)),
            role = role,
            keep_with_next = true,
        }
        first_group = false
    end

    -- Sort is one full-width tile above the facets, and only when the page
    -- itself offers a sort select.
    if o.sort then
        addLabel(_("Sort"), "filter_sort_label")
        local summary = FilterPage.sortSummary(o.sort)
        local entry = {
            text = _("Sort by"),
            hint = summary,
            icon = "sort",
            action = o.on_sort,
        }
        rows[#rows + 1] = {
            ao3_static = Uikit.padded(tile(entry, o.width, height, o)),
            role = "filter_sort",
            ao3_tile = true,
            ao3_filter_hint = summary,
            text = entry.text,
            action = entry.action,
        }
    end

    addLabel(_("Filters"), "filter_label")

    -- One tile per dimension, in filterDimensions' own order, two to a line.
    -- The pair is one static row, exactly like the landing page's Browse grid;
    -- each tile is its own tap target.
    local descriptors, widgets = {}, {}
    for _, dimension in ipairs(o.dimensions) do
        local included = o.selected_count("include", dimension.key)
        local excluded = o.selected_count("exclude", dimension.key)
        local hint = hintText(included, excluded)
        local entry = {
            text = dimension.label,
            hint = hint,
            icon = DIMENSION_ICONS[dimension.key] or "tag",
            action = function()
                o.on_dimension(dimension.key)
            end,
        }
        descriptors[#descriptors + 1] = {
            text = dimension.label,
            action = entry.action,
            role = "filter_dimension",
            ao3_filter_type = dimension.key,
            ao3_filter_hint = hint,
            ao3_tile = true,
        }
        widgets[#widgets + 1] = entry
    end

    local index = 1
    while index <= #widgets do
        local line = HorizontalGroup:new{ align = "top" }
        local line_tiles = {}
        local left = widgets[index]
        local right = widgets[index + 1]
        if right then
            line[#line + 1] = tile(left, tile_w, height, o)
            line[#line + 1] = HorizontalSpan:new{ width = gap }
            line[#line + 1] = tile(right, tile_w, height, o)
        else
            -- A lone last dimension is one full-width tile, so the grid never
            -- ends on a ragged half-line.
            line[#line + 1] = tile(left, o.width, height, o)
        end
        line_tiles[#line_tiles + 1] = descriptors[index]
        if right then line_tiles[#line_tiles + 1] = descriptors[index + 1] end
        -- Ten pixels between tile rows: entries stay tight inside a line and
        -- the grid keeps the catalogue's air between lines.
        local block = VerticalGroup:new{ align = "left" }
        block[#block + 1] = Uikit.padded(line)
        block[#block + 1] = VerticalSpan:new{ width = gap }
        rows[#rows + 1] = {
            ao3_static = block,
            role = "filter_grid",
            tiles = line_tiles,
        }
        index = index + 2
    end

    -- One action row closes the screen: Clear beside Apply once there is
    -- something to clear, Apply alone when there is not.
    local bar_height = math.floor(o.font_size * 2.2 + 0.5)
    local bar
    if o.total > 0 then
        local clear_w = math.floor((o.width - gap) * 0.34)
        local apply_w = o.width - gap - clear_w
        bar = HorizontalGroup:new{ align = "center" }
        bar[1] = Uikit.button(_("Clear"), clear_w, bar_height, false,
            o.on_clear, o.font_size - 2)
        bar[2] = HorizontalSpan:new{ width = gap }
        bar[3] = Uikit.button(_("Apply filters"), apply_w, bar_height, true,
            o.on_apply, o.font_size)
    else
        bar = Uikit.button(_("Apply filters"), o.width, bar_height, true,
            o.on_apply, o.font_size)
    end
    rows[#rows + 1] = {
        text = _("Apply filters"),
        ao3_panel = bar,
        action = o.on_apply,
        role = "filter_apply",
        ao3_filter_clear = o.total > 0,
        line_color = Blitbuffer.COLOR_WHITE,
    }
    return rows
end

-- One dimension's facets. The native title bar names the side and dimension
-- ("Include · Fandom"), and a compact Include/Exclude switch sits above the
-- list so the same page serves both sides. The last row opens the typed
-- autocomplete; only the tag dimensions pass `on_add_tag`.
function FilterPage.build_dimension(o)
    local rows = {}
    local sides = { include = _("Include"), exclude = _("Exclude") }
    rows[#rows + 1] = {
        ao3_static = Uikit.padded(FilterPage.section_label(
            _("Show"), o.width, o.font_size, Size.padding.default)),
        role = "filter_side_label",
        keep_with_next = true,
    }
    for _, action in ipairs({ "include", "exclude" }) do
        rows[#rows + 1] = {
            text = sides[action],
            mandatory = o.action == action and "\u{2713}" or nil,
            action = function()
                if o.on_side then o.on_side(action) end
            end,
            role = "filter_side",
            ao3_filter_action = action,
        }
    end

    for index, facet in ipairs(o.facets) do
        rows[#rows + 1] = {
            text = facet.name,
            mandatory = FilterPage.value(facet,
                o.selected[facet.id] ~= nil),
            action = function()
                o.on_toggle(index)
            end,
            role = "filter_facet",
            ao3_facet = facet,
            ao3_typed = facet.typed or nil,
        }
    end
    if o.on_add_tag then
        rows[#rows + 1] = {
            text = _("Search for a tag…"),
            action = o.on_add_tag,
            role = "filter_add_tag",
        }
    end
    if #rows == FilterPage.DIMENSION_HEADER_ROWS then
        rows[#rows + 1] = { text = _("No options on this page."),
            role = "filter_empty" }
    end
    return rows
end

-- The sort page: one row per column AO3's own select lists, a Direction
-- section only when the page has that control, and the page's default at the
-- foot. Every pick is pending state; the page rebuilds in place.
function FilterPage.build_sort(o)
    local rows = {}
    for _, option in ipairs(o.sort.columns or {}) do
        rows[#rows + 1] = {
            text = option.label,
            mandatory = option.value == o.sort.column and "\u{2713}" or nil,
            action = function()
                o.on_column(option.value)
            end,
            role = "filter_sort_column",
            ao3_sort_value = option.value,
        }
    end
    if o.sort.directions and #o.sort.directions > 0 then
        rows[#rows + 1] = {
            ao3_static = Uikit.padded(FilterPage.section_label(
                _("Direction"), o.width, o.font_size, Size.padding.large)),
            role = "filter_sort_direction_label",
            keep_with_next = true,
        }
        for _, option in ipairs(o.sort.directions) do
            rows[#rows + 1] = {
                text = option.label,
                mandatory = option.value == o.sort.direction
                    and "\u{2713}" or nil,
                action = function()
                    o.on_direction(option.value)
                end,
                role = "filter_sort_direction",
                ao3_sort_value = option.value,
            }
        end
    end
    rows[#rows + 1] = {
        text = _("Default sort"),
        action = o.on_default,
        role = "filter_sort_default",
    }
    return rows
end

-- Rows inside the typed-tag dialog. Same left inset and ink as a menu row,
-- with a fixed height so the suggestion window keeps its size whatever the
-- names are.
local function suggestionTextRow(widget, o)
    local height = math.floor(o.font_size * 2 + 0.5)
    local content = VerticalGroup:new{ align = "left" }
    local top = math.floor((height - widget:getSize().h) / 2)
    if top > 0 then content[#content + 1] = VerticalSpan:new{ width = top } end
    content[#content + 1] = Uikit.padded(widget)
    local row = LeftContainer:new{
        dimen = Geom:new{ w = o.width, h = height },
        content,
    }
    row.show_parent = o.show_parent
    return row
end

function FilterPage.suggestionHint(text, o)
    return suggestionTextRow(Uikit.label(text, o.width - 2 * Size.padding.fullscreen,
        o.font_size), o)
end

-- A fixed-height window into the live suggestions. It is added to the input
-- dialog before it is shown, so ten matches can never grow the dialog off the
-- screen: the extra rows scroll under the four visible ones.
function FilterPage.suggestionArea(o)
    local height = math.floor(o.font_size * 2 + 0.5)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = FilterPage.suggestionHint(_("Type at least two characters…"), o)
    local panel = ScrollableContainer:new{
        dimen = Geom:new{ w = o.width, h = height * 4 },
        scroll_bar_width = 0,
        group,
    }
    panel.ao3_group = group
    return panel
end

-- Replace the window's rows. `names` nil means "no list": show `o.hint` and
-- keep the panel's height. A name row is a tap target that hands the canonical
-- name to `o.on_pick`; nothing here talks to the network.
function FilterPage.fillSuggestions(panel, names, o)
    local group = panel.ao3_group
    for index = #group, 1, -1 do group[index] = nil end
    -- The group caches each child's offset on its first measure. Replacing the
    -- rows and repainting without dropping that cache leaves offsets for the
    -- old, shorter list, and the next paint walks off the end of it.
    group:resetLayout()

    if not names or #names == 0 then
        group[#group + 1] = FilterPage.suggestionHint(o.hint or "", o)
    else
        for _, name in ipairs(names) do
            local text = TextWidget:new{
                text = name,
                face = Font:getFace("cfont", o.font_size),
                max_width = o.width - 2 * Size.padding.fullscreen,
                fgcolor = Blitbuffer.COLOR_BLACK,
            }
            local row = suggestionTextRow(text, o)
            local area = Uikit.tapArea(row, o.width,
                math.floor(o.font_size * 2 + 0.5), function()
                    if o.on_pick then o.on_pick(name) end
                end)
            area.show_parent = o.show_parent
            group[#group + 1] = area
        end
    end
    -- The child size changed, so the window has to measure and crop it again.
    panel:reset()
end

function FilterPage.groupTitle(action)
    return action == "exclude" and _("Exclude") or _("Include")
end

function FilterPage.dimensionTitle(action, label)
    return T(_("%1 · %2"), FilterPage.groupTitle(action), label)
end

FilterPage.ROOT_TITLE = _("Filter works")

function FilterPage.rootTitle(scope)
    if scope == "bookmark" then return _("Filter bookmarks") end
    if scope == "search" then return _("Filter search results") end
    return FilterPage.ROOT_TITLE
end

return FilterPage
