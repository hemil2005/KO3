--[[--
Pure helpers for AO3's tag autocomplete.

AO3 serves the tag picker as JSON at `/autocomplete/<type>?term=<text>`:

    [ { "id": "Hannibal (TV)", "name": "Hannibal (TV)" }, ... ]

`id` and `name` are both the canonical tag name; there is no numeric id to
carry. So a chosen tag travels as a name, not an id: the filter dialog keeps
the name in its pending selection, and Apply writes it to
`work_search[other_tag_names]` (include) or `work_search[excluded_tag_names]`
(exclude), where AO3 resolves it server-side. A bookmark page substitutes
`bookmark_search[...]`, and a bookmarker's tag uses its own
`other_bookmark_tag_names`/`excluded_bookmark_tag_names` field.

This module owns only the URL, the JSON parsing and the optional gzip decode;
main.lua owns the request, the debounce and the dialog. Keeping it pure makes
the offline tests independent of LuaSocket.
]]

local JSON = require("json")
local util = require("util")

local Autocomplete = {}

-- AO3's own picker starts at one character; two avoids a request on the first
-- keystroke of a short word while still feeling immediate.
Autocomplete.MIN_CHARS = 2
Autocomplete.LIMIT = 10
Autocomplete.DELAY = 0.35

-- The dimensions AO3's autocomplete routes exist for: the four work-tag
-- dimensions on every listing, plus `tag` for a bookmark page's bookmarker's
-- tags (AO3's own bookmark filter uses `/autocomplete/tag` for that field).
-- Ratings, warnings and categories are short fixed lists and keep their
-- embedded facets.
Autocomplete.TYPES = {
    fandom = true,
    character = true,
    relationship = true,
    freeform = true,
    tag = true,
}

function Autocomplete.isType(kind)
    return Autocomplete.TYPES[kind] == true
end

function Autocomplete.url(base_url, kind, term)
    return (base_url or "https://archiveofourown.org") .. "/autocomplete/"
        .. kind .. "?term=" .. util.urlEncode(term or "")
end

-- Decode a response body to a list of canonical names, in AO3's order and at
-- most LIMIT long. An empty array is a valid "nothing matches" answer; a body
-- that is not a list of objects/strings is malformed and returns nil.
function Autocomplete.parse(body)
    if type(body) ~= "string" or body == "" then return nil end
    local ok, decoded = pcall(JSON.decode, body)
    if not ok or type(decoded) ~= "table" then return nil end

    local names, seen = {}, {}
    for _, item in ipairs(decoded) do
        local name
        if type(item) == "table" then
            name = item.name or item.id
        elseif type(item) == "string" then
            name = item
        end
        if type(name) == "string" then
            name = name:gsub("^%s+", ""):gsub("%s+$", "")
            if name ~= "" and not seen[name] then
                seen[name] = true
                names[#names + 1] = name
                if #names >= Autocomplete.LIMIT then break end
            end
        end
    end
    return names
end

-- ---------------------------------------------------------------------------
-- Gzip
-- ---------------------------------------------------------------------------
--
-- The request asks for identity, but Cloudflare can still gzip a JSON answer.
-- ffi/zlib only exposes `uncompress` (zlib streams), so wrap the inflate
-- entry points directly and let zlib recognise the gzip header (windowBits 31,
-- i.e. 16 + MAX_WBITS). Every failure is quiet: a body that cannot be read is
-- the same as no suggestions.

local ffi = require("ffi")
local MAX_DECODED_BYTES = 4 * 1024 * 1024
local zlib_declared = false
local zlib_lib

local function loadZlib()
    if zlib_lib ~= nil then return zlib_lib or nil end
    zlib_lib = false
    local ok, lib = pcall(function()
        if ffi.loadlib then return ffi.loadlib("z", 1) end
        return ffi.load("z")
    end)
    if not ok or not lib then return nil end
    if not zlib_declared then
        local declared = pcall(ffi.cdef, [[
typedef struct {
    const unsigned char *next_in;
    unsigned int avail_in;
    unsigned long total_in;
    unsigned char *next_out;
    unsigned int avail_out;
    unsigned long total_out;
    const char *msg;
    void *state;
    void *zalloc;
    void *zfree;
    void *opaque;
    int data_type;
    unsigned long adler;
    unsigned long reserved;
} ko3_z_stream;
const char *zlibVersion(void);
int inflateInit2_(ko3_z_stream *strm, int windowBits, const char *version, int stream_size);
int inflate(ko3_z_stream *strm, int flush);
int inflateEnd(ko3_z_stream *strm);
]])
        if not declared then return nil end
        zlib_declared = true
    end
    zlib_lib = lib
    return lib
end

local function gunzip(data)
    local lib = loadZlib()
    if not lib or type(data) ~= "string" or #data < 18 then return nil end

    local input = ffi.new("uint8_t[?]", #data)
    ffi.copy(input, data, #data)
    local strm = ffi.new("ko3_z_stream[1]")
    strm[0].next_in = input
    strm[0].avail_in = #data
    if lib.inflateInit2_(strm, 16 + 15, lib.zlibVersion(),
            ffi.sizeof("ko3_z_stream")) ~= 0 then
        return nil
    end

    local chunks, total = {}, 0
    local out_size = math.max(4096, math.min(#data * 4, 65536))
    while true do
        local buffer = ffi.new("uint8_t[?]", out_size)
        strm[0].next_out = buffer
        strm[0].avail_out = out_size
        local result = lib.inflate(strm, 0) -- Z_NO_FLUSH
        local produced = out_size - tonumber(strm[0].avail_out)
        if produced > 0 then
            chunks[#chunks + 1] = ffi.string(buffer, produced)
            total = total + produced
            if total > MAX_DECODED_BYTES then
                lib.inflateEnd(strm)
                return nil
            end
        end
        if result == 1 then break end -- Z_STREAM_END
        -- Z_OK continues; Z_BUF_ERROR with nothing produced means the stream
        -- is truncated or the output buffer cannot grow any further.
        if result ~= 0 and result ~= -5 then
            lib.inflateEnd(strm)
            return nil
        end
        if result == -5 and produced == 0 then
            lib.inflateEnd(strm)
            return nil
        end
    end
    lib.inflateEnd(strm)
    return table.concat(chunks)
end

Autocomplete.gunzip = gunzip

local function contentEncoding(headers)
    for name, value in pairs(headers or {}) do
        if tostring(name):lower() == "content-encoding" then
            return tostring(value):lower()
        end
    end
    return ""
end

-- Return the JSON text of a response, inflating a gzipped body when one
-- arrives despite the identity request. `headers` is LuaSocket's lower-cased
-- table; the magic check covers a server that forgets the header.
function Autocomplete.decode(body, headers)
    if type(body) ~= "string" then return nil end
    if body:sub(1, 2) == "\31\139"
            or contentEncoding(headers):find("gzip", 1, true) then
        return gunzip(body)
    end
    return body
end

return Autocomplete
