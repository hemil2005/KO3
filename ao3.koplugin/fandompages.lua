--[[--
Bounded paging over the embedded fandom letter files.

Each `<dir>/<category>/<letter>.tsv.z` is a 4-byte little-endian uncompressed
length followed by a zlib stream. The uncompressed text is TSV:

    name<TAB>url<TAB>count<LF>

A letter can hold thousands of entries. The UI only needs a small window, so
`page()` returns plain `{ name, url, count }` tables for at most 100 rows and
never menu rows, actions or closures. URLs are returned exactly as stored.

One decompressed letter is cached at a time: changing category or letter
replaces the previous text, and `clearCache()` releases it explicitly. Within
one letter, consecutive pages scan the cached text and never decompress again.

Usage:
    local FandomPages = dofile(plugin_path .. "/fandompages.lua")
    local page, err = FandomPages.page(dir, category.index, letter, offset, 100)
    -- page.entries, page.total, page.next_offset, page.has_more
]]

local FandomPages = {}

FandomPages.MAX_PAGE_SIZE = 100
FandomPages.DEFAULT_PAGE_SIZE = 100
-- The largest shipped letter is under 700 KB uncompressed. Keep a generous
-- ceiling so a corrupted header cannot make ffi/zlib allocate gigabytes.
FandomPages.MAX_RAW_BYTES = 4 * 1024 * 1024
FandomPages.MAX_FILE_BYTES = 8 * 1024 * 1024

-- At most one entry: { path = ..., text = ..., total = ... }.
local cache

local zlib_module

local function getZlib()
    if zlib_module then return zlib_module end
    local ok, zlib = pcall(require, "ffi/zlib")
    if ok and type(zlib) == "table"
            and type(zlib.zlib_uncompress) == "function" then
        zlib_module = zlib
        return zlib
    end
end

local function readFile(path)
    local file, err = io.open(path, "rb")
    if not file then
        return nil, "cannot open fandom data file: " .. tostring(err)
    end

    local size = file:seek("end")
    if not size then
        file:close()
        return nil, "cannot read fandom data file size"
    end
    if size > FandomPages.MAX_FILE_BYTES then
        file:close()
        return nil, "fandom data file is too large"
    end
    if file:seek("set", 0) == nil then
        file:close()
        return nil, "cannot rewind fandom data file"
    end

    local raw = file:read("*a")
    file:close()
    if type(raw) ~= "string" then
        return nil, "cannot read fandom data file"
    end
    return raw
end

-- Validate the header before touching zlib, then decompress into a buffer
-- whose size is known to be bounded.
local function decompressLetter(raw)
    if #raw < 5 then
        return nil, "fandom data file is truncated"
    end

    local b1, b2, b3, b4 = raw:byte(1, 4)
    local raw_size = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
    if raw_size > FandomPages.MAX_RAW_BYTES then
        return nil, "fandom data length is too large"
    end
    if raw_size == 0 then
        return ""
    end

    local compressed = raw:sub(5)
    if compressed == "" then
        return nil, "fandom data file is truncated"
    end

    local zlib = getZlib()
    if not zlib then
        return nil, "zlib support is not available"
    end

    local ok, text = pcall(zlib.zlib_uncompress, compressed, raw_size)
    if not ok or type(text) ~= "string" then
        return nil, "could not decompress fandom data file"
    end
    if #text < raw_size then
        return nil, "fandom data stream is shorter than its declared length"
    end
    return text
end

-- Return the next valid TSV row at or after `pos`, plus the position after
-- it. Blank and malformed lines are skipped. The fourth return value is the
-- new position, so callers can scan without retaining row tables.
local function nextRow(text, pos)
    local len = #text
    while pos <= len do
        local newline = text:find("\n", pos, true)
        local line
        if newline then
            line = text:sub(pos, newline - 1)
            pos = newline + 1
        else
            line = text:sub(pos)
            pos = len + 1
        end

        if line:sub(-1) == "\r" then
            line = line:sub(1, -2)
        end

        if line ~= "" then
            local name, url, count = line:match("^(.-)\t(.-)\t(.*)$")
            if name and name ~= "" and url ~= "" then
                return name, url, count, pos
            end
        end
    end
end

local function countRows(text)
    local total = 0
    local pos = 1
    while true do
        local name, _, _, next_pos = nextRow(text, pos)
        if not name then break end
        total = total + 1
        pos = next_pos
    end
    return total
end

-- Collect only the requested window. Rows before `offset` are counted but
-- not turned into tables.
local function windowRows(text, offset, limit)
    local rows = {}
    local index = 0
    local pos = 1

    while #rows < limit do
        local name, url, count, next_pos = nextRow(text, pos)
        if not name then break end
        if index >= offset then
            rows[#rows + 1] = { name = name, url = url, count = count }
        end
        index = index + 1
        pos = next_pos
    end

    return rows
end

local function loadLetter(path)
    if cache and cache.path == path then
        return cache
    end

    -- Drop the previous letter before a possible failure, so at most one
    -- decompressed text exists even when the next file is corrupt.
    cache = nil

    local raw, err = readFile(path)
    if not raw then return nil, err end

    local text, decompress_err = decompressLetter(raw)
    if not text then return nil, decompress_err end

    cache = {
        path = path,
        text = text,
        total = countRows(text),
    }
    return cache
end

local function parseArgs(dir, category_index, letter, offset, page_size)
    if type(dir) ~= "string" or dir == "" then
        return nil, "fandom data directory is required"
    end
    if type(category_index) ~= "number" or category_index < 1
            or category_index % 1 ~= 0 then
        return nil, "fandom category index is invalid"
    end
    if type(letter) ~= "string" or not letter:match("^[A-Z#]$") then
        return nil, "fandom letter is invalid"
    end

    if offset == nil then offset = 0 end
    if page_size == nil then page_size = FandomPages.DEFAULT_PAGE_SIZE end

    if type(offset) ~= "number" or offset < 0 or offset % 1 ~= 0 then
        return nil, "fandom page offset is invalid"
    end
    if type(page_size) ~= "number" or page_size < 1
            or page_size % 1 ~= 0 then
        return nil, "fandom page size is invalid"
    end
    if page_size > FandomPages.MAX_PAGE_SIZE then
        page_size = FandomPages.MAX_PAGE_SIZE
    end

    local base = dir:gsub("/+$", "")
    if base == "" then
        return nil, "fandom data directory is required"
    end

    return {
        dir = base,
        offset = offset,
        page_size = page_size,
    }
end

--[[--
Return one bounded page of a letter.

@param dir            Category root, e.g. `<plugin>/data/fandoms`.
@param category_index Category number from index.lua.
@param letter         One of "A".."Z" or "#".
@param offset         Zero-based entry offset (default 0).
@param page_size      Entries to return (default 100, capped at 100).

@treturn table|nil Page `{ entries, total, offset, page_size, next_offset,
                          has_more }`, where each entry is
                          `{ name, url, count }`. `next_offset` is nil on the
                          last page.
@treturn string|nil Error message when the file or arguments are unusable.
]]
function FandomPages.page(dir, category_index, letter, offset, page_size)
    local args, err = parseArgs(dir, category_index, letter, offset, page_size)
    if not args then return nil, err end

    local path = args.dir .. "/" .. category_index .. "/" .. letter .. ".tsv.z"
    local letter_data, load_err = loadLetter(path)
    if not letter_data then return nil, load_err end

    local entries = windowRows(
        letter_data.text, args.offset, args.page_size)
    local after = args.offset + #entries
    local next_offset
    if after < letter_data.total then
        next_offset = after
    end

    return {
        entries = entries,
        total = letter_data.total,
        offset = args.offset,
        page_size = args.page_size,
        next_offset = next_offset,
        has_more = next_offset ~= nil,
    }
end

-- Find the first matching name without creating menu rows. The returned
-- zero-based offset can be rounded down to a window boundary by the UI.
function FandomPages.find(dir, category_index, letter, query)
    local args, err = parseArgs(dir, category_index, letter)
    if not args then return nil, err end
    if type(query) ~= "string" or query == "" then
        return nil, "a fandom name is required"
    end
    local path = args.dir .. "/" .. category_index .. "/" .. letter .. ".tsv.z"
    local data, load_err = loadLetter(path)
    if not data then return nil, load_err end

    local needle = query:lower()
    local pos, offset = 1, 0
    while true do
        local name, _, _, next_pos = nextRow(data.text, pos)
        if not name then break end
        if name:lower():find(needle, 1, true) then
            return offset
        end
        offset = offset + 1
        pos = next_pos
    end
    return nil
end

-- Release the one cached letter. Callers normally just open another letter;
-- this is for tests and for dropping memory before a long unrelated task.
function FandomPages.clearCache()
    cache = nil
end

return FandomPages
