--[[--
The plugin's landing screen.

A front page rather than a pile of links: the AO3 mark and name, one solid
primary action (Search), then icon tiles for browsing and for the local
library. It uses the same primitives as the work details page (uikit.lua),
so the two screens read as one product.

The logo is the official OTW artwork: assets/ao3-logo.png byte-for-byte,
and assets/ao3-logo.svg traced from it for sharp e-ink rendering. The row
symbols are authored 24x24 vector icons in assets/icons/ (stroke style, same
weight as KOReader's own mdlight icons), so they scale and stay legible on
e-ink instead of falling back to a missing-icon glyph on older builds.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local ImageWidget = require("ui/widget/imagewidget")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Screen = require("device").screen
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template

local SOURCE = debug.getinfo(1, "S").source:sub(2)
local Uikit = dofile((SOURCE:gsub("homepage%.lua$", "uikit.lua")))

local HomePage = {}

-- One spacing rhythm for the screen: cards sit a gutter apart, a new group
-- starts two gutters above its label, and a label sits one small step above
-- the cards it names. Tight inside a group, open between groups.
local GUTTER = Size.span.horizontal_default
local GROUP_GAP = Size.padding.large * 2

-- An icon from assets/icons/, rendered at the given size. Missing files (or
-- a build without SVG support) simply leave the text-only tile intact.
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

-- A masthead control: one quiet icon in a 44px tap target, aligned with the
-- name. The settings gear and the notifications bell share this shape so they
-- read as one pair at the right edge. A build without SVG gets a short word
-- instead of a missing-icon glyph, so the action stays reachable.
local function mastheadButton(o, icon_name, label, callback)
    local size = Screen:scaleBySize(44)
    local mark_size = Screen:scaleBySize(24)
    local mark = icon(o, icon_name, mark_size)
    local line = HorizontalGroup:new{ align = "center" }
    if mark then
        line[#line + 1] = HorizontalSpan:new{
            width = math.max(0, math.floor((size - mark_size) / 2)),
        }
        line[#line + 1] = mark
    else
        line[#line + 1] = TextWidget:new{
            text = label,
            face = Font:getFace("smallinfofont", HomePage.hint_size(o) - 2),
            fgcolor = Uikit.SECONDARY,
            max_width = size,
        }
    end
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
    group[#group + 1] = line
    return Uikit.tapArea(group, size, size, callback)
end

-- The settings control: a quiet gear at the far right of the masthead line.
-- It is a tap area rather than a button, because a second outlined control
-- beside the solid Search bar would compete with it.
function HomePage.settingsButton(o)
    return mastheadButton(o, "settings", _("Settings"), o.on_settings)
end

-- The notifications control: a bell beside the gear. It wears the filled-dot
-- icon while the quiet check has found chapters the saved copy does not have,
-- so the landing page says there is something new without a popup.
function HomePage.bellButton(o)
    return mastheadButton(o, o.updates_unread and "bell-dot" or "bell",
        _("Updates"), o.on_updates)
end

-- Logo lockup: mark on the left, name and one honest subtitle beside it, then
-- the bell and the settings gear at the right edge of the same line.
function HomePage.hero(o)
    local gap = Size.padding.large
    local control = Screen:scaleBySize(44)
    local bell_w = o.on_updates and control or 0
    local gear_w = o.on_settings and control or 0
    local controls = bell_w + gear_w
    local text_width = o.width
    local logo_used = 0
    local row = HorizontalGroup:new{ align = "top" }

    if o.logo_path then
        local logo_w = Screen:scaleBySize(84)
        local logo_h = math.floor(logo_w * 240 / 351 + 0.5)
        local ok, logo = pcall(ImageWidget.new, ImageWidget, {
            file = o.logo_path,
            width = logo_w,
            height = logo_h,
            alpha = true,
        })
        if ok and logo then
            row[#row + 1] = logo
            row[#row + 1] = HorizontalSpan:new{ width = gap }
            logo_used = logo_w + gap
            text_width = math.max(1, text_width - logo_used)
        end
    end
    if controls > 0 then
        text_width = math.max(1, text_width - controls - gap)
    end

    local text = VerticalGroup:new{ align = "left" }
    text[#text + 1] = TextWidget:new{
        text = _("Archive of Our Own"),
        face = Font:getFace("smallinfofont", o.font_size + 2),
        bold = true,
        max_width = text_width,
    }
    text[#text + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
    text[#text + 1] = TextWidget:new{
        text = _("Unofficial reader · works and fandoms"),
        face = Font:getFace("smallinfofont", o.font_size - 6),
        fgcolor = Uikit.SECONDARY,
        max_width = text_width,
    }
    row[#row + 1] = text

    if controls > 0 then
        local used = logo_used + text:getSize().w
        row[#row + 1] = HorizontalSpan:new{
            width = math.max(gap, o.width - used - controls),
        }
        if bell_w > 0 then
            row[#row + 1] = HomePage.bellButton(o)
        end
        if gear_w > 0 then
            row[#row + 1] = HomePage.settingsButton(o)
        end
    end

    local group = VerticalGroup:new{ align = "left" }
    -- Equal air above and below the lockup: the gap to the top is the gap
    -- before the search bar (which carries its own matching padding), and the
    -- solid bar is the divider, so the header needs no hairline of its own.
    group[#group + 1] = VerticalSpan:new{ width = GUTTER }
    group[#group + 1] = row
    -- Pin the lockup to the full column width: the mark and name are a header,
    -- not a floating badge in the middle of the page.
    return LeftContainer:new{
        dimen = Geom:new{ w = o.width, h = group:getSize().h },
        group,
    }
end

-- The one primary action on the screen, styled like Read on the work page.
function HomePage.search(o)
    local height = math.floor(o.font_size * 2.4 + 0.5)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = GUTTER }
    group[#group + 1] = Uikit.button(_("Search works"), o.width, height, true,
        o.on_search, o.font_size)
    -- No padding below: the next group's label gap owns that separation.
    return group
end

-- A quiet group label, not a control. LeftContainer fixes the row width so
-- the menu (whose item group centres) cannot float it to the middle.
function HomePage.section_label(text, o, top)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = top or GROUP_GAP }
    group[#group + 1] = Uikit.label(text, o.width, o.font_size)
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    return LeftContainer:new{
        dimen = Geom:new{ w = o.width, h = group:getSize().h },
        group,
    }
end

-- The icon is a fixed visual weight; the text beside it carries the name.
local function iconSize()
    return Screen:scaleBySize(26)
end

-- The hint is secondary but still has to be read on e-ink: one step below the
-- tile name, not a footnote.
function HomePage.hint_size(o)
    return o.font_size - 5
end

-- Single-line height for a face, so the card can be measured from the content
-- it actually holds rather than from a font-size multiplier.
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

-- Name beside the symbol, hint underneath both: the name is what the eye
-- lands on, and the card spends its height on the words, not on a gap.
function HomePage.card(entry, width, height, o)
    local pad = Size.padding.large
    local border = Size.border.default
    local inner_w = math.max(1, width - 2 * (pad + border))
    local inner_h = math.max(1, height - 2 * (pad + border))
    local mark = icon(o, entry.icon, iconSize())
    local mark_w = mark and iconSize() + Size.padding.large or 0

    local top = HorizontalGroup:new{ align = "center" }
    if mark then
        top[#top + 1] = mark
        top[#top + 1] = HorizontalSpan:new{ width = Size.padding.large }
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
        content[#content + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
        content[#content + 1] = TextWidget:new{
            text = entry.hint,
            face = Font:getFace("smallinfofont", HomePage.hint_size(o)),
            -- The same detail ink as the work cards' author and summary: a
            -- hint that has been made readable should not stay pale.
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
    return Uikit.tapArea(frame, width, height, entry.action, entry.hold_action)
end

-- A card row plus the air that separates it from the next row. The gap lives
-- in the row so tile rows cannot end up flush against each other.
local function rowBlock(row, space_below)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = Uikit.padded(row)
    if space_below and space_below > 0 then
        group[#group + 1] = VerticalSpan:new{ width = space_below }
    end
    return group
end

-- The Continue reading row: a full-width card in the tile family, with an open
-- book on the left, the action's name over the work's own title, and a chevron
-- at the right edge that says the row goes somewhere. It is a reading record,
-- not a button, so it keeps the tiles' 7px card and 1px ink border.
function HomePage.continueCard(entry, width, height, o)
    local pad = Size.padding.large
    local border = Size.border.default
    local gap = Size.padding.large
    local inner_w = math.max(1, width - 2 * (pad + border))
    local inner_h = math.max(1, height - 2 * (pad + border))
    local mark = icon(o, entry.icon, iconSize())
    local mark_w = mark and iconSize() + gap or 0
    local arrow_size = Screen:scaleBySize(22)
    local arrow = icon(o, "arrow-right", arrow_size)
    local arrow_w = arrow and arrow_size + gap or 0
    local text_w = math.max(1, inner_w - mark_w - arrow_w)

    local text = VerticalGroup:new{ align = "left" }
    text[#text + 1] = TextWidget:new{
        text = entry.text,
        face = Font:getFace("smallinfofont", o.font_size),
        bold = true,
        max_width = text_w,
    }
    text[#text + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    text[#text + 1] = TextWidget:new{
        text = entry.hint,
        face = Font:getFace("smallinfofont", HomePage.hint_size(o)),
        fgcolor = Uikit.CARD_DETAIL,
        max_width = text_w,
    }

    local row = HorizontalGroup:new{ align = "center" }
    if mark then
        row[#row + 1] = mark
        row[#row + 1] = HorizontalSpan:new{ width = gap }
    end
    row[#row + 1] = LeftContainer:new{
        dimen = Geom:new{ w = text_w, h = inner_h },
        text,
    }
    if arrow then
        row[#row + 1] = HorizontalSpan:new{ width = gap }
        row[#row + 1] = CenterContainer:new{
            dimen = Geom:new{ w = arrow_size, h = inner_h },
            arrow,
        }
    end

    local frame = FrameContainer:new{
        bordersize = border,
        color = Blitbuffer.COLOR_BLACK,
        radius = Size.radius.button,
        background = Blitbuffer.COLOR_WHITE,
        padding = pad,
        row,
    }
    return Uikit.tapArea(frame, width, height, entry.action)
end

-- Two tiles side by side. The pair is a static row; taps land on the tiles.
function HomePage.tiles_row(entries, o, role, space_below)
    local gap = GUTTER
    local tile_w = math.floor((o.width - gap) / 2)
    local row = HorizontalGroup:new{ align = "top" }
    for i, entry in ipairs(entries) do
        if i > 1 then
            row[#row + 1] = HorizontalSpan:new{ width = gap }
        end
        row[#row + 1] = HomePage.card(entry, tile_w, o.tile_height, o)
    end
    return {
        ao3_static = rowBlock(row, space_below),
        role = role,
        tiles = entries,
    }
end

-- A full-width tile for the occasional single action (Plugin). Same card as
-- the grid, just wider, so the two read as one family.
function HomePage.wide_tile(entry, o, role, space_below)
    local card = HomePage.card(entry, o.width, o.tile_height, o)
    return {
        ao3_static = rowBlock(card, space_below),
        role = role,
        tiles = { entry },
    }
end

-- The one row that changes with reading rather than with the session. It uses
-- the tile height so it sits in the Library shelf's rhythm.
function HomePage.continue_row(entry, o, role)
    local card = HomePage.continueCard(entry, o.width, o.tile_height, o)
    return {
        ao3_static = rowBlock(card, 0),
        role = role,
        tiles = { entry },
    }
end

function HomePage.build(o)
    local rows = {}
    -- Measured from the card's own content: the icon row, the gap under it and
    -- the hint line, plus the frame's padding and border. Spending the height
    -- on the words is what lets the hint keep a readable size.
    o.tile_height = 2 * (Size.padding.large + Size.border.default)
        + math.max(iconSize(), lineHeight(Font:getFace("smallinfofont", o.font_size), true))
        + Size.span.vertical_large
        + lineHeight(Font:getFace("smallinfofont", HomePage.hint_size(o)), false)

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.hero(o)),
        role = "hero",
    }

    rows[#rows + 1] = {
        ao3_panel = HomePage.search(o),
        action = o.on_search,
        role = "search",
        -- The bar carries its own weight; the focus underline only appears
        -- when the row actually has focus.
        line_color = Blitbuffer.COLOR_WHITE,
    }

    -- Pinned fandoms sit between Search and Browse: they are the reader's own
    -- short shelf, a faster path than the letter index, but they must not
    -- displace the one primary action above them. An empty shelf emits no
    -- rows at all, so the landing page is unchanged until something is pinned.
    local favourites = o.favourites or {}
    if #favourites > 0 then
        local label = _("%1 works")
        local function tile(favourite)
            return {
                text = favourite.name,
                hint = type(favourite.count) == "string" and favourite.count ~= ""
                    and T(label, favourite.count) or _("Fandom"),
                icon = "heart",
                role = "favourite",
                -- The stored record travels with the tile so a hold can
                -- unpin the exact url, not a name guessed from the label.
                favourite = favourite,
                action = function() o.on_favourite(favourite) end,
                hold_action = function() o.on_unfavourite(favourite) end,
            }
        end

        rows[#rows + 1] = {
            ao3_static = Uikit.padded(HomePage.section_label(_("Favourites"), o)),
            role = "favourites_label",
            keep_with_next = true,
        }

        local shown = {}
        for i = 1, math.min(#favourites, 4) do
            shown[i] = tile(favourites[i])
        end
        rows[#rows + 1] = HomePage.tiles_row(
            { shown[1], shown[2] }, o, "favourites_row_1",
            shown[3] and GUTTER or 0)
        if shown[3] then
            rows[#rows + 1] = HomePage.tiles_row(
                { shown[3], shown[4] }, o, "favourites_row_2",
                #favourites > 4 and GUTTER or 0)
        end
        if #favourites > 4 then
            rows[#rows + 1] = HomePage.wide_tile({
                text = _("All favourites"),
                hint = T(_("%1 pinned"), #favourites),
                icon = "heart",
                role = "favourites_all",
                action = o.on_all_favourites,
            }, o, "favourites_all")
        end
    end

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.section_label(_("Browse"), o)),
        role = "browse_label",
        keep_with_next = true,
    }
    rows[#rows + 1] = HomePage.tiles_row({
        {
            text = _("Latest works"), hint = _("Newest on AO3"), icon = "clock",
            role = "latest", action = o.on_latest,
        },
        {
            text = _("Fandoms"), hint = _("By media"), icon = "grid",
            role = "fandoms", action = o.on_fandoms,
        },
    }, o, "browse_row_1", GUTTER)
    rows[#rows + 1] = HomePage.tiles_row({
        {
            text = _("Author"), hint = _("Works by a writer"), icon = "user",
            role = "author", action = o.on_author,
        },
        {
            text = _("Tag"), hint = _("Tag name or URL"), icon = "tag",
            role = "tag", action = o.on_tag,
        },
    }, o, "browse_row_2")

    -- One tile that changes with the session: a way in while signed out, the
    -- reader's own name and lists once signed in. It sits below Browse so the
    -- primary path stays first, and above Library so it is not buried.
    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.section_label(_("Account"), o)),
        role = "account_label",
        keep_with_next = true,
    }
    rows[#rows + 1] = HomePage.wide_tile({
        text = o.signed_in and (o.account_name or _("My account")) or _("Sign in"),
        hint = o.signed_in and _("Bookmarks, marked for later, history, subscriptions")
            or _("Kudos, bookmarks and subscriptions"),
        icon = o.signed_in and "user" or "login",
        role = "account", action = o.on_account,
    }, o, "account")

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.section_label(_("Library"), o)),
        role = "library_label",
        keep_with_next = true,
    }
    rows[#rows + 1] = HomePage.tiles_row({
        {
            text = _("Downloads"),
            hint = o.downloads > 0 and T(_("%1 saved"), o.downloads) or _("None yet"),
            icon = "download", role = "downloads", action = o.on_downloads,
        },
        {
            text = _("Open work"), hint = _("URL or ID"), icon = "file",
            role = "open", action = o.on_open,
        },
    }, o, "library_row", o.continue_work and GUTTER or nil)

    -- Resume the work the reader opened last, directly under the Library
    -- shelf it is saved in. Absent until something has been read, so a fresh
    -- install shows the same four groups as before.
    if o.continue_work then
        rows[#rows + 1] = HomePage.continue_row({
            text = _("Continue reading"),
            hint = o.continue_work.title,
            icon = "book",
            role = "continue",
            action = o.continue_work.action,
        }, o, "continue")
    end

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.section_label(_("Plugin"), o)),
        role = "plugin_label",
        keep_with_next = true,
    }
    rows[#rows + 1] = HomePage.wide_tile({
        text = _("Update KO3"),
        hint = o.version and T(_("Installed v%1"), o.version) or nil,
        icon = "refresh", role = "update", action = o.on_update,
    }, o, "update", GUTTER)

    rows[#rows + 1] = HomePage.wide_tile({
        text = _("Report a bug"),
        hint = _("Description and log"),
        icon = "file", role = "report", action = o.on_report,
    }, o, "report", o.on_restore and GUTTER or 0)

    if o.on_restore then
        rows[#rows + 1] = HomePage.wide_tile({
            text = _("Restore previous version"),
            hint = _("Undo the last update"),
            icon = "restore", role = "restore", action = o.on_restore,
        }, o, "restore")
    end

    -- Marks this table as the landing page, so a work opened later can refresh
    -- the Continue reading row on the copy that waits at the bottom of the
    -- menu's stack without rebuilding the whole screen.
    rows.ao3_home = true
    return rows
end

return HomePage
