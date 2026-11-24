-- KOReader busted spec for bounded fandom letter paging.
--
-- From a KOReader checkout with this plugin symlinked into plugins/:
--   ln -s ../../plugins/ao3.koplugin/spec/ao3_fandompages_spec.lua spec/unit/
--   ./kodev test --busted=--pattern=ao3_fandompages_spec front
--
-- The letter files are built in a temp directory through the same
-- 4-byte length + ffi/zlib format the shipped snapshot uses.

require("commonrequire")

local lfs = require("libs/libkoreader-lfs")
local zlib = require("ffi/zlib")

local FandomPages = dofile("plugins/ao3.koplugin/fandompages.lua")

local tmp_root

local function remove_tree(path)
    local mode = lfs.attributes(path, "mode")
    if mode == "directory" then
        for entry in lfs.dir(path) do
            if entry ~= "." and entry ~= ".." then
                remove_tree(path .. "/" .. entry)
            end
        end
        lfs.rmdir(path)
    elseif mode then
        os.remove(path)
    end
end

local function ensure_dir(path)
    if lfs.attributes(path, "mode") ~= "directory" then
        assert(lfs.mkdir(path))
    end
    return path
end

-- Write the exact on-disk format: little-endian raw length + zlib stream.
local function write_letter_bytes(path, raw_size, compressed)
    local f = assert(io.open(path, "wb"))
    f:write(string.char(
        raw_size % 256,
        math.floor(raw_size / 256) % 256,
        math.floor(raw_size / 65536) % 256,
        math.floor(raw_size / 16777216) % 256))
    f:write(compressed)
    f:close()
end

local function write_letter_file(path, text)
    write_letter_bytes(path, #text, zlib.zlib_compress(text))
end

local function make_letter(subdir, letter, text)
    local dir = ensure_dir(tmp_root .. "/" .. subdir)
    local category_dir = ensure_dir(dir .. "/1")
    write_letter_file(category_dir .. "/" .. letter .. ".tsv.z", text)
    return dir
end

local function with_uncompress_counter(fn)
    local real = zlib.zlib_uncompress
    local calls = 0
    zlib.zlib_uncompress = function(zdata, size)
        calls = calls + 1
        return real(zdata, size)
    end
    local ok, err = pcall(fn, function() return calls end)
    zlib.zlib_uncompress = real
    assert(ok, err)
    return calls
end

local function many_entries(count)
    local lines = {}
    for i = 1, count do
        lines[i] = string.format(
            "Fandom %03d\t/tags/Fandom%%20%03d/works\t%d", i, i, i)
    end
    return table.concat(lines, "\n") .. "\n"
end

-- Four rows, sorted the way the build script sorts them. The third row has
-- no count and the second URL keeps the literal *a* used by AO3.
local SAMPLE = table.concat({
    "Alpha Fandom\t/tags/Alpha%20Fandom/works\t10",
    "Ampersand & Co\t/tags/Ampersand%20*a*%20Co/works\t5",
    "Archie\t/tags/Archie/works\t",
    "Zeta Archive\t/tags/Zeta%20Archive/works\t42",
}, "\n") .. "\n"

-- A term may sit anywhere in the name, and the catalogue's own casing is not
-- the reader's: mixed case, a space-joined name and a lower-case prefix all
-- have to answer to "cyber".
local SEARCH_SAMPLE = table.concat({
    "Alpha Fandom\t/tags/Alpha%20Fandom/works\t10",
    "Cyber Sled\t/tags/Cyber%20Sled/works\t1",
    "Cyberpunk 2077\t/tags/Cyberpunk%202077/works\t10962",
    "cyberpunkdreams\t/tags/cyberpunkdreams/works\t12",
    "Zeta Archive\t/tags/Zeta%20Archive/works\t42",
}, "\n") .. "\n"

setup(function()
    tmp_root = os.tmpname()
    os.remove(tmp_root)
    assert(lfs.mkdir(tmp_root))
end)

teardown(function()
    if FandomPages and FandomPages.clearCache then
        FandomPages.clearCache()
    end
    if tmp_root then
        remove_tree(tmp_root)
    end
end)

describe("fandom letter pages", function()
    before_each(function()
        FandomPages.clearCache()
    end)

    describe("page windows", function()
        it("returns a bounded window with exact urls", function()
            local dir = make_letter("window", "A", SAMPLE)
            local page, err = FandomPages.page(dir, 1, "A", 0, 2)

            assert.is_nil(err)
            assert.is_truthy(page)
            assert.are.equal(4, page.total)
            assert.are.equal(0, page.offset)
            assert.are.equal(2, page.page_size)
            assert.are.equal(2, page.next_offset)
            assert.is_true(page.has_more)
            assert.are.equal(2, #page.entries)

            assert.are.equal("Alpha Fandom", page.entries[1].name)
            assert.are.equal("/tags/Alpha%20Fandom/works", page.entries[1].url)
            assert.are.equal("10", page.entries[1].count)
            assert.is_nil(page.entries[1].action)

            assert.are.equal("Ampersand & Co", page.entries[2].name)
            assert.are.equal(
                "/tags/Ampersand%20*a*%20Co/works", page.entries[2].url)
            assert.are.equal("5", page.entries[2].count)
        end)

        it("returns the last partial page without a next offset", function()
            local dir = make_letter("window_tail", "A", SAMPLE)
            local page, err = FandomPages.page(dir, 1, "A", 2, 2)

            assert.is_nil(err)
            assert.are.equal(4, page.total)
            assert.are.equal(2, #page.entries)
            assert.are.equal("Archie", page.entries[1].name)
            assert.are.equal("", page.entries[1].count)
            assert.are.equal("Zeta Archive", page.entries[2].name)
            assert.is_nil(page.next_offset)
            assert.is_false(page.has_more)
        end)

        it("defaults page size to 100 and accepts an offset", function()
            local dir = make_letter("window_default", "A", many_entries(120))
            local page, err = FandomPages.page(dir, 1, "A", 100)

            assert.is_nil(err)
            assert.are.equal(100, page.page_size)
            assert.are.equal(100, page.offset)
            assert.are.equal(20, #page.entries)
            assert.are.equal("Fandom 101", page.entries[1].name)
            assert.is_nil(page.next_offset)
        end)

        it("caps a larger requested page size at 100", function()
            local dir = make_letter("window_cap", "A", many_entries(120))
            local page, err = FandomPages.page(dir, 1, "A", 0, 1000)

            assert.is_nil(err)
            assert.are.equal(100, page.page_size)
            assert.are.equal(100, #page.entries)
            assert.are.equal(100, page.next_offset)
            assert.is_true(page.has_more)
            assert.is_true(#page.entries <= FandomPages.MAX_PAGE_SIZE)
            for _, entry in ipairs(page.entries) do
                assert.is_nil(entry.action)
                assert.is_nil(entry.callback)
            end
        end)

        it("returns an empty page at or past the end", function()
            local dir = make_letter("window_end", "A", SAMPLE)

            local page, err = FandomPages.page(dir, 1, "A", 4, 10)
            assert.is_nil(err)
            assert.are.equal(4, page.total)
            assert.are.equal(0, #page.entries)
            assert.is_nil(page.next_offset)
            assert.is_false(page.has_more)

            page, err = FandomPages.page(dir, 1, "A", 99, 10)
            assert.is_nil(err)
            assert.are.equal(4, page.total)
            assert.are.equal(0, #page.entries)
            assert.is_nil(page.next_offset)
        end)

        it("does not overlap or skip entries across pages", function()
            local dir = make_letter("window_walk", "A", many_entries(25))
            local seen = {}
            local seen_count = 0
            local offset = 0
            local pages = 0

            while offset do
                local page, err = FandomPages.page(dir, 1, "A", offset, 10)
                assert.is_nil(err)
                for _, entry in ipairs(page.entries) do
                    assert.is_nil(seen[entry.name])
                    seen[entry.name] = true
                    seen_count = seen_count + 1
                end
                offset = page.next_offset
                pages = pages + 1
                assert.is_true(pages <= 3)
            end

            assert.are.equal(3, pages)
            assert.are.equal(25, seen_count)
        end)
    end)

    describe("search", function()
        before_each(function()
            FandomPages.clearCache()
        end)

        it("lists every name that contains the term, ignoring case", function()
            local dir = make_letter("search_sub", "C", SEARCH_SAMPLE)
            assert.is_function(FandomPages.search)
            local page, err = FandomPages.search(dir, 1, "C", "CYBER")

            assert.is_nil(err)
            assert.are.equal(3, page.total)
            assert.are.equal(3, #page.entries)
            assert.are.equal("CYBER", page.query:upper())
            assert.are.equal("Cyber Sled", page.entries[1].name)
            assert.are.equal("Cyberpunk 2077", page.entries[2].name)
            assert.are.equal("cyberpunkdreams", page.entries[3].name)
            assert.are.equal("10962", page.entries[2].count)
            assert.are.equal(
                "/tags/Cyberpunk%202077/works", page.entries[2].url)
            assert.is_nil(page.next_offset)
            assert.is_false(page.has_more)
        end)

        it("matches in the middle of a name, not only the start", function()
            local dir = make_letter("search_middle", "C", SEARCH_SAMPLE)
            local page, err = FandomPages.search(dir, 1, "C", "punk")

            assert.is_nil(err)
            assert.are.equal(2, page.total)
            assert.are.equal("Cyberpunk 2077", page.entries[1].name)
            assert.are.equal("cyberpunkdreams", page.entries[2].name)
        end)

        it("trims the term, so a stray space still finds the name", function()
            local dir = make_letter("search_trim", "C", SEARCH_SAMPLE)
            local page, err = FandomPages.search(dir, 1, "C", "  cyber  ")

            assert.is_nil(err)
            assert.are.equal("cyber", page.query)
            assert.are.equal(3, page.total)
        end)

        it("returns an empty result, not an error, when nothing matches", function()
            local dir = make_letter("search_empty", "C", SEARCH_SAMPLE)
            local page, err = FandomPages.search(dir, 1, "C", "Battlestar")

            assert.is_nil(err)
            assert.are.equal(0, page.total)
            assert.are.equal(0, #page.entries)
            assert.is_nil(page.next_offset)
            assert.is_false(page.has_more)
        end)

        it("pages through every match without overlap", function()
            local dir = make_letter("search_walk", "A", many_entries(25))
            local seen, seen_count = {}, 0
            local offset, pages = 0, 0

            while offset do
                local page, err = FandomPages.search(dir, 1, "A", "fandom", offset, 10)
                assert.is_nil(err)
                assert.are.equal(25, page.total)
                for _, entry in ipairs(page.entries) do
                    assert.is_nil(seen[entry.name], entry.name .. " seen twice")
                    seen[entry.name] = true
                    seen_count = seen_count + 1
                end
                offset = page.next_offset
                pages = pages + 1
                assert.is_true(pages <= 3)
            end

            assert.are.equal(3, pages)
            assert.are.equal(25, seen_count)
        end)

        it("keeps page size bounded and reports the remaining matches", function()
            local dir = make_letter("search_cap", "A", many_entries(120))
            local page, err = FandomPages.search(dir, 1, "A", "fandom", 100, 1000)

            assert.is_nil(err)
            assert.are.equal(120, page.total)
            assert.are.equal(100, page.page_size)
            assert.are.equal(20, #page.entries)
            assert.are.equal("Fandom 101", page.entries[1].name)
            assert.is_nil(page.next_offset)
        end)

        it("decompresses once while paging through results", function()
            local dir = make_letter("search_cache", "A", many_entries(25))
            with_uncompress_counter(function(calls)
                local first = assert(FandomPages.search(dir, 1, "A", "fandom", 0, 10))
                assert.are.equal(10, #first.entries)
                local second, err = FandomPages.search(dir, 1, "A", "fandom", 10, 10)
                assert.is_nil(err)
                assert.are.equal(10, #second.entries)
                assert.are.equal(1, calls())
            end)
        end)

        it("rejects a missing, blank or non-string term", function()
            local dir = make_letter("search_args", "C", SEARCH_SAMPLE)
            local cases = { nil, "", "   ", 17 }

            for i, term in ipairs(cases) do
                local page, err = FandomPages.search(dir, 1, "C", term)
                assert.is_nil(page, "case " .. i .. " should fail")
                assert.is_truthy(err, "case " .. i .. " should explain")
            end
        end)

        it("reports a letter file that cannot be read", function()
            local dir = ensure_dir(tmp_root .. "/search_missing")
            local page, err = FandomPages.search(dir, 1, "A", "cyber")
            assert.is_nil(page)
            assert.is_truthy(err)
        end)
    end)

    describe("cache", function()
        it("decompresses once for consecutive pages of one letter", function()
            local dir = make_letter("cache_one", "A", SAMPLE)
            with_uncompress_counter(function(calls)
                assert(FandomPages.page(dir, 1, "A", 0, 2))
                local page, err = FandomPages.page(dir, 1, "A", 2, 2)
                assert.is_nil(err)
                assert.are.equal(2, #page.entries)
                assert.are.equal(1, calls())
            end)
        end)

        it("keeps at most one letter cached", function()
            local dir = make_letter("cache_two", "A", SAMPLE)
            write_letter_file(
                dir .. "/1/B.tsv.z", "Beta\t/tags/Beta/works\t1\n")

            with_uncompress_counter(function(calls)
                assert(FandomPages.page(dir, 1, "A", 0, 2))
                assert(FandomPages.page(dir, 1, "B", 0, 2))
                -- A was evicted by B, so returning to A decompresses again.
                assert(FandomPages.page(dir, 1, "A", 0, 2))
                assert.are.equal(3, calls())
            end)
        end)

        it("clearCache forces the active letter to be read again", function()
            local dir = make_letter("cache_clear", "A", SAMPLE)
            with_uncompress_counter(function(calls)
                assert(FandomPages.page(dir, 1, "A", 0, 2))
                assert.are.equal(1, calls())
                FandomPages.clearCache()
                assert(FandomPages.page(dir, 1, "A", 0, 2))
                assert.are.equal(2, calls())
            end)
        end)
    end)

    describe("robustness", function()
        it("reports a missing letter file", function()
            local dir = ensure_dir(tmp_root .. "/missing")
            local page, err = FandomPages.page(dir, 1, "A", 0, 10)
            assert.is_nil(page)
            assert.is_truthy(err)
            assert.is_truthy(err:find("open", 1, true))
        end)

        it("rejects a truncated header", function()
            local dir = ensure_dir(tmp_root .. "/short_header")
            ensure_dir(dir .. "/1")
            local f = assert(io.open(dir .. "/1/A.tsv.z", "wb"))
            f:write(string.char(1, 2))
            f:close()

            local page, err = FandomPages.page(dir, 1, "A", 0, 10)
            assert.is_nil(page)
            assert.is_truthy(err)
        end)

        it("rejects an absurd raw length before decompressing", function()
            local dir = ensure_dir(tmp_root .. "/huge_header")
            ensure_dir(dir .. "/1")
            write_letter_bytes(
                dir .. "/1/A.tsv.z",
                FandomPages.MAX_RAW_BYTES + 1,
                zlib.zlib_compress("boom"))

            with_uncompress_counter(function(calls)
                local page, err = FandomPages.page(dir, 1, "A", 0, 10)
                assert.is_nil(page)
                assert.is_truthy(err)
                assert.is_truthy(err:find("length", 1, true))
                assert.are.equal(0, calls())
            end)
        end)

        it("rejects an oversized file before reading it", function()
            local dir = ensure_dir(tmp_root .. "/huge_file")
            ensure_dir(dir .. "/1")
            local f = assert(io.open(dir .. "/1/A.tsv.z", "wb"))
            f:write(string.rep("x", 64))
            f:close()

            local old_limit = FandomPages.MAX_FILE_BYTES
            FandomPages.MAX_FILE_BYTES = 32
            local ok, page, err = pcall(
                FandomPages.page, dir, 1, "A", 0, 10)
            FandomPages.MAX_FILE_BYTES = old_limit

            assert(ok, page)
            assert.is_nil(page)
            assert.is_truthy(err)
            assert.is_truthy(err:find("large", 1, true))
        end)

        it("reports a corrupt zlib stream", function()
            local dir = ensure_dir(tmp_root .. "/bad_zlib")
            ensure_dir(dir .. "/1")
            write_letter_bytes(dir .. "/1/A.tsv.z", 32, "definitely not zlib")

            local page, err = FandomPages.page(dir, 1, "A", 0, 10)
            assert.is_nil(page)
            assert.is_truthy(err)
            assert.is_truthy(err:find("decompress", 1, true))
        end)

        it("reports a declared length that does not match the stream", function()
            local text = "One\t/tags/One/works\t1\n"
            local dir = ensure_dir(tmp_root .. "/short_stream")
            ensure_dir(dir .. "/1")
            write_letter_bytes(
                dir .. "/1/A.tsv.z", #text + 20, zlib.zlib_compress(text))

            local page, err = FandomPages.page(dir, 1, "A", 0, 10)
            assert.is_nil(page)
            assert.is_truthy(err)
            assert.is_truthy(err:find("shorter", 1, true))
        end)

        it("skips malformed lines, CRLF and a missing final newline", function()
            local dir = make_letter("messy", "A", table.concat({
                "Good One\t/tags/Good/works\t1",
                "missing tabs",
                "No URL\t\t2",
                "Good Two\t/tags/Good2/works\t2",
            }, "\r\n"))

            local page, err = FandomPages.page(dir, 1, "A", 0, 10)
            assert.is_nil(err)
            assert.are.equal(2, page.total)
            assert.are.equal(2, #page.entries)
            assert.are.equal("Good One", page.entries[1].name)
            assert.are.equal("1", page.entries[1].count)
            assert.are.equal("Good Two", page.entries[2].name)
            assert.are.equal("2", page.entries[2].count)
        end)

        it("reads an empty letter as zero entries", function()
            local dir = make_letter("empty", "A", "")
            local page, err = FandomPages.page(dir, 1, "A", 0, 10)

            assert.is_nil(err)
            assert.are.equal(0, page.total)
            assert.are.equal(0, #page.entries)
            assert.is_nil(page.next_offset)
        end)
    end)

    describe("argument validation", function()
        local dir

        before_each(function()
            dir = make_letter("args", "A", SAMPLE)
        end)

        it("rejects bad directories, categories, letters and windows", function()
            local cases = {
                { nil, 1, "A", 0, 10 },
                { "", 1, "A", 0, 10 },
                { dir, 0, "A", 0, 10 },
                { dir, 1.5, "A", 0, 10 },
                { dir, 1, "../A", 0, 10 },
                { dir, 1, "A", -1, 10 },
                { dir, 1, "A", 0.5, 10 },
                { dir, 1, "A", 0, 0 },
                { dir, 1, "A", 0, -5 },
                { dir, 1, "A", 0, "10" },
            }

            for i, args in ipairs(cases) do
                local page, err = FandomPages.page(unpack(args))
                assert.is_nil(page, "case " .. i .. " should fail")
                assert.is_truthy(err, "case " .. i .. " should explain")
            end
        end)
    end)
end)
