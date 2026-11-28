--[[--
Chapter counts for a saved work and its live page.

A downloaded AO3 work keeps the preface, and its stats list carries the same
"3/7" the website shows, so a saved work in progress can be compared with the
live page without opening (or even reading all of) the multi-megabyte file.
Nothing here touches the network: the caller fetches the live page only on a
tap, and this module only reads files already on the device.
]]

local util = require("util")
local _ = require("gettext")
local T = require("ffi/util").template

local WorkUpdate = {}

-- Only the preface is needed. AO3's downloadable HTML puts the work meta and
-- its stats before the first chapter, and the chapters after it can be many
-- megabytes; a bounded prefix keeps a check cheap on a reader with little RAM.
local PREFACE_BYTES = 128 * 1024

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

-- AO3 prints the chapter stat as "current/total", with "?" for a work whose
-- total is not set ("5/?"). Single-chapter works are "1/1", and a bare number
-- is an old export of the same fixed count. Anything else is unreadable.
function WorkUpdate.parseChapters(text)
    local s = trim(text):gsub("%s+", "")
    local current, total = s:match("^(%d+)/(%d+)$")
    if current then
        return tonumber(current), tonumber(total)
    end
    current = s:match("^(%d+)/%?$")
    if current then
        return tonumber(current), nil
    end
    current = s:match("^(%d+)$")
    if current then
        -- A lone count has no separate total: the number is both.
        return tonumber(current), tonumber(current)
    end
    return nil
end

local function plainStat(text)
    local s = text:gsub("<[^>]->", "")
    s = util.htmlEntitiesToUtf8(s)
    return trim(s:gsub("%s+", " "))
end

-- The saved copy's own chapter count, read from the preface only. Two values
-- (current, total) like parseChapters; nil when the file or its stat is
-- missing. A bounded pattern rather than a full parse: htmlparser would need
-- the whole document up front, and the stat is one element in the head.
function WorkUpdate.cachedChapters(path, bytes)
    if not path then return nil end
    local limit = tonumber(bytes)
    if not limit or limit < 1 then limit = PREFACE_BYTES end
    local file = io.open(path, "rb")
    if not file then return nil end
    local head = file:read(limit) or ""
    file:close()

    -- AO3 pairs a label (<dt class="chapters">Chapters:</dt>) with the value
    -- (<dd class="chapters">3/7</dd>), so take the first element that parses
    -- as a count and ignore the label. Either quote style is accepted: the
    -- stat is the one thing worth being forgiving about in a saved file.
    for body in head:gmatch("class=[\"']chapters[\"'][^>]*>(.-)</%a+>") do
        local current, total = WorkUpdate.parseChapters(plainStat(body))
        if current then return current, total end
    end
    return nil
end

-- AO3's chapter menu (`/works/<id>/navigate`) is the cheap view of a work: the
-- chapter list and nothing else, so one small request answers "is there a new
-- chapter?" without pulling the work's text, images or comment thread. AO3
-- renders the list as `ol.chapter.index` with one `li` per posted chapter; the
-- chapter links are the fallback if that wrapper ever changes. Returns nil for
-- a page that is not a chapter list (a login redirect, a challenge, a 404), so
-- the caller can tell "no count" from "no chapters".
function WorkUpdate.parseChapterIndex(html)
    if type(html) ~= "string" or html == "" then return nil end

    local list = html:match(
        "<ol[^>]-class=[\"'][^\"']*chapter[^\"']*[\"'][^>]*>(.-)</ol>")
    local count = 0
    if list then
        for _ in list:gmatch("<li[%s>]") do count = count + 1 end
    end

    if count == 0 then
        local seen, unique = {}, 0
        for id in html:gmatch("href=[\"']/works/%d+/chapters/(%d+)") do
            if not seen[id] then
                seen[id] = true
                unique = unique + 1
            end
        end
        count = unique
    end

    if count == 0 then return nil end
    return count
end

-- `value` may be a { current, total } table, a chapter string ("3/7"), or
-- nil. Callers keep whichever form they already have; nothing is fetched.
local function countsOf(value)
    if type(value) == "table" then
        return value.current, value.total
    end
    return WorkUpdate.parseChapters(value)
end

-- Compare the saved copy with the live page. `added` is content, never
-- negative: a work whose count went backwards (a revision, a split) is up to
-- date as far as new reading goes. `unknown` is true when either side has no
-- readable current count, and then nothing should be offered for download.
function WorkUpdate.compare(old, new)
    local old_current, old_total = countsOf(old)
    local new_current, new_total = countsOf(new)

    local added = 0
    if old_current and new_current then
        added = math.max(0, new_current - old_current)
    end

    local complete = false
    if new_current and new_total then
        complete = new_current == new_total
    end

    return {
        old_current = old_current,
        old_total = old_total,
        new_current = new_current,
        new_total = new_total,
        added = added,
        up_to_date = added == 0,
        complete = complete,
        unknown = old_current == nil or new_current == nil,
    }
end

-- "3/7", "3/?" for a work whose total is not set. Shared by the details row
-- and the updates screen so both say the same thing.
function WorkUpdate.chapterPair(current, total)
    return T(_("%1/%2"), current, total or "?")
end

-- True when the live page carries something the saved copy does not: more
-- chapters, or a total that has just been filled in to the current count
-- ("5/?" -> "5/5"), which is how a work gets marked complete.
function WorkUpdate.isNew(result)
    if not result or result.unknown then return false end
    if result.added > 0 then return true end
    local was_complete = result.old_total ~= nil
        and result.old_current == result.old_total
    return result.complete and not was_complete
end

-- The one-line sentence a check shows. Short enough for an e-ink dialog.
function WorkUpdate.message(result)
    if not result or result.unknown then
        return _("Chapter count unavailable")
    end
    local was_complete = result.old_total ~= nil
        and result.old_current == result.old_total
    if result.complete and not was_complete then
        return T(_("The work is now complete · %1"),
            WorkUpdate.chapterPair(result.new_current, result.new_total))
    end
    if result.added > 0 then
        return T(_("%1 new chapters · %2 → %3"), result.added,
            WorkUpdate.chapterPair(result.old_current, result.old_total),
            WorkUpdate.chapterPair(result.new_current, result.new_total))
    end
    return T(_("Up to date · %1"),
        WorkUpdate.chapterPair(result.new_current, result.new_total))
end

-- A work that can still grow chapters. An unknown total ("3/?") is the
-- definition of a work in progress; a known equal pair ("2/2", "7/7") is
-- finished and already has the plain Refresh action, so the check would only
-- cost a request to say "up to date". A one-shot can never grow.
function WorkUpdate.isWip(chapters)
    local current, total = countsOf(chapters)
    if not current then return false end
    if not total then return true end
    return current < total
end

return WorkUpdate
