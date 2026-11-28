--[[--
The settings screen.

Three options, in the same native row language as the rest of the app: the
label on the left, its state on the right, and a tap to change it. There is no
solid action bar because nothing here needs committing.
]]

local _ = require("gettext")

local SettingsPage = {}

-- `tags_expanded`, `card_style` and `check_subscriptions` are the stored
-- choices; each row flips and saves one.
function SettingsPage.build(o)
    local expanded = o.tags_expanded == true
    local follows = o.check_subscriptions ~= false
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
        {
            text = _("Subscribed works:"),
            mandatory = follows and _("On") or _("Off"),
            action = o.on_toggle_subscriptions,
            role = "subscriptions_default",
        },
    }
end

return SettingsPage
