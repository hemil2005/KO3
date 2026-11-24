--[[--
The settings screen.

Two options, in the same native row language as the rest of the app: the
label on the left, its state on the right, and a tap to change it. There is no
solid action bar because nothing here needs committing.
]]

local _ = require("gettext")

local SettingsPage = {}

-- `tags_expanded` and `card_style` are the stored choices; the two toggles
-- flip and save them.
function SettingsPage.build(o)
    local expanded = o.tags_expanded == true
    return {
        {
            text = _("Expanded tags:"),
            mandatory = expanded and _("On") or _("Off"),
            action = o.on_toggle,
            role = "tags_default",
        },
        {
            text = _("Work cards:"),
            mandatory = o.card_style == "legacy" and _("Legacy") or _("Modern"),
            action = o.on_toggle_card_style,
            role = "card_style",
        },
    }
end

return SettingsPage
