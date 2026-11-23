--[[--
The account screen.

The reader's own page, modelled on the four lists AO3 keeps for an account:
Bookmarks, Marked for later, History and Subscriptions. It is a contents
page, not a settings page: a name at the top, the lists as native rows, the
reader's author page, and the way out at the bottom.

The lists are rows rather than a tab strip because the four labels do not fit
one 600px strip ("Marked for later" alone is wider than a quarter of it), and
a list you scan vertically is the catalogue's own shape. Each row is fetched
only when tapped; this module draws, it does not request.

The one action on the screen is Log out, and it is outlined: leaving is not
the page's purpose, so it must not be the solid bar.
]]

local Blitbuffer = require("ffi/blitbuffer")
local Font = require("ui/font")
local Geom = require("ui/geometry")
local LeftContainer = require("ui/widget/container/leftcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local _ = require("gettext")
local T = require("ffi/util").template

local SOURCE = debug.getinfo(1, "S").source:sub(2)
local Uikit = dofile((SOURCE:gsub("accountpage%.lua$", "uikit.lua")))

local AccountPage = {}

local GUTTER = Size.span.horizontal_default
local GROUP_GAP = Size.padding.large * 2

-- The four lists AO3 keeps, in the order the site puts them. The hint says
-- what is inside without guessing at counts, which are not known until a
-- list is fetched.
AccountPage.LISTS = {
    {
        id = "bookmarks", label = _("Bookmarks"),
        hint = _("Works and series you saved"),
    },
    {
        id = "marked", label = _("Marked for later"),
        hint = _("Your reading queue"),
    },
    {
        id = "history", label = _("History"),
        hint = _("Works you opened"),
    },
    {
        id = "subscriptions", label = _("Subscriptions"),
        hint = _("Updates you follow"),
    },
}

-- The name is the page's headline; "Signed in to AO3" qualifies it. A long
-- pseud wraps rather than truncating: it is the reader's own name.
function AccountPage.hero(name, width, font_size)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = TextBoxWidget:new{
        text = name,
        face = Font:getFace("smallinfofont", font_size + 6),
        bold = true,
        width = width,
        height_adjust = true,
        alignment = "left",
    }
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    group[#group + 1] = TextWidget:new{
        text = _("Signed in to AO3"),
        face = Font:getFace("smallinfofont", font_size - 4),
        fgcolor = Uikit.SECONDARY,
        max_width = width,
    }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    group[#group + 1] = Uikit.rule(width)
    return group
end

-- A quiet group label, pinned to the gutter the way the landing page's
-- groups are.
function AccountPage.section_label(text, width, font_size, top)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = top or GROUP_GAP }
    group[#group + 1] = Uikit.label(text, width, font_size)
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    return LeftContainer:new{
        dimen = Geom:new{ w = width, h = group:getSize().h },
        group,
    }
end

-- The way out: outlined, full width, with one honest line underneath. Saved
-- downloads live on the device, so logging out does not take them away.
function AccountPage.session(width, font_size, on_logout)
    local height = math.floor(font_size * 2.4 + 0.5)
    local group = VerticalGroup:new{ align = "left" }
    group[#group + 1] = VerticalSpan:new{ width = GROUP_GAP }
    group[#group + 1] = Uikit.button(_("Log out"), width, height, false,
        on_logout, font_size - 2)
    group[#group + 1] = VerticalSpan:new{ width = Size.span.vertical_large }
    group[#group + 1] = TextWidget:new{
        text = _("Saved works stay on this device."),
        face = Font:getFace("smallinfofont", font_size - 5),
        fgcolor = Blitbuffer.COLOR_GRAY_6,
        max_width = width,
    }
    group[#group + 1] = VerticalSpan:new{ width = Size.padding.default }
    return group
end

-- Rows for the plugin's Menu. `on_list(id)` opens a list, `on_works()` opens
-- the reader's author page, `on_logout()` ends the session.
function AccountPage.build(o)
    local name = o.name or _("your account")
    local width = o.width
    local font_size = o.font_size
    local rows = {}

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(AccountPage.hero(name, width, font_size)),
        role = "account_hero",
    }

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(AccountPage.section_label(
            _("Lists"), width, font_size, GUTTER)),
        role = "lists_label",
        keep_with_next = true,
    }
    for _, list in ipairs(AccountPage.LISTS) do
        rows[#rows + 1] = {
            text = list.label,
            mandatory = list.hint,
            action = function() o.on_list(list.id) end,
            role = "list_" .. list.id,
        }
    end

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(AccountPage.section_label(
            _("Author"), width, font_size)),
        role = "author_label",
        keep_with_next = true,
    }
    rows[#rows + 1] = {
        text = T(_("Works by %1"), name),
        mandatory = _("Author page"),
        action = o.on_works,
        role = "works",
    }

    rows[#rows + 1] = {
        ao3_static = Uikit.padded(AccountPage.session(
            width, font_size, o.on_logout)),
        role = "session",
    }
    return rows
end

return AccountPage
