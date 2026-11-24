--[[--
The settings screen.

One option, in the same native row language as the rest of the app: the label
on the left, its state on the right, and a tap to change it. There is no
solid action bar because nothing here needs committing.
]]

local _ = require("gettext")

local SettingsPage = {}

-- `tags_expanded` is the stored default; `on_toggle` flips and saves it.
function SettingsPage.build(o)
    local expanded = o.tags_expanded == true
    return {
        {
            text = _("Expanded tags:"),
            mandatory = expanded and _("On") or _("Off"),
            action = o.on_toggle,
            role = "tags_default",
        },
    }
end

return SettingsPage
