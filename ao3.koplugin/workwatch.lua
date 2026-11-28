--[[--
Quiet checks for saved works in progress.

The downloaded copy carries its chapter count in the preface, and AO3's
chapter menu (`/works/<id>/navigate`) answers with the live chapter list in
about a kilobyte, so asking "is there a new chapter?" neither refetches the
saved file nor pulls a work page. This module is the part that needs no
network: which saved works are due, what a check found, and how many chapters
the reader has not read yet.

State lives in `settings/ao3_prefs.lua` beside the other local facts, as one
entry per work id: `{ ts = last check, chapters = live count, gone = true }`.
Nothing here identifies the reader, and Log out keeps the entries.

A check is only ever a request, never a download: the caller fetches, records
and stops. The reader still confirms before any work is replaced.
]]

local SOURCE = debug.getinfo(1, "S").source:sub(2)
local WorkUpdate = dofile((SOURCE:gsub("workwatch%.lua$", "workupdate.lua")))

local WorkWatch = {}

-- A work is asked about at most once a day, and a single run stops after a
-- dozen so opening the plugin never becomes a crawl. Checks are spaced apart
-- in time by the caller; this module only says what is due.
WorkWatch.INTERVAL = 24 * 60 * 60
WorkWatch.BUDGET = 12
WorkWatch.DELAY = 20
WorkWatch.SPACING = 4

-- Only the preface is needed for the saved count, and the stats sit near the
-- top of AO3's downloaded HTML. A smaller window than the update check's keeps
-- a run over a full shelf cheap on a reader with little RAM.
WorkWatch.PREFACE_BYTES = 64 * 1024

-- A hand-edited or very old preferences file cannot grow without bound.
WorkWatch.MAX_ENTRIES = 500

local function key(id)
    return tostring(id)
end

function WorkWatch.entry(prefs, id)
    local checks = prefs and prefs.work_checks
    if type(checks) ~= "table" or id == nil then return nil end
    return checks[key(id)]
end

-- The saved copy's own count, or nil when the file or its stat is missing.
-- Returns current and total, exactly like WorkUpdate.cachedChapters.
function WorkWatch.localChapters(item)
    if not item or not item.path then return nil end
    return WorkUpdate.cachedChapters(item.path, WorkWatch.PREFACE_BYTES)
end

-- Chapters the check saw beyond the saved copy. The count is recomputed from
-- the file each time, so refreshing the work makes the badge disappear without
-- any extra bookkeeping.
function WorkWatch.added(prefs, item)
    local entry = WorkWatch.entry(prefs, item and item.id)
    if not entry or entry.gone or not entry.chapters then return 0 end
    local current = WorkWatch.localChapters(item)
    if not current then return 0 end
    return math.max(0, entry.chapters - current)
end

local function dropOldestEntry(checks)
    local oldest_id, oldest_ts
    for id, entry in pairs(checks) do
        local ts = tonumber(entry and entry.ts) or 0
        if not oldest_ts or ts < oldest_ts then
            oldest_id, oldest_ts = id, ts
        end
    end
    if oldest_id then checks[oldest_id] = nil end
end

-- Remember one answer. `gone` means AO3 returned 404 for the work: the saved
-- copy is still readable, so nothing is deleted, but there is no point asking
-- again. A request that produced no readable count records nothing, so the
-- work is retried on the next run instead of being marked up to date.
function WorkWatch.record(prefs, id, chapters, now, gone)
    if not prefs or id == nil then return end
    local checks = type(prefs.work_checks) == "table" and prefs.work_checks or {}
    prefs.work_checks = checks
    local entry = { ts = math.floor(tonumber(now) or os.time()) }
    if gone then
        entry.gone = true
    else
        local count = tonumber(chapters)
        if not count or count < 1 then return end
        entry.chapters = math.floor(count)
    end
    checks[key(id)] = entry

    local size = 0
    for _ in pairs(checks) do size = size + 1 end
    while size > WorkWatch.MAX_ENTRIES do
        dropOldestEntry(checks)
        size = size - 1
    end
end

-- A work is due when it can still grow (never for a one-shot or a finished
-- save), has not been checked within the interval, and its preface is
-- readable. `interval = 0` makes every WIP due, for the manual run.
function WorkWatch.due(prefs, item, now, interval)
    if not item or not item.id then return false end
    local entry = WorkWatch.entry(prefs, item.id)
    if entry and entry.gone then return false end
    local wait = interval or WorkWatch.INTERVAL
    if entry and entry.ts and (now - entry.ts) < wait then return false end
    local current, total = WorkWatch.localChapters(item)
    if not current then return false end
    return WorkUpdate.isWip{ current = current, total = total }
end

-- Forget ids whose files are no longer on the shelf, so an uninstalled work
-- cannot keep a check entry forever.
function WorkWatch.prune(prefs, items)
    local checks = prefs and prefs.work_checks
    if type(checks) ~= "table" then return end
    local present = {}
    for _, item in ipairs(items or {}) do
        if item and item.id then present[key(item.id)] = true end
    end
    for id in pairs(checks) do
        if not present[id] then checks[id] = nil end
    end
end

-- The works one run should ask about, oldest check first so a shelf larger
-- than the budget rotates instead of starving its tail.
function WorkWatch.plan(items, prefs, now, opts)
    opts = opts or {}
    now = now or os.time()
    local interval = opts.force and 0 or (opts.interval or WorkWatch.INTERVAL)
    local budget = opts.budget or WorkWatch.BUDGET
    local due = {}
    for _, item in ipairs(items or {}) do
        if WorkWatch.due(prefs, item, now, interval) then
            local entry = WorkWatch.entry(prefs, item.id)
            due[#due + 1] = {
                item = item,
                ts = (entry and tonumber(entry.ts)) or 0,
            }
        end
    end
    table.sort(due, function(a, b)
        if a.ts ~= b.ts then return a.ts < b.ts end
        return key(a.item.id) < key(b.item.id)
    end)

    local queue = {}
    for i = 1, math.min(#due, math.max(0, budget)) do
        queue[i] = due[i].item
    end
    WorkWatch.prune(prefs, items)
    return queue
end

-- Everything the notifications screen lists: saved works with chapters the
-- copy does not have, plus works AO3 no longer serves.
function WorkWatch.updates(prefs, items)
    local out = {}
    for _, item in ipairs(items or {}) do
        local entry = WorkWatch.entry(prefs, item.id)
        if entry then
            if entry.gone then
                out[#out + 1] = { item = item, gone = true }
            else
                local current, total = WorkWatch.localChapters(item)
                local live = tonumber(entry.chapters)
                if current and live and live > current then
                    out[#out + 1] = {
                        item = item,
                        added = live - current,
                        current = current,
                        total = total,
                        live = live,
                    }
                end
            end
        end
    end
    return out
end

-- True when a check has found something since the reader last opened the
-- list: the bell carries its dot, and opening the list clears it.
function WorkWatch.unread(prefs, items, seen_ts)
    local seen = tonumber(seen_ts) or 0
    for _, item in ipairs(items or {}) do
        local entry = WorkWatch.entry(prefs, item.id)
        if entry and not entry.gone and (tonumber(entry.ts) or 0) > seen
                and WorkWatch.added(prefs, item) > 0 then
            return true
        end
    end
    return false
end

return WorkWatch
