--[[--
The work details screen.

One work as a page rather than a list of key/value lines: identity at the
top, the two decisions you actually make there (read it, or refresh the
saved copy), the numbers that tell you what you are getting into, a small
table for the decision metadata, the four things an AO3 account can do with
the work, then the long text — summary and tags — folded away behind section
headers so the page stays scannable and the work's own words are one tap from
reach.

Everything is native KOReader widgets: TextWidget / TextBoxWidget /
HorizontalGroup / VerticalGroup / LineWidget, the same building blocks the
rest of the plugin already uses. Nothing here is drawn by hand, so it
inherits the device's fonts, scaling and e-ink rendering.

The pieces are returned as rows for the plugin's Menu, which supplies
paging, the title bar and Back. Rows carrying `ao3_static` paint as-is;
rows carrying `ao3_panel` are selectable (the section headers, the action
bar) and get the menu's focus underline.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template

local SOURCE = debug.getinfo(1, "S").source:sub(2)
local Uikit = dofile((SOURCE:gsub("workpage%.lua$", "uikit.lua")))

local WorkPage = {}

local SECONDARY = Uikit.SECONDARY

local function hasText(s)
    return s ~= nil and s ~= ""
end

-- Title, author, fandoms. The title wraps: AO3 titles are long, and a
-- truncated title on a details page is worse than no title bar at all.
function WorkPage.hero(work, width, font_size)
    local group = VerticalGroup:new{ align = "left" }

    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = TextBoxWidget:new{
        text = hasText(work.title) and work.title or _("Untitled"),
        face = Font:getFace("smallinfofont", font_size + 6),
        bold = true,
        width = width,
        height_adjust = true,
        alignment = "left",
    }
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    group[#group + 1] = TextBoxWidget:new{
        text = T(_("by %1"),
            hasText(work.authors) and work.authors or _("Anonymous")),
        face = Font:getFace("smallinfofont", font_size - 4),
        fgcolor = SECONDARY,
        width = width,
        height_adjust = true,
        alignment = "left",
    }
    if hasText(work.fandoms) then
        group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
        group[#group + 1] = TextBoxWidget:new{
            text = work.fandoms,
            face = Font:getFace("smallinfofont", font_size - 4),
            fgcolor = SECONDARY,
            width = width,
            height_adjust = true,
            alignment = "left",
        }
    end
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = Uikit.rule(width)
    return group
end

-- Read is the one thing most people came for, so it gets the solid bar;
-- Refresh stays outlined and secondary.
function WorkPage.actions(width, font_size, primary_label, on_read, on_refresh)
    local gap = Size.span.horizontal_default
    local height = math.floor(font_size * 2.4 + 0.5)
    local read_w = math.floor((width - gap) * 0.6)
    local refresh_w = width - gap - read_w

    local row = HorizontalGroup:new{ align = "center" }
    row[#row + 1] = Uikit.button(primary_label, read_w, height, true, on_read, font_size)
    row[#row + 1] = HorizontalSpan:new{ width = gap }
    row[#row + 1] = Uikit.button(_("Refresh"), refresh_w, height, false, on_refresh,
        font_size - 2)

    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = row
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    return group
end

-- Words / chapters / kudos / hits, as a quiet strip. Empty values drop out
-- instead of leaving a gap.
function WorkPage.stats(work, width, font_size)
    local cells = {}
    local function add(label, value)
        if hasText(value) then
            cells[#cells + 1] = { label = label, value = value }
        end
    end
    add(_("Words"), work.words)
    add(_("Chapters"), work.chapters)
    add(_("Kudos"), work.kudos)
    add(_("Hits"), work.hits)
    if #cells == 0 then return nil end

    local gap = Size.span.horizontal_default
    local cell_w = math.floor((width - gap * (#cells - 1)) / #cells)
    local row = HorizontalGroup:new{ align = "top" }
    for i, cell in ipairs(cells) do
        if i > 1 then
            row[#row + 1] = HorizontalSpan:new{ width = gap }
        end
        local column = VerticalGroup:new{ align = "left" }
        column[#column + 1] = TextWidget:new{
            text = cell.label,
            face = Font:getFace("smallinfofont", font_size - 8),
            fgcolor = SECONDARY,
            max_width = cell_w,
        }
        column[#column + 1] = TextWidget:new{
            text = cell.value,
            face = Font:getFace("smallinfofont", font_size),
            bold = true,
            max_width = cell_w,
        }
        row[#row + 1] = LeftContainer:new{
            dimen = Geom:new{ w = cell_w, h = column:getSize().h },
            column,
        }
    end

    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = row
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = Uikit.rule(width)
    return group
end

-- The decision metadata, two aligned columns. Values wrap; labels never
-- push them off the edge.
function WorkPage.facts(work, width, font_size)
    local facts = {
        { _("Rating"), work.rating },
        { _("Warnings"), work.warnings },
        { _("Category"), work.category },
        { _("Status"), work.complete },
        { _("Updated"), work.updated },
    }
    local visible = {}
    for _, fact in ipairs(facts) do
        if hasText(fact[2]) then
            visible[#visible + 1] = fact
        end
    end
    if #visible == 0 then return nil end

    local label_w = math.floor(width * 0.23)
    local value_w = width - label_w - Size.span.horizontal_default
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    for i, fact in ipairs(visible) do
        if i > 1 then
            group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
        end
        local value = TextBoxWidget:new{
            text = fact[2],
            face = Font:getFace("smallinfofont", font_size - 2),
            width = value_w,
            height_adjust = true,
            alignment = "left",
        }
        local label = TextWidget:new{
            text = fact[1],
            face = Font:getFace("smallinfofont", font_size - 4),
            fgcolor = SECONDARY,
            max_width = label_w,
        }
        local row = HorizontalGroup:new{ align = "top" }
        row[#row + 1] = LeftContainer:new{
            dimen = Geom:new{ w = label_w, h = value:getSize().h },
            label,
        }
        row[#row + 1] = HorizontalSpan:new{ width = Size.span.horizontal_default }
        row[#row + 1] = LeftContainer:new{
            dimen = Geom:new{ w = value_w, h = value:getSize().h },
            value,
        }
        group[#group + 1] = row
    end
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    return group
end

-- A quiet "Series" label above the series rows: the same group label the
-- account page uses, so the rows below read as one group rather than as more
-- work facts. The rows themselves stay native menu rows.
function WorkPage.series_label(width, font_size)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = Uikit.label(_("Series"), width, font_size)
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = group:getSize().h },
        group,
    }
end

-- The four things an AO3 account does with a work. Read stays the page's one
-- solid bar, so these are a 2x2 grid of outlined buttons: a second primary
-- would cancel the first. The pressed state is KOReader's own checkmark, the
-- same mark its tab strip uses, so the page needs no new state language.
WorkPage.SOCIAL = {
    { id = "kudos", label = _("Kudos") },
    { id = "bookmark", label = _("Bookmark") },
    { id = "subscribe", label = _("Subscribe") },
    { id = "later", label = _("Mark for later") },
}

-- `state` maps a social id to whether it is already on. `signed_in` only
-- changes the quiet line under the grid: the buttons keep full contrast
-- either way and route the tap to sign-in themselves.
function WorkPage.social(width, font_size, state, signed_in, on_action)
    state = state or {}
    on_action = on_action or function() end
    local gap = Size.span.horizontal_default
    local height = math.floor(font_size * 2.4 + 0.5)
    local button_w = math.floor((width - gap) / 2)

    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = Uikit.label(_("Your AO3"), width, font_size)
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }

    for i = 1, #WorkPage.SOCIAL, 2 do
        local row = HorizontalGroup:new{ align = "center" }
        for column = 0, 1 do
            local entry = WorkPage.SOCIAL[i + column]
            if entry then
                if column > 0 then
                    row[#row + 1] = HorizontalSpan:new{ width = gap }
                end
                row[#row + 1] = Uikit.button(
                    entry.label, button_w, height, false,
                    function() on_action(entry.id) end,
                    font_size - 2, state[entry.id] == true)
            end
        end
        group[#group + 1] = row
        if i + 2 <= #WorkPage.SOCIAL then
            group[#group + 1] = VerticalSpan:new{ width = gap }
        end
    end

    if not signed_in then
        group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
        group[#group + 1] = TextBoxWidget:new{
            text = _("Sign in to your AO3 account to use these."),
            face = Font:getFace("smallinfofont", font_size - 5),
            fgcolor = Blitbuffer.COLOR_GRAY_6,
            width = width,
            height_adjust = true,
            alignment = "left",
        }
    end
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = Uikit.rule(width)
    return group
end

-- Section header for the folded content. The menu's focus underline sits
-- under it, so it also acts as the rule between sections.
function WorkPage.section(title, width, font_size, expanded)
    local label = TextWidget:new{
        text = title,
        face = Font:getFace("smallinfofont", font_size),
        bold = true,
        max_width = width - 2 * Size.padding.large,
    }
    local glyph = TextWidget:new{
        text = expanded and "-" or "+",
        face = Font:getFace("cfont", font_size + 2),
        bold = true,
        fgcolor = SECONDARY,
    }
    local row = HorizontalGroup:new{ align = "center" }
    row[#row + 1] = label
    row[#row + 1] = HorizontalSpan:new{
        width = math.max(0, width - label:getWidth() - glyph:getWidth()),
    }
    row[#row + 1] = glyph

    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.small }
    group[#group + 1] = row
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    return group
end

-- Text body for the folded sections. Bounded: a Menu row taller than a page
-- is clipped (the menu pages by item, it does not scroll inside one), so a
-- long body is elided and the caller offers the full text in TextViewer.
-- Returns the widget and whether anything was cut off.
function WorkPage.body(text, width, font_size, max_height)
    local box = TextBoxWidget:new{
        text = text,
        face = Font:getFace("smallinfofont", font_size - 2),
        width = width,
        height = max_height,
        height_adjust = true,
        height_overflow_show_ellipsis = true,
        alignment = "left",
        line_height = 0.15,
    }
    local clamped = box.lines_per_page
        and #box.vertical_string_list > box.lines_per_page
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = box
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    return group, clamped
end

-- Build the rows the menu will page through. `state` holds which sections
-- are open, so the caller can rebuild after a toggle without losing it.
function WorkPage.build(o)
    local work = o.work
    local width = o.width
    local font_size = o.font_size
    local rows = {}

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(WorkPage.hero(work, width, font_size)),
        role = "hero",
    }

    local primary_label = o.cached and _("Open saved copy") or _("Read")
    rows[#rows + 1] = {
        ao3_panel = WorkPage.actions(width, font_size, primary_label,
            o.on_read, o.on_refresh),
        action = o.on_read,
        refresh = o.on_refresh,
        read_label = primary_label,
        role = "actions",
        -- No resting underline between the hero and the numbers; the line
        -- only appears when this row has focus.
        line_color = Blitbuffer.COLOR_WHITE,
    }

    local stats = WorkPage.stats(work, width, font_size)
    if stats then
        rows[#rows + 1] = { ao3_static = Uikit.padded(stats), role = "stats" }
    end

    local facts = WorkPage.facts(work, width, font_size)
    if facts then
        rows[#rows + 1] = { ao3_static = Uikit.padded(facts), role = "facts" }
    end

    -- Account actions sit below the metadata so Read keeps the top of the
    -- page, and above the folded text so they stay on the first screen.
    rows[#rows + 1] = {
        ao3_static = Uikit.padded(WorkPage.social(
            width, font_size, o.social or {}, o.signed_in == true,
            o.on_action or function() end)),
        role = "social",
    }

    -- Series membership is navigation, like the author rows, but it belongs on
    -- the first screen with the work's other facts: it sits below the account
    -- grid and above the folded text, so Summary and Tags cannot bury the way
    -- into the series. The row carries its entry so the caller needs no second
    -- fetch to know which series was tapped.
    local series = {}
    for _, entry in ipairs(work.series or {}) do
        if entry and hasText(entry.name) then series[#series + 1] = entry end
    end
    if #series > 0 then
        rows[#rows + 1] = {
            ao3_static = Uikit.padded(WorkPage.series_label(width, font_size)),
            role = "series_label",
            -- A page must not end on a label whose rows are overleaf.
            keep_with_next = true,
        }
        local on_series = o.on_series or function() end
        -- Translate before the loop: `for _, entry` shadows gettext `_`.
        local part_format = _("Part %1 of %2")
        local of_format = _("Part of %1")
        for _, entry in ipairs(series) do
            local position = tonumber(entry.position)
            local text = position
                and T(part_format, position, entry.name)
                or T(of_format, entry.name)
            rows[#rows + 1] = {
                text = text,
                entry = entry,
                action = function() on_series(entry) end,
                role = "series",
            }
        end
    end

    if hasText(work.summary) then
        rows[#rows + 1] = {
            ao3_panel = WorkPage.section(_("Summary"), width, font_size,
                o.state.summary),
            action = function() o.on_toggle("summary") end,
            label = _("Summary"),
            role = "summary",
        }
        if o.state.summary then
            local body, clamped = WorkPage.body(
                work.summary, width, font_size, o.body_max_height)
            rows[#rows + 1] = {
                ao3_static = Uikit.padded(body),
                role = "summary_body",
            }
            if clamped then
                rows[#rows + 1] = {
                    text = _("Read full summary"),
                    mandatory = _("Opens the full text"),
                    action = function() o.on_full_text(_("Summary"), work.summary) end,
                    role = "summary_more",
                }
            end
        end
    end

    if hasText(work.tags) then
        local tag_count = select(2, work.tags:gsub(",", "")) + 1
        local tags_label = T(_("Tags · %1"), tag_count)
        rows[#rows + 1] = {
            ao3_panel = WorkPage.section(
                tags_label, width, font_size, o.state.tags),
            action = function() o.on_toggle("tags") end,
            label = tags_label,
            role = "tags",
        }
        if o.state.tags then
            local body, clamped = WorkPage.body(
                (work.tags:gsub(",%s*", "  ·  ")), width, font_size,
                o.body_max_height)
            rows[#rows + 1] = {
                ao3_static = Uikit.padded(body),
                role = "tags_body",
            }
            if clamped then
                rows[#rows + 1] = {
                    text = _("Read all tags"),
                    mandatory = _("Opens the full list"),
                    action = function() o.on_full_text(_("Tags"), work.tags) end,
                    role = "tags_more",
                }
            end
        end
    end

    -- Authors are the only navigation off this page, so they stay as native
    -- menu rows at the bottom, after the content they describe.
    local names, urls = work.author_names or {}, work.author_urls or {}
    if #names > 0 and #names == #urls then
        for i = 1, #names do
            local name, url = names[i], urls[i]
            rows[#rows + 1] = {
                text = name,
                mandatory = _("Author page"),
                action = function() o.on_author(name, url) end,
                role = "author",
            }
        end
    end

    return rows
end

return WorkPage
