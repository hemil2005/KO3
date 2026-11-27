--[[--
Static facets for AO3's keyword search.

`/works/search` renders the search-results page, which carries no
`#work-filters` sidebar: a live fetch shows the only form is the header search
with `work_search[query]`. So search results cannot borrow the page's facets the
way tag, fandom and author listings do. The search action does still read the
advanced form's fixed lists:

    work_search[rating_ids][]=10
    work_search[archive_warning_ids][]=14
    work_search[category_ids][]=116
    work_search[complete]=T
    work_search[crossover]=F

Names and ids were read from AO3's live Edit Search form on 2026-11-27, and
`spec/fixtures/search_form.html` pins them, so a re-seed that moved an id fails
a test rather than a filter silently doing nothing. Typed tags do not live here:
they come from AO3's autocomplete and travel as names.

The fixed dimensions are Include-only, as on AO3's form (one rating select and
checkbox lists for warnings and categories, no Exclude side). The four work-tag
dimensions still take typed names on both sides.
]]

local _ = require("gettext")

local SearchFilters = {}

-- { id, name } in the order AO3's form prints them.
SearchFilters.RATINGS = {
    { "9", _("Not Rated") },
    { "10", _("General Audiences") },
    { "11", _("Teen And Up Audiences") },
    { "12", _("Mature") },
    { "13", _("Explicit") },
}

SearchFilters.WARNINGS = {
    { "14", _("Creator Chose Not To Use Archive Warnings") },
    { "17", _("Graphic Depictions Of Violence") },
    { "18", _("Major Character Death") },
    { "16", _("No Archive Warnings Apply") },
    { "19", _("Rape/Non-Con") },
    { "20", _("Underage Sex") },
}

SearchFilters.CATEGORIES = {
    { "116", _("F/F") },
    { "22", _("F/M") },
    { "21", _("Gen") },
    { "23", _("M/M") },
    { "2246", _("Multi") },
    { "24", _("Other") },
}

SearchFilters.COMPLETION = {
    { "T", _("Complete works only") },
    { "F", _("Works in progress only") },
}

SearchFilters.CROSSOVERS = {
    { "F", _("Exclude crossovers") },
    { "T", _("Only crossovers") },
}

SearchFilters.DIMENSIONS = {
    { key = "rating", label = _("Rating"), single = true },
    { key = "archive_warning", label = _("Archive Warning") },
    { key = "category", label = _("Category") },
    { key = "complete", label = _("Completion"), single = true },
    { key = "crossover", label = _("Crossovers"), single = true },
    { key = "fandom", label = _("Fandom") },
    { key = "character", label = _("Character") },
    { key = "relationship", label = _("Relationship") },
    { key = "freeform", label = _("Additional Tags") },
}

-- What the search action reads. `_ids` lists repeat; completion and crossovers
-- are single values.
SearchFilters.ID_KEYS = {
    rating = "rating_ids",
    archive_warning = "archive_warning_ids",
    category = "category_ids",
}
SearchFilters.SINGLE_KEYS = { complete = true, crossover = true }

function SearchFilters.isSearchUrl(url)
    if type(url) ~= "string" then return false end
    local path, query = url:match("^([^?#]*)%??([^#]*)")
    path = path or url
    if path:match("/works/search$") then return true end
    -- A hand-written or paged URL may use the index path with a search query.
    return path:match("/works$") ~= nil
        and (query or ""):find("work_search", 1, true) ~= nil
end

local function facet(kind, id, name, control)
    return {
        id = id,
        name = name,
        type = kind,
        action = "include",
        control = control,
    }
end

-- A fresh facets table on every call, shaped exactly like a parsed page's, so
-- `filterDimensions`, the dialog and `filterUrl` need no special case.
function SearchFilters.facets()
    local facets = {}
    local function add(kind, entries, control)
        local list = {}
        for _, entry in ipairs(entries) do
            list[#list + 1] = facet(kind, entry[1], entry[2], control)
        end
        facets[kind] = { include = list, exclude = {} }
    end
    add("rating", SearchFilters.RATINGS, "radio")
    add("archive_warning", SearchFilters.WARNINGS)
    add("category", SearchFilters.CATEGORIES)
    add("complete", SearchFilters.COMPLETION, "radio")
    add("crossover", SearchFilters.CROSSOVERS, "radio")
    for _, kind in ipairs({ "fandom", "character", "relationship", "freeform" }) do
        facets[kind] = { include = {}, exclude = {} }
    end
    return facets
end

function SearchFilters.isIndexed(kind)
    return SearchFilters.ID_KEYS[kind] ~= nil
end

function SearchFilters.isSingle(kind)
    return SearchFilters.SINGLE_KEYS[kind] == true
end

-- The exact `work_search` key a chosen facet is written to, for Apply and for
-- paging (AO3's own links are rebuilt from the selection).
function SearchFilters.paramKey(kind)
    if SearchFilters.ID_KEYS[kind] then
        return "work_search[" .. SearchFilters.ID_KEYS[kind] .. "][]"
    end
    if SearchFilters.SINGLE_KEYS[kind] then
        return "work_search[" .. kind .. "]"
    end
end

-- Recognize a search filter already on a pasted URL, so its box starts ticked.
function SearchFilters.adoptKey(decoded_key)
    for kind, name in pairs(SearchFilters.ID_KEYS) do
        if decoded_key == "work_search[" .. name .. "][]" then return kind end
    end
    for kind in pairs(SearchFilters.SINGLE_KEYS) do
        if decoded_key == "work_search[" .. kind .. "]" then return kind end
    end
end

function SearchFilters.isFilterKey(decoded_key)
    return SearchFilters.adoptKey(decoded_key) ~= nil
end

return SearchFilters
