--[[--
The filter screen of a work listing.

AO3 puts its filter sidebar in the same HTML as the results, so KO3 can offer
the facets the page already carries without a second request. This module only
draws that form: an Include group and an Exclude group, one drill-in row per
dimension, then the facets of the chosen dimension as native rows. main.lua
owns the selection, the URL and the one request Apply makes.

The screen follows the catalogue's own language (DESIGN.md): native rows with
the dimension on the left and its count on the right, quiet group labels, no
prose. The one solid bar is Apply, because committing the choice is what the
screen exists for.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
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

-- `dimensions` are the facets the page carried, one entry per AO3 dimension
-- with its include list and exclude list already split.
-- `selected_count(action, type)` is read per row so a returned-to root page
-- can be rebuilt with fresh counts.
function FilterPage.build_root(o)
    local rows = {}
    local group_name = { include = _("Include"), exclude = _("Exclude") }
    local selected_singular = _("1 selected")
    local selected_plural = _("%1 selected")

    local function addGroup(action, top)
        rows[#rows + 1] = {
            ao3_static = Uikit.padded(FilterPage.section_label(
                group_name[action], o.width, o.font_size, top)),
            role = "filter_group",
            ao3_filter_group = action,
            keep_with_next = true,
        }
        for _, dimension in ipairs(o.dimensions) do
            local count = o.selected_count(action, dimension.key)
            rows[#rows + 1] = {
                text = dimension.label,
                mandatory = count == 1 and selected_singular
                    or (count > 1 and T(selected_plural, count) or nil),
                action = function()
                    o.on_dimension(action, dimension.key)
                end,
                role = "filter_dimension",
                ao3_filter_action = action,
                ao3_filter_type = dimension.key,
            }
        end
    end

    addGroup("include", Size.padding.default)
    addGroup("exclude", Size.padding.large)

    -- One action row closes the screen: Clear beside Apply once there is
    -- something to clear, Apply alone when there is not. Fourteen dimension
    -- rows plus two labels plus this row are one 600x800 page.
    local height = math.floor(o.font_size * 2.2 + 0.5)
    local bar
    if o.total > 0 then
        local gap = Size.span.horizontal_default
        local clear_w = math.floor((o.width - gap) * 0.34)
        local apply_w = o.width - gap - clear_w
        bar = HorizontalGroup:new{ align = "center" }
        bar[1] = Uikit.button(_("Clear"), clear_w, height, false,
            o.on_clear, o.font_size - 2)
        bar[2] = HorizontalSpan:new{ width = gap }
        bar[3] = Uikit.button(_("Apply filters"), apply_w, height, true,
            o.on_apply, o.font_size)
    else
        bar = Uikit.button(_("Apply filters"), o.width, height, true,
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

-- One dimension's facets. The native title bar names the group and dimension
-- ("Include · Fandom"), so the rows can be nothing but names and counts. The
-- last row opens the typed autocomplete; only the four tag dimensions pass
-- `on_add_tag`.
function FilterPage.build_dimension(o)
    local rows = {}
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
    if #rows == 0 then
        rows[1] = { text = _("No options on this page."), role = "filter_empty" }
    end
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
    return scope == "bookmark" and _("Filter bookmarks") or FilterPage.ROOT_TITLE
end

return FilterPage
