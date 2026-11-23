--[[--
Shared native widgets for the plugin's designed screens.

The landing page and the work page share one visual language: inset content,
hairline rules, a solid primary bar, quiet section labels and native menu
rows. Keeping the primitives here means the two screens cannot drift apart.

Everything is built from stock KOReader widgets (TextWidget, TextBoxWidget,
FrameContainer, LineWidget, groups, InputContainer), so fonts, scaling and
e-ink rendering stay native.
]]

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InputContainer = require("ui/widget/container/inputcontainer")
local LineWidget = require("ui/widget/linewidget")
local Size = require("ui/size")
local TextWidget = require("ui/widget/textwidget")

local Uikit = {}

Uikit.SECONDARY = Blitbuffer.COLOR_DARK_GRAY
Uikit.RULE = Blitbuffer.COLOR_GRAY_5
Uikit.RULE_H = rawget(Size.line, "thin") or 1

function Uikit.rule(width)
    return LineWidget:new{
        dimen = Geom:new{ w = width, h = Uikit.RULE_H },
        background = Uikit.RULE,
    }
end

-- Full-bleed row content: native menu rows are inset by this padding, so
-- static panels use the same inset to keep one left edge down the screen.
function Uikit.padded(widget)
    return HorizontalGroup:new{
        HorizontalSpan:new{ width = Size.padding.fullscreen },
        widget,
        HorizontalSpan:new{ width = Size.padding.fullscreen },
    }
end

-- A tap target around an already-built widget (the primary bar is not a
-- native Button: an inverted bar needs a white label, which Button does not
-- expose).
function Uikit.tapArea(widget, width, height, callback)
    local area = InputContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = width, h = height },
    }
    area[1] = widget
    area.ges_events = {
        Tap = {
            GestureRange:new{ ges = "tap", range = area.dimen },
        },
    }
    area.onTap = function()
        callback()
        return true
    end
    return area
end

-- A full-width button. Primary is a solid black bar with a white label; the
-- secondary keeps the native outlined look. `checked` appends KOReader's own
-- checkmark (the mark its Buttons and tab strips use), so a toggle says
-- "on" in a language the device already speaks.
function Uikit.button(label, width, height, primary, callback, font_size, checked)
    local border = primary and 0 or Size.border.button
    local inner_w = math.max(1, width - 2 * border)
    local inner_h = math.max(1, height - 2 * border)
    local label_widget = TextWidget:new{
        text = checked and (label .. "  \u{2713}") or label,
        face = Font:getFace("cfont", font_size),
        bold = true,
        fgcolor = primary and Blitbuffer.COLOR_WHITE or Blitbuffer.COLOR_BLACK,
        max_width = math.max(1, inner_w - 2 * Size.padding.large),
    }
    local frame = FrameContainer:new{
        background = primary and Blitbuffer.COLOR_BLACK or Blitbuffer.COLOR_WHITE,
        color = Blitbuffer.COLOR_BLACK,
        bordersize = border,
        padding = 0,
        margin = 0,
        CenterContainer:new{
            dimen = Geom:new{ w = inner_w, h = inner_h },
            label_widget,
        },
    }
    return Uikit.tapArea(frame, width, height, callback)
end

-- A quiet group label: small, bold, secondary. It is not a control.
function Uikit.label(text, width, font_size)
    return TextWidget:new{
        text = text,
        face = Font:getFace("smallinfofont", font_size - 4),
        bold = true,
        fgcolor = Uikit.SECONDARY,
        max_width = width,
    }
end

return Uikit
