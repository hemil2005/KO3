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
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local _ = require("gettext")
local T = require("ffi/util").template

local SOURCE = debug.getinfo(1, "S").source:sub(2)
local Uikit = dofile((SOURCE:gsub("homepage%.lua$", "uikit.lua")))

local HomePage = {}

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

-- Logo lockup: mark on the left, name and one honest subtitle beside it.
function HomePage.hero(o)
    local text_width = o.width
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
            row[#row + 1] = HorizontalSpan:new{ width = Size.padding.large }
            text_width = math.max(1, o.width - logo_w - Size.padding.large)
        end
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

    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = row
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = Uikit.rule(o.width)
    return group
end

-- The one primary action on the screen, styled like Read on the work page.
function HomePage.search(o)
    local height = math.floor(o.font_size * 2.4 + 0.5)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = Uikit.button(_("Search works"), o.width, height, true,
        o.on_search, o.font_size)
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    return group
end

-- A quiet group label, not a control. LeftContainer fixes the row width so
-- the menu (whose item group centres) cannot float it to the middle.
function HomePage.section_label(text, o, top)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{
        width = top or (Size.padding.default + Size.span.vertical_default),
    }
    group[#group + 1] = Uikit.label(text, o.width, o.font_size)
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_small }
    return LeftContainer:new{
        dimen = Geom:new{ w = o.width, h = group:getSize().h },
        group,
    }
end

-- One tile: symbol over a bold label and a short hint, inside a hairline
-- card. Sized explicitly so a row of tiles has one baseline.
function HomePage.tile(entry, width, height, o)
    local pad = Size.padding.large
    local border = Size.border.default
    local inner_w = width - 2 * (pad + border)
    local inner_h = height - 2 * (pad + border)

    local content = VerticalGroup:new{ align = "left" }
    local mark = icon(o, entry.icon, Screen:scaleBySize(26))
    if mark then
        content[#content + 1] = mark
        content[#content + 1] = VerticalSpan:new{ width = Size.padding.default }
    end
    content[#content + 1] = TextWidget:new{
        text = entry.text,
        face = Font:getFace("smallinfofont", o.font_size),
        bold = true,
        max_width = inner_w,
    }
    if entry.hint then
        content[#content + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
        content[#content + 1] = TextWidget:new{
            text = entry.hint,
            face = Font:getFace("smallinfofont", o.font_size - 8),
            fgcolor = Uikit.SECONDARY,
            max_width = inner_w,
        }
    end

    local frame = FrameContainer:new{
        bordersize = border,
        color = Blitbuffer.COLOR_BLACK,
        radius = Size.radius.button,
        background = Blitbuffer.COLOR_WHITE,
        padding = pad,
        WidgetContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            content,
        },
    }
    return Uikit.tapArea(frame, width, height, entry.action)
end

-- Two tiles side by side. The pair is a static row; taps land on the tiles.
function HomePage.tiles_row(entries, o, role)
    local gap = Size.span.horizontal_default
    local tile_w = math.floor((o.width - gap) / 2)
    local row = HorizontalGroup:new{ align = "top" }
    for i, entry in ipairs(entries) do
        if i > 1 then
            row[#row + 1] = HorizontalSpan:new{ width = gap }
        end
        row[#row + 1] = HomePage.tile(entry, tile_w, o.tile_height, o)
    end
    return {
        ao3_static = Uikit.padded(row),
        role = role,
        tiles = entries,
    }
end

-- A full-width tile for the occasional single action (Plugin).
function HomePage.wide_tile(entry, o, role)
    local pad = Size.padding.large
    local border = Size.border.default
    local width = o.width
    local height = o.wide_height
    local inner_w = width - 2 * (pad + border)
    local inner_h = height - 2 * (pad + border)

    local mark = icon(o, entry.icon, Screen:scaleBySize(26))
    local text = VerticalGroup:new{ align = "left" }
    text[#text + 1] = TextWidget:new{
        text = entry.text,
        face = Font:getFace("smallinfofont", o.font_size),
        bold = true,
        max_width = inner_w - (mark and Screen:scaleBySize(26) + pad or 0),
    }
    if entry.hint then
        text[#text + 1] = VerticalSpan:new{ width = Size.span.vertical_default }
        text[#text + 1] = TextWidget:new{
            text = entry.hint,
            face = Font:getFace("smallinfofont", o.font_size - 8),
            fgcolor = Uikit.SECONDARY,
            max_width = inner_w - (mark and Screen:scaleBySize(26) + pad or 0),
        }
    end

    local row = HorizontalGroup:new{ align = "center" }
    if mark then
        row[#row + 1] = mark
        row[#row + 1] = HorizontalSpan:new{ width = Size.padding.large }
    end
    row[#row + 1] = text

    local frame = FrameContainer:new{
        bordersize = border,
        color = Blitbuffer.COLOR_BLACK,
        radius = Size.radius.button,
        background = Blitbuffer.COLOR_WHITE,
        padding = pad,
        WidgetContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            row,
        },
    }
    return {
        ao3_static = Uikit.padded(Uikit.tapArea(frame, width, height, entry.action)),
        role = role,
        tiles = { entry },
    }
end

function HomePage.build(o)
    local rows = {}
    o.tile_height = math.floor(o.font_size * 5.2 + 0.5)
    o.wide_height = math.floor(o.font_size * 3.4 + 0.5)

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

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.section_label(_("Browse"), o)),
        role = "browse_label",
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
    }, o, "browse_row_1")
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

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.section_label(_("Library"), o)),
        role = "library_label",
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
    }, o, "library_row")

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.section_label(_("Plugin"), o)),
        role = "plugin_label",
    }
    rows[#rows + 1] = HomePage.wide_tile({
        text = _("Update plugin"),
        hint = o.version and T(_("Installed v%1"), o.version) or nil,
        icon = "refresh", role = "update", action = o.on_update,
    }, o, "update")

    if o.on_restore then
        rows[#rows + 1] = HomePage.wide_tile({
            text = _("Restore previous version"),
            hint = _("Undo the last update"),
            icon = "restore", role = "restore", action = o.on_restore,
        }, o, "restore")
    end

    return rows
end

return HomePage
