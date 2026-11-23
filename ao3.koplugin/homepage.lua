--[[--
The plugin's landing screen.

A front page rather than a pile of links: the AO3 mark and name, one solid
primary action (Search), then grouped rows for browsing and for the local
library. It uses the same primitives as the work details page (uikit.lua),
so the two screens read as one product.

The logo is the official OTW artwork: assets/ao3-logo.png byte-for-byte,
and assets/ao3-logo.svg traced from it for sharp e-ink rendering. If the
SVG is missing, the caller passes the PNG instead.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
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

function HomePage.build(o)
    local rows = {}

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
    rows[#rows + 1] = {
        text = _("Latest works"),
        mandatory = _("Newest on AO3"),
        action = o.on_latest,
        role = "latest",
    }
    rows[#rows + 1] = {
        text = _("Fandoms"),
        mandatory = _("By media"),
        action = o.on_fandoms,
        role = "fandoms",
    }
    rows[#rows + 1] = {
        text = _("Author"),
        mandatory = _("Works by a writer"),
        action = o.on_author,
        role = "author",
    }
    rows[#rows + 1] = {
        text = _("Tag"),
        mandatory = _("Tag name or URL"),
        action = o.on_tag,
        role = "tag",
    }

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.section_label(_("Library"), o)),
        role = "library_label",
    }
    rows[#rows + 1] = {
        text = _("Downloads"),
        mandatory = o.downloads > 0 and T(_("%1 saved"), o.downloads) or _("None yet"),
        action = o.on_downloads,
        role = "downloads",
    }
    rows[#rows + 1] = {
        text = _("Open work"),
        mandatory = _("URL or ID"),
        action = o.on_open,
        role = "open",
    }

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(HomePage.section_label(_("Plugin"), o)),
        role = "plugin_label",
    }
    rows[#rows + 1] = {
        text = _("Update plugin"),
        mandatory = o.version and T(_("Installed v%1"), o.version) or nil,
        action = o.on_update,
        role = "update",
    }

    return rows
end

return HomePage
