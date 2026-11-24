-- KOReader busted spec for the KO3 plugin.
--
-- From a KOReader checkout with this plugin symlinked into plugins/:
--   ln -s ../../plugins/ao3.koplugin/spec/ao3_spec.lua spec/unit/ao3_spec.lua
--   ./kodev test --busted=--pattern=ao3_spec front
--
-- The tests are offline. HTTP requests are mocked; the search-results
-- fixture is a real AO3 page saved on 2026-11-22.

require("commonrequire")

local DataStorage = require("datastorage")
local http = require("socket.http")
local socket = require("socket")
local lfs = require("libs/libkoreader-lfs")
local socketutil = require("socketutil")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")
local plugin = setmetatable({}, { __index = Ao3 })

local fixture_dir = "plugins/ao3.koplugin/spec/fixtures/"

local function read_fixture(name)
    local f = assert(io.open(fixture_dir .. name, "rb"))
    local body = f:read("*a")
    f:close()
    return body
end

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

local tmp_root
local old_get_full_data_dir
local old_set_timeout
local old_reset_timeout

setup(function()
    tmp_root = os.tmpname()
    os.remove(tmp_root)
    assert(lfs.mkdir(tmp_root))

    old_get_full_data_dir = DataStorage.getFullDataDir
    DataStorage.getFullDataDir = function() return tmp_root end

    old_set_timeout = socketutil.set_timeout
    old_reset_timeout = socketutil.reset_timeout
    socketutil.set_timeout = function() end
    socketutil.reset_timeout = function() end
end)

teardown(function()
    if old_get_full_data_dir then
        DataStorage.getFullDataDir = old_get_full_data_dir
    end
    if old_set_timeout then
        socketutil.set_timeout = old_set_timeout
    end
    if old_reset_timeout then
        socketutil.reset_timeout = old_reset_timeout
    end
    if tmp_root then
        remove_tree(tmp_root)
    end
end)

local function with_http(mock, fn)
    local old_request = http.request
    http.request = mock
    local ok, err = pcall(fn)
    http.request = old_request
    assert(ok, err)
end

describe("AO3 browser", function()
    describe("parseWorkId", function()
        it("extracts an id from a work URL", function()
            assert.are.equal("1234567", plugin:parseWorkId("https://archiveofourown.org/works/1234567"))
        end)

        it("extracts an id from a chapter URL", function()
            assert.are.equal("1234567", plugin:parseWorkId(
                "https://archiveofourown.org/works/1234567/chapters/7654321"))
        end)

        it("extracts an id from a download URL", function()
            assert.are.equal("1234567", plugin:parseWorkId(
                "https://download.archiveofourown.org/downloads/1234567/work.html"))
        end)

        it("accepts a bare id with whitespace", function()
            assert.are.equal("1234567", plugin:parseWorkId("  1234567  "))
        end)

        it("rejects arbitrary text", function()
            assert.is_nil(plugin:parseWorkId("not a work"))
        end)
    end)

    describe("URL builders", function()
        it("builds a search URL", function()
            local url = plugin:searchUrl("harry potter")
            assert.is_truthy(url:find(
                "https://archiveofourown.org/works/search?work_search%5Bquery%5D=", 1, true))
            assert.is_nil(url:find(" ", 1, true))
        end)

        it("builds a tag URL", function()
            assert.are.equal(
                "https://archiveofourown.org/tags/Harry%20Potter%20-%20J.%20K.%20Rowling/works",
                plugin:tagUrl("Harry Potter - J. K. Rowling"))
        end)

        it("encodes slash and ampersand in tag names", function()
            local url = plugin:tagUrl("A/B & C")
            assert.is_truthy(url:find("A*s*B", 1, true))
            assert.is_truthy(url:find("*a*", 1, true))
        end)

        it("builds a recent-works URL", function()
            assert.are.equal("https://archiveofourown.org/works", plugin:recentUrl())
        end)

        it("passes a tag URL through unchanged", function()
            local url = "https://archiveofourown.org/tags/Foo/works"
            assert.are.equal(url, plugin:tagUrl(url))
        end)

        it("builds an author works URL from a name", function()
            assert.are.equal(
                "https://archiveofourown.org/users/An%20Author/works",
                plugin:authorWorksUrl("An Author"))
        end)

        it("appends the works list to a pasted author page", function()
            assert.are.equal(
                "https://archiveofourown.org/users/foo/pseuds/bar/works",
                plugin:authorWorksUrl("https://archiveofourown.org/users/foo/pseuds/bar"))
            assert.are.equal(
                "https://archiveofourown.org/users/foo/works",
                plugin:authorWorksUrl("/users/foo"))
        end)

        it("keeps a pasted author works URL unchanged", function()
            local url = "https://archiveofourown.org/users/foo/works"
            assert.are.equal(url, plugin:authorWorksUrl(url))
        end)
    end)

    describe("parseListing", function()
        it("parses a real search results page", function()
            local listing, err = plugin:parseListing(read_fixture("search.html"))
            assert.is_nil(err)
            assert.is_truthy(listing)
            assert.are.equal(20, #listing.items)

            local first = listing.items[1]
            assert.are.equal("13215162", first.id)
            assert.are.equal("Dragon, Dragon", first.title)
            assert.are.equal("myreia", first.authors)
            assert.are.equal("1,447", first.words)
            assert.are.equal("38", first.kudos)
            assert.are.equal("General Audiences", first.rating)
            assert.are.equal("Complete", first.complete)
            assert.is_truthy(first.summary:find(
                "When Athelas finds a baby dragon", 1, true))

            -- The card's own fields: AO3's symbol state, the tag kinds kept
            -- apart, and the numbers on the record line.
            assert.are.equal("rating-general-audience", first.rating_key)
            assert.are.equal("warning-no", first.warning_key)
            assert.are.equal("category-gen", first.category_key)
            assert.are.equal("complete-yes", first.complete_key)
            assert.are.same({ "Female Lavellan", "Cassandra Pentaghast",
                "Humour", "Fluff" },
                { first.tag_list[1], first.tag_list[2], first.tag_list[3],
                    first.tag_list[4] })
            for _, tag in ipairs(first.tag_list) do
                assert.are_not.equal("No Archive Warnings Apply", tag)
            end
            assert.are.equal("", first.relationships)

            local shipped = listing.items[2]
            assert.is_truthy(shipped.relationships:find("Aizawa Shouta", 1, true))
            assert.is_truthy(shipped.relationship_list and #shipped.relationship_list > 0)
            -- A relationship is shown on its own line, not repeated in the
            -- tag box.
            for _, tag in ipairs(shipped.tag_list) do
                for _, ship in ipairs(shipped.relationship_list) do
                    assert.are_not.equal(ship, tag)
                end
            end

            assert.is_truthy(listing.next_url)
            assert.is_truthy(listing.next_url:find("page=2", 1, true))
            assert.is_nil(listing.next_url:find("&amp;", 1, true))
            assert.is_nil(listing.prev_url)
            assert.are.equal("317,737", listing.count)
        end)

        it("reads the works count from an author works page", function()
            local listing = plugin:parseListing(read_fixture("author/works_fandom.html"))
            assert.are.equal("12", listing.count)
            assert.are.equal(1, #listing.items)
            assert.are.equal("Porcelain Scales", listing.items[1].title)
        end)

        it("reads the count from a paginated author works page", function()
            local listing = plugin:parseListing(read_fixture("author/works.html"))
            assert.are.equal("535", listing.count)
            assert.are.equal(2, #listing.items)
        end)

        it("captures each author's page link", function()
            local listing = plugin:parseListing(read_fixture("search.html"))
            assert.are.same({ "/users/myreia/pseuds/myreia" },
                listing.items[1].author_urls)
            for _, item in ipairs(listing.items) do
                if item.authors ~= "Anonymous" then
                    assert.is_truthy(item.author_urls and #item.author_urls > 0)
                    assert.is_truthy(item.author_urls[1]:match("^/users/"))
                end
            end
        end)

        it("detects a Cloudflare challenge page", function()
            local listing, err = plugin:parseListing(read_fixture("challenge.html"))
            assert.is_nil(listing)
            assert.is_truthy(err)
            assert.is_truthy(err:find("Cloudflare", 1, true))
        end)

        it("returns an empty listing for a non-results page", function()
            local listing, err = plugin:parseListing("<html><body><p>hello</p></body></html>")
            assert.is_nil(err)
            assert.are.equal(0, #listing.items)
        end)

        it("understands the pagy pagination markup", function()
            local html = [[
                <html><body>
                <ol class="pagination actions pagy">
                  <li class="next"><a href="/tags/Foo/works?page=2">Next &rarr;</a></li>
                </ol>
                </body></html>
            ]]
            local listing, err = plugin:parseListing(html)
            assert.is_nil(err)
            assert.are.equal(
                "https://archiveofourown.org/tags/Foo/works?page=2",
                listing.next_url)
        end)
    end)

    describe("fetchHtml", function()
        it("returns a 200 body", function()
            with_http(function(req)
                assert.are.equal("https://example.test/page", req.url)
                req.sink("hello")
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local body, err = plugin:fetchHtml("https://example.test/page")
                assert.are.equal("hello", body)
                assert.is_nil(err)
            end)
        end)

        it("turns 429 into a useful error", function()
            local client = setmetatable({}, { __index = Ao3 })
            with_http(function(req)
                req.sink("")
                req.sink(nil)
                return 1, 429, { ["retry-after"] = "30" }, "Too Many Requests"
            end, function()
                local body, err = client:fetchHtml("https://example.test/page")
                assert.is_nil(body)
                assert.is_truthy(err)
                assert.is_truthy(err:find("429", 1, true))
            end)
        end)

        it("honors Retry-After without sending another blocked request", function()
            local client = setmetatable({}, { __index = Ao3 })
            local calls = 0
            with_http(function(req)
                calls = calls + 1
                req.sink("rate limited")
                req.sink(nil)
                return 1, 429, { ["retry-after"] = "60" }, "Too Many Requests"
            end, function()
                local body, err = client:fetchHtml("https://archiveofourown.org/works")
                assert.is_nil(body)
                assert.is_truthy(err:find("wait", 1, true))
                body, err = client:fetchHtml("https://archiveofourown.org/works")
                assert.is_nil(body)
                assert.is_truthy(err:find("wait", 1, true))
                assert.are.equal(1, calls)
            end)
        end)

        it("warns that a VPN can trigger a 429", function()
            local client = setmetatable({}, { __index = Ao3 })
            with_http(function(req)
                req.sink("bot servers overloaded")
                req.sink(nil)
                return 1, 429, {}, "Too Many Requests"
            end, function()
                local body, err = client:fetchHtml("https://archiveofourown.org/works")
                assert.is_nil(body)
                assert.is_truthy(err:find("VPN", 1, true))
            end)
        end)

        it("does not shorten a long Retry-After interval", function()
            local client = setmetatable({}, { __index = Ao3 })
            with_http(function(req)
                req.sink("rate limited")
                req.sink(nil)
                return 1, 429, { ["retry-after"] = "3600" }, "Too Many Requests"
            end, function()
                local body = client:fetchHtml("https://archiveofourown.org/works")
                assert.is_nil(body)
                assert.is_true(client.blocked_until - socket.gettime() > 3500)
            end)
        end)

        it("retries once after a 403 and recovers", function()
            local calls = 0
            with_http(function(req)
                calls = calls + 1
                if calls == 1 then
                    req.sink("denied")
                    req.sink(nil)
                    return 1, 403, {}, "Forbidden"
                end
                req.sink("recovered")
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local body, err = plugin:fetchHtml("https://example.test/page")
                assert.are.equal("recovered", body)
                assert.is_nil(err)
                assert.are.equal(2, calls)
            end)
        end)

        it("does not retry a response marked as a browser challenge", function()
            local client = setmetatable({}, { __index = Ao3 })
            local calls = 0
            with_http(function(req)
                calls = calls + 1
                req.sink("<title>Just a moment...</title>")
                req.sink(nil)
                return 1, 403, { ["cf-mitigated"] = "challenge" }, "Forbidden"
            end, function()
                local body, err = client:fetchHtml("https://archiveofourown.org/works")
                assert.is_nil(body)
                assert.is_truthy(err:find("browser", 1, true))
                assert.are.equal(1, calls)
                assert.is_truthy(client.blocked_until)
            end)
        end)

        it("recognizes a browser-check page when the challenge header is absent", function()
            local client = setmetatable({}, { __index = Ao3 })
            local calls = 0
            with_http(function(req)
                calls = calls + 1
                req.sink("<html><title>Just a moment...</title>Enable JavaScript and cookies to continue</html>")
                req.sink(nil)
                return 1, 403, {}, "Forbidden"
            end, function()
                local body, err = client:fetchHtml("https://archiveofourown.org/works")
                assert.is_nil(body)
                assert.is_truthy(err:find("browser", 1, true))
                assert.are.equal(1, calls)
            end)
        end)

        it("cools down after a persistent Cloudflare refusal", function()
            local client = setmetatable({}, { __index = Ao3 })
            local calls = 0
            with_http(function(req)
                calls = calls + 1
                req.sink("Shields are up")
                req.sink(nil)
                return 1, 403, {}, "Forbidden"
            end, function()
                local body, err = client:fetchHtml("https://archiveofourown.org/works")
                assert.is_nil(body)
                assert.is_truthy(err:find("wait", 1, true))
                body, err = client:fetchHtml("https://archiveofourown.org/works")
                assert.is_nil(body)
                assert.is_truthy(err:find("wait", 1, true))
                assert.are.equal(2, calls)
            end)
        end)

        it("passes through a network error", function()
            with_http(function()
                return nil, "timeout"
            end, function()
                local body, err = plugin:fetchHtml("https://example.test/page")
                assert.is_nil(body)
                assert.are.equal("timeout", err)
            end)
        end)
    end)

    describe("downloadWork", function()
        it("streams and names a work file", function()
            local work_html = read_fixture("work.html")
            with_http(function(req)
                assert.are.equal(
                    "https://download.archiveofourown.org/downloads/123/work.html", req.url)
                req.sink(work_html)
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local path, err = plugin:downloadWork("123", "Test Work")
                assert.is_nil(err)
                assert.is_truthy(path)
                assert.is_truthy(path:find("%[123%]%.html$"))

                local f = assert(io.open(path, "rb"))
                local body = f:read("*a")
                f:close()
                assert.is_truthy(body:find("Test Work", 1, true))
            end)
        end)

        it("rejects a login page", function()
            with_http(function(req)
                req.sink(read_fixture("login.html"))
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local path, err = plugin:downloadWork("456", nil)
                assert.is_nil(path)
                assert.is_truthy(err)
                assert.is_truthy(err:find("Log In", 1, true))
            end)
        end)

        it("reports an ended session when AO3 serves the lost-cookie page", function()
            -- AO3 redirects a signed-in request without user_credentials to
            -- /lost_cookie; the download is a 200 page, so the generic
            -- "did not return a work file" message would hide the real cause.
            with_http(function(req)
                req.sink(read_fixture("account/lost_cookie.html"))
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local path, err = plugin:downloadWork("9911", nil)
                assert.is_nil(path)
                assert.is_truthy(err)
                assert.is_truthy(err:find("Sign in again", 1, true))
                assert.is_nil(err:find("did not return a work file", 1, true))
            end)
        end)

        it("reports a 404", function()
            with_http(function(req)
                req.sink("missing")
                req.sink(nil)
                return 1, 404, {}, "Not Found"
            end, function()
                local path, err = plugin:downloadWork("789", nil)
                assert.is_nil(path)
                assert.is_truthy(err)
                assert.is_truthy(err:find("404", 1, true))
            end)
        end)

        it("keeps a cached work when refreshing receives an error", function()
            local dir = DataStorage:getFullDataDir() .. "/ao3"
            local old = dir .. "/Saved work [9901].html"
            local file = assert(io.open(old, "wb"))
            file:write("<html>offline copy</html>")
            file:close()
            with_http(function(req)
                req.sink("blocked")
                req.sink(nil)
                return 1, 404, {}, "Not Found"
            end, function()
                local path = plugin:downloadWork("9901", "Saved work")
                assert.is_nil(path)
                local cached = assert(io.open(old, "rb"))
                assert.are.equal("<html>offline copy</html>", cached:read("*a"))
                cached:close()
            end)
        end)

        it("replaces a cached work only after a valid download", function()
            local dir = DataStorage:getFullDataDir() .. "/ao3"
            local old = dir .. "/Old title [9902].html"
            local file = assert(io.open(old, "wb"))
            file:write("<html>offline copy</html>")
            file:close()
            with_http(function(req)
                req.sink(read_fixture("work.html"))
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local path = assert(plugin:downloadWork("9902", "New title"))
                assert.is_nil(io.open(old, "rb"))
                local updated = assert(io.open(path, "rb"))
                assert.is_truthy(updated:read("*a"):find('id="preface"', 1, true))
                updated:close()
            end)
        end)
    end)

    describe("KOReader plugin loader", function()
        it("loads the plugin and its metadata", function()
            disable_plugins()
            load_plugin("ao3")

            local PluginLoader = require("pluginloader")
            local loaded
            for _, p in ipairs(PluginLoader.enabled_plugins) do
                if p.name == "ao3" then
                    loaded = p
                    break
                end
            end

            assert.is_truthy(loaded)
            assert.are.equal("KO3", loaded.fullname)
            assert.is_truthy(loaded.addToMainMenu)
            disable_plugins()
        end)
    end)

    describe("embedded fandom data", function()
        local zlib = require("ffi/zlib")
        local DataStorage = require("datastorage")
        local lfs = require("libs/libkoreader-lfs")

        local function write_letter(path, text)
            local data = zlib.zlib_compress(text)
            local n = #text
            local header = string.char(n % 256, math.floor(n / 256) % 256,
                math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
            local f = assert(io.open(path, "wb"))
            f:write(header)
            f:write(data)
            f:close()
        end

        it("reads the index and one letter lazily", function()
            local root = DataStorage:getFullDataDir() .. "/fandom_fixture"
            local dir = root .. "/data/fandoms"
            if lfs.attributes(dir, "mode") ~= "directory" then
                lfs.mkdir(root)
                lfs.mkdir(root .. "/data")
                lfs.mkdir(dir)
                lfs.mkdir(dir .. "/1")
            end
            local index = assert(io.open(dir .. "/index.lua", "wb"))
            index:write([[return { { index = 1, name = "Test Media", count = 2, letters = { "A" } } }]])
            index:close()
            write_letter(dir .. "/1/A.tsv.z",
                "Alpha Fandom\t/tags/Alpha%20Fandom/works\t10\nAmpersand & Co\t/tags/Ampersand%20*a*%20Co/works\t5\n")

            local old_path = plugin.path
            plugin.path = root
            plugin.fandom_index = nil

            local data = assert(plugin:loadFandomIndex())
            assert.are.equal("Test Media", data[1].name)
            assert.are.equal(2, data[1].count)

            local rows = assert(plugin:loadFandomLetter(data[1], "A"))
            assert.are.equal(2, #rows)
            assert.are.equal("Alpha Fandom", rows[1].text)
            assert.are.equal("10", rows[1].mandatory)
            assert.are.equal("Ampersand & Co", rows[2].text)

            plugin.path = old_path
            plugin.fandom_index = nil
        end)

        it("returns nil when the data file is missing", function()
            local old_path = plugin.path
            plugin.path = "/nonexistent"
            plugin.fandom_index = nil
            assert.is_nil(plugin:loadFandomIndex())
            assert.is_nil(plugin:loadFandomLetter({ index = 9, name = "X" }, "A"))
            plugin.path = old_path
            plugin.fandom_index = nil
        end)

        it("only builds one bounded menu window from a large letter", function()
            local root = DataStorage:getFullDataDir() .. "/fandom_window_fixture"
            local dir = root .. "/data/fandoms"
            lfs.mkdir(root)
            lfs.mkdir(root .. "/data")
            lfs.mkdir(dir)
            lfs.mkdir(dir .. "/9")
            local lines = {}
            for i = 1, 211 do
                lines[i] = string.format("Name %03d\t/tags/Name%%20%03d/works\t%d", i, i, i)
            end
            write_letter(dir .. "/9/N.tsv.z", table.concat(lines, "\n") .. "\n")
            local old_path = plugin.path
            plugin.path = root
            local ok, err = pcall(function()
                local category = { index = 9, name = "TV Shows" }
                local rows, page = plugin:loadFandomLetter(category, "N", 0)
                assert.are.equal(100, #rows)
                assert.are.equal(211, page.total)
                assert.are.equal(100, page.next_offset)
                assert.are.equal("Name 001", rows[1].text)
                rows, page = plugin:loadFandomLetter(category, "N", 200)
                assert.are.equal(11, #rows)
                assert.are.equal("Name 211", rows[11].text)
                assert.is_nil(page.next_offset)
                -- A search is a window too: one match out of 211 is one row,
                -- wherever it sits in the letter.
                local matches, found = plugin:searchFandomLetter(category, "N", "name 207")
                assert.are.equal(1, found.total)
                assert.are.equal(1, #matches)
                assert.are.equal("Name 207", matches[1].text)
                assert.are.equal("207", matches[1].mandatory)
            end)
            plugin.path = old_path
            assert.is_true(ok, err)
        end)

        it("releases the decompressed letter when the AO3 menu closes", function()
            local root = DataStorage:getFullDataDir() .. "/fandom_close_fixture"
            local dir = root .. "/data/fandoms"
            lfs.mkdir(root)
            lfs.mkdir(root .. "/data")
            lfs.mkdir(dir)
            lfs.mkdir(dir .. "/3")
            write_letter(dir .. "/3/A.tsv.z", "Alpha\t/tags/Alpha/works\t1\n")
            local old_path = plugin.path
            local original = zlib.zlib_uncompress
            local calls = 0
            zlib.zlib_uncompress = function(...)
                calls = calls + 1
                return original(...)
            end
            plugin.path = root
            local ok, err = pcall(function()
                local category = { index = 3 }
                assert(plugin:loadFandomLetter(category, "A"))
                assert(plugin:loadFandomLetter(category, "A"))
                assert.are.equal(1, calls)
                plugin:ensureMenu().close_callback()
                assert(plugin:loadFandomLetter(category, "A"))
                assert.are.equal(2, calls)
            end)
            plugin.path = old_path
            zlib.zlib_uncompress = original
            assert.is_true(ok, err)
        end)
    end)

    describe("app screens", function()
        local function clear_downloads()
            local DataStorage = require("datastorage")
            local lfs = require("libs/libkoreader-lfs")
            local dir = DataStorage:getFullDataDir() .. "/ao3"
            if lfs.attributes(dir, "mode") ~= "directory" then
                lfs.mkdir(dir)
            end
            for entry in lfs.dir(dir) do
                if entry ~= "." and entry ~= ".." then
                    os.remove(dir .. "/" .. entry)
                end
            end
        end

        local function open_home()
            plugin.menu = nil
            local UIManager = require("ui/uimanager")
            local old_show = UIManager.show
            UIManager.show = function() end
            local ok, err = pcall(function() plugin:showHome() end)
            UIManager.show = old_show
            assert.is_true(ok, err)
            return plugin.menu
        end

        local function texts(menu)
            local out = {}
            for _, item in ipairs(menu.item_table) do
                out[#out + 1] = item.text
            end
            return table.concat(out, "|")
        end

        after_each(function()
            plugin.menu = nil
        end)

        local function tile(menu, role)
            for _, row in ipairs(menu.item_table) do
                for _, entry in ipairs(row.tiles or {}) do
                    if entry.role == role then return entry end
                end
            end
        end

        -- The author screen is a page, not a list of lists: the masthead, the
        -- bar and the strip are rows like any other, so tests find rows by the
        -- role the author page names them with.
        local function author_row(menu, role)
            for _, row in ipairs(menu.item_table) do
                if row.role == role then return row end
            end
        end

        local function author_rows(menu, role)
            local out = {}
            for _, row in ipairs(menu.item_table) do
                if row.role == role then out[#out + 1] = row end
            end
            return out
        end

        local function author_tabs(menu)
            local row = author_row(menu, "author_tabs")
            return row and row.ao3_tabs
        end

        it("opens a home menu led by the logo, not a repeated title", function()
            local menu = open_home()
            assert.is_truthy(menu)
            -- The wordmark lives in the page header, so the native bar is
            -- empty: one identity, not two.
            assert.are.equal("", menu.title_bar.title_widget.text)
            assert.are.equal("", menu.ao3_title)

            for _, role in ipairs({ "latest", "fandoms", "author", "tag",
                "account", "downloads", "open", "update", "report" }) do
                assert.is_truthy(tile(menu, role))
            end
        end)

        it("keeps the close tap zone inside the title bar", function()
            local menu = open_home()
            local bar = menu.title_bar
            local close = bar and bar.right_button
            assert.is_truthy(close)
            -- The author screen's tab strip is the first content row. If the
            -- close button's target reached below the bar, its right end
            -- would swallow taps on the rightmost tab (Bookmarks) and close
            -- the screen instead of switching tabs.
            assert.are.equal(0, close.padding_bottom)
            assert.is_true(close.dimen.h <= bar.dimen.h)
        end)

        it("brings the network up before downloading an update", function()
            local NetworkMgr = require("ui/network/manager")
            local http = require("socket.http")
            local UIManager = require("ui/uimanager")
            local old_run, old_after = NetworkMgr.runWhenOnline, NetworkMgr.afterWifiAction
            local old_request, old_show = http.request, UIManager.show
            local online, offline, shown = 0, 0, {}
            NetworkMgr.runWhenOnline = function(_, callback)
                online = online + 1
                callback()
            end
            NetworkMgr.afterWifiAction = function() offline = offline + 1 end
            UIManager.show = function(_, widget) shown[#shown + 1] = widget end
            http.request = function() return nil, "timeout" end
            local ok, err = pcall(function()
                plugin:installUpdate(plugin:pluginDir(), {
                    version = "9.9.9",
                    zip_url = "https://example.test/ao3.zip",
                })
            end)
            NetworkMgr.runWhenOnline, NetworkMgr.afterWifiAction = old_run, old_after
            http.request, UIManager.show = old_request, old_show
            assert.is_true(ok, err)
            -- The manifest check may have left Wi-Fi off; the download has to
            -- ask for it itself or it sits on a dead socket until it times out.
            assert.are.equal(1, online)
            assert.are.equal(1, offline)
            assert.is_truthy(shown[#shown].text:find("Update failed", 1, true))
        end)

        it("leads with the logo lockup and one primary search bar", function()
            local menu = open_home()
            assert.are.equal("hero", menu.item_table[1].role)
            assert.is_truthy(menu.item_table[1].ao3_static)
            assert.are.equal("search", menu.item_table[2].role)
            assert.is_truthy(menu.item_table[2].ao3_panel)

            local calls = 0
            plugin.searchDialog = function() calls = calls + 1 end
            menu.item_table[2].action()
            plugin.searchDialog = nil
            assert.are.equal(1, calls)
        end)

        it("groups the home rows into tile sections", function()
            local menu = open_home()
            local roles = {}
            for _, row in ipairs(menu.item_table) do
                roles[#roles + 1] = row.role
            end
            assert.are.same({
                "hero", "search", "browse_label", "browse_row_1",
                "browse_row_2", "account_label", "account",
                "library_label", "library_row",
                "plugin_label", "update", "report",
            }, roles)
            -- Each tile row carries its two entries for paging and tests.
            for _, row in ipairs(menu.item_table) do
                if row.tiles then
                    assert.is_true(#row.tiles == 1 or #row.tiles == 2)
                    for _, entry in ipairs(row.tiles) do
                        assert.is_truthy(entry.action)
                        assert.is_truthy(entry.icon)
                    end
                end
            end
        end)

        it("keeps a group label with the first row of its group", function()
            local menu = open_home()
            -- A page may never end on a label whose content is overleaf.
            for _, page in ipairs(menu.page_items) do
                local last = menu.item_table[page[#page]]
                assert.is_false(last.keep_with_next == true,
                    "page ends alone on " .. tostring(last.role))
            end
        end)

        it("opens Settings from the gear and stores the tag default", function()
            local DataStorage = require("datastorage")
            local lfs = require("libs/libkoreader-lfs")
            local Preferences = dofile("plugins/ao3.koplugin/preferences.lua")
            local dir = DataStorage:getFullDataDir() .. "/ao3_prefs_test"
            if lfs.attributes(dir, "mode") ~= "directory" then lfs.mkdir(dir) end
            local prefs_path = dir .. "/ao3_prefs.lua"
            os.remove(prefs_path)
            os.remove(prefs_path .. ".old")
            local old_dir = DataStorage.getSettingsDir
            DataStorage.getSettingsDir = function() return dir end
            plugin.prefs = { tags_expanded = false }

            local ok, err = pcall(function()
                local menu = open_home()

                -- The gear sits in the masthead row, at the right edge.
                local gear
                local function walk(widget)
                    if widget.onTap then gear = gear or widget end
                    for _, child in ipairs(widget) do walk(child) end
                end
                walk(menu.item_group[1])
                assert.is_truthy(gear)

                gear.onTap()
                assert.are.equal("Settings", menu.ao3_title)

                -- Two options, each a label and its state: the tag default,
                -- then the card design, which starts modern.
                assert.are.equal(2, #menu.item_table)
                local row = menu.item_table[1]
                assert.are.equal("tags_default", row.role)
                assert.are.equal("Expanded tags:", row.text)
                assert.are.equal("Off", row.mandatory)
                local style_row = menu.item_table[2]
                assert.are.equal("card_style", style_row.role)
                assert.are.equal("Work cards:", style_row.text)
                assert.are.equal("Modern", style_row.mandatory)

                row.action()
                assert.is_true(plugin.prefs.tags_expanded)
                assert.are.equal("On", menu.item_table[1].mandatory)

                -- The choice is on disk, and a new listing follows it.
                assert.is_true(Preferences.load(prefs_path).tags_expanded)
                local work_row = plugin:workRow({
                    id = "1", title = "A work", authors = "A writer",
                    tag_list = { "friendship" },
                })
                assert.is_true(work_row.tags_expanded)

                -- A second tap turns it off again.
                menu.item_table[1].action()
                assert.is_false(plugin.prefs.tags_expanded)
                assert.are.equal("Off", menu.item_table[1].mandatory)
                assert.is_false(Preferences.load(prefs_path).tags_expanded)
            end)

            DataStorage.getSettingsDir = old_dir
            os.remove(prefs_path)
            os.remove(prefs_path .. ".old")
            assert.is_true(ok, err)
        end)

        it("ships the official logo, its traced SVG and the tile icons", function()
            local dir = "plugins/ao3.koplugin/assets/"
            local png = assert(io.open(dir .. "ao3-logo.png", "rb"))
            local png_head = png:read(8)
            png:close()
            assert.are.equal("\137PNG\r\n\26\n", png_head)

            local svg = assert(io.open(dir .. "ao3-logo.svg", "rb"))
            local svg_head = svg:read(400)
            svg:close()
            assert.is_truthy(svg_head:find("<svg", 1, true))
            assert.is_truthy(svg_head:find('viewBox="0 0 351 240"', 1, true))

            for _, name in ipairs({ "clock", "grid", "user", "tag",
                "download", "file", "refresh", "restore", "search" }) do
                local f = assert(io.open(dir .. "icons/" .. name .. ".svg", "rb"))
                local head = f:read(200)
                f:close()
                assert.is_truthy(head:find("<svg", 1, true), name)
            end
        end)

        it("asks before attaching the log and saves the report", function()
            local UIManager = require("ui/uimanager")
            local old_show, old_close = UIManager.show, UIManager.close
            local old_settings = DataStorage.getSettingsDir
            DataStorage.getSettingsDir = function() return tmp_root .. "/settings" end
            local old_relay = plugin.BugReport.RELAY_URL
            plugin.BugReport.RELAY_URL = nil -- exercise the saved-bundle path
            local shown = {}
            UIManager.show = function(_, widget)
                shown[#shown + 1] = widget
            end
            UIManager.close = function() end
            local ok, err = pcall(function()
                plugin:reportBug()
                local input = shown[#shown]
                assert.is_truthy(input)
                input.getInputValue = function()
                    return "It crashes when I tap Read"
                end
                input.buttons[1][2].callback() -- Next
                local consent = shown[#shown]
                assert.is_truthy(consent.text:find("used only to find the cause", 1, true))
                assert.is_truthy(consent.text:find("password", 1, true))
                consent.ok_callback() -- Attach log
                local saved = shown[#shown]
                assert.is_truthy(saved.text:find("Report saved:", 1, true))
            end)
            UIManager.show, UIManager.close = old_show, old_close
            DataStorage.getSettingsDir = old_settings
            plugin.BugReport.RELAY_URL = old_relay
            assert.is_true(ok, err)

            local reports = tmp_root .. "/ao3/reports"
            local found
            for entry in lfs.dir(reports) do
                if entry ~= "." and entry ~= ".." then
                    found = reports .. "/" .. entry
                end
            end
            assert.is_truthy(found)
            assert.are.equal("file", lfs.attributes(found .. "/report.md", "mode"))
            assert.are.equal("file", lfs.attributes(found .. "/log.txt", "mode"))
            remove_tree(found)
        end)

        it("shows a results page with a short summary and backs out", function()
            local menu = open_home()
            plugin:showListing({
                items = {
                    {
                        id = "1",
                        title = "Test Work",
                        authors = "Test Author",
                        summary = "A short summary of the story.",
                    },
                    {
                        id = "2",
                        title = "Long One",
                        authors = "Someone",
                        summary = string.rep("word ", 100),
                    },
                },
                count = "317,737",
                next_url = "https://archiveofourown.org/works?page=2",
            }, "Search: dragon")

            assert.are.equal("Test Work", menu.item_table[1].text)
            assert.are.equal("Test Author", menu.item_table[1].mandatory)
            assert.are.equal("A short summary of the story.", menu.item_table[1].summary)
            assert.are.equal("Long One", menu.item_table[2].text)
            assert.are.equal(3, #menu.item_table)

            -- The long summary stays inside its work's single selectable card.
            local long_summary = menu.item_table[2].summary
            assert.is_truthy(long_summary:find("…", 1, true))
            assert.is_true(#long_summary < 330)

            assert.are.equal("Next page →", menu.item_table[#menu.item_table].text)
            assert.is_truthy(menu.ao3_title:find("317,737", 1, true))

            menu:onClose()
            assert.are.equal("", menu.ao3_title)
            local home_latest
            for _, row in ipairs(menu.item_table) do
                for _, entry in ipairs(row.tiles or {}) do
                    if entry.role == "latest" then home_latest = entry end
                end
            end
            assert.is_truthy(home_latest)
        end)

        it("keeps one back-stack entry while paging through AO3 results", function()
            local menu = open_home()
            plugin:showListing({
                items = { { id = "100", title = "First", authors = "A" } },
                next_url = "https://archiveofourown.org/works?page=2",
            }, "Latest works")
            assert.are.equal(1, #menu.item_table_stack)

            local old_fetch = plugin.fetchPage
            local page = 1
            plugin.fetchPage = function(_, url, parse, label, on_success)
                page = page + 1
                on_success({
                    items = { { id = tostring(100 + page), title = "Page " .. page,
                        authors = "A" } },
                    next_url = "https://archiveofourown.org/works?page=" .. (page + 1),
                })
            end
            local ok, err = pcall(function()
                for _ = 1, 5 do
                    local next_row = menu.item_table[#menu.item_table]
                    next_row.action()
                    assert.are.equal(1, #menu.item_table_stack)
                end
            end)
            plugin.fetchPage = old_fetch
            assert.is_true(ok, err)
            menu:onClose()
            assert.are.equal("", menu.ao3_title)
        end)

        it("builds the fandom list from the embedded index", function()
            local menu = open_home()
            plugin:pushRows("Fandoms", plugin:fandomRows({
                { index = 1, name = "Test Media", count = 42, letters = { "A" } },
                { index = 2, name = "Other Media", count = 3, letters = { "B" } },
            }))

            assert.are.equal("Fandoms", menu.ao3_title)
            -- "Find a tag…" plus the two categories.
            assert.are.equal(3, #menu.item_table)
            assert.are.equal("Find a tag…", menu.item_table[1].text)
            assert.are.equal("Test Media", menu.item_table[2].text)
            assert.is_truthy(menu.item_table[2].mandatory:find("42", 1, true))
        end)

        it("formats large fandom counts for scanning", function()
            local rows = plugin:fandomRows({
                { index = 2, name = "Books & Literature", count = 14300, letters = { "H" } },
            })
            assert.are.equal("14,300 fandoms", rows[2].mandatory)
        end)

        it("puts Read on the first page of a work", function()
            local menu = open_home()
            local calls = {}
            plugin.readWork = function(_, id, title, refresh)
                calls[#calls + 1] = { id = id, title = title, refresh = refresh }
            end
            local ok, err = pcall(function()
                plugin:showWork({
                    id = "1",
                    title = "Test Work",
                    authors = "Test Author",
                    summary = "A summary.",
                })
            end)
            assert.is_true(ok, err)
            assert.is_truthy(menu.item_table[1].ao3_static)
            local actions = menu.item_table[2]
            assert.are.equal("actions", actions.role)
            assert.is_truthy(actions.ao3_panel)
            actions.action()
            plugin.readWork = nil
            assert.are.equal(1, #calls)
            assert.are.equal("1", calls[1].id)
            assert.are.equal("Test Work", calls[1].title)
        end)

        it("keeps the decision fields above the fold and omits empty ones", function()
            local menu = open_home()
            local ok, err = pcall(function()
                plugin:showWork({
                    id = "9920", title = "A work", authors = "A writer",
                    summary = "Why read this work", rating = "Teen", warnings = "None",
                    complete = "Complete", tags = "friendship", words = "1200",
                })
            end)
            assert.is_true(ok, err)
            local roles = {}
            for _, row in ipairs(menu.item_table) do
                roles[#roles + 1] = row.role
            end
            assert.are.same({ "hero", "actions", "stats", "facts", "social",
                "summary", "tags" }, roles)

            -- A work with nothing but a title still gets the hero, the
            -- actions and the account actions; empty metadata rows are not
            -- invented.
            plugin:showWork({ id = "9922", title = "Bare", authors = "A" })
            local bare = {}
            for _, row in ipairs(menu.item_table) do
                bare[#bare + 1] = row.role
            end
            assert.are.same({ "hero", "actions", "social" }, bare)
        end)

        it("folds summary and tags away, and expands in place", function()
            local menu = open_home()
            plugin:showWork({
                id = "7000", title = "Folded", authors = "A",
                summary = "The long summary.",
                tags = "friendship, fix-it, slow burn",
            })
            local function roles()
                local out = {}
                for _, row in ipairs(menu.item_table) do
                    out[#out + 1] = row.role
                end
                return out
            end
            local function row_with(role)
                for _, row in ipairs(menu.item_table) do
                    if row.role == role then return row end
                end
            end

            assert.are.same({ "hero", "actions", "social", "summary", "tags" },
                roles())

            -- Expanding replaces the current page instead of pushing a new
            -- one, so Back still returns to the listing that opened the work.
            local depth = #menu.item_table_stack
            row_with("summary").action()
            assert.are.equal(depth, #menu.item_table_stack)
            assert.are.same({ "hero", "actions", "social", "summary",
                "summary_body", "tags" }, roles())

            row_with("summary").action()
            assert.are.same({ "hero", "actions", "social", "summary", "tags" },
                roles())

            row_with("tags").action()
            assert.are.same({ "hero", "actions", "social", "summary", "tags",
                "tags_body" }, roles())
        end)

        it("counts the tags in the folded section header", function()
            local menu = open_home()
            plugin:showWork({
                id = "7001", title = "Tagged", authors = "A",
                tags = "friendship, fix-it, slow burn",
            })
            local tags_row
            for _, row in ipairs(menu.item_table) do
                if row.role == "tags" then tags_row = row end
            end
            assert.is_truthy(tags_row)
            assert.are.equal("Tags · 3", tags_row.label)
        end)

        it("bounds a long summary and offers the full text", function()
            local menu = open_home()
            local function expand(work)
                plugin:showWork(work)
                for _, row in ipairs(menu.item_table) do
                    if row.role == "summary" then row.action() break end
                end
                local more
                for _, row in ipairs(menu.item_table) do
                    if row.role == "summary_more" then more = row end
                end
                return more
            end

            local paragraphs = {}
            for i = 1, 60 do
                paragraphs[#paragraphs + 1] = "Paragraph " .. i
                    .. " with enough words in it to wrap across the page width."
            end
            assert.is_truthy(expand({
                id = "7002", title = "Long", authors = "A",
                summary = table.concat(paragraphs, " "),
            }))

            -- A short summary displays in full, with no extra control.
            assert.is_nil(expand({
                id = "7003", title = "Short", authors = "A",
                summary = "One short paragraph.",
            }))
        end)

        it("opens an author page on the dashboard tab", function()
            local menu = open_home()
            local fetched = {}
            plugin.fetchPage = function(_, url, parse, label, on_success)
                fetched[#fetched + 1] = url
                on_success(parse(read_fixture("author/dashboard.html")))
            end
            local ok, err = pcall(function()
                plugin:showAuthor("Kingsaxcul", "/users/Kingsaxcul/works")
            end)
            plugin.fetchPage = nil
            assert.is_true(ok, err)
            assert.is_truthy(fetched[1]:find("?expand_fandoms=true", 1, true))
            -- The masthead names the author, then the strip, then the shelf
            -- itself: no solid bar, since the works list is one of the tabs.
            local masthead = author_row(menu, "author_identity")
            assert.is_truthy(masthead)
            assert.is_nil(author_row(menu, "author_all_works"))
            assert.are.equal(4, #author_tabs(menu).segments)
            -- The bar names the shelf, not the author again.
            assert.are.equal("Fandoms", menu.ao3_title)
            local fandoms = author_rows(menu, "author_fandom")
            assert.are.equal("Harry Potter - J. K. Rowling", fandoms[1].text)
            assert.are.equal("12 works", fandoms[1].mandatory)
            assert.is_truthy(fandoms[1].ao3_fandom)
        end)

        it("switches author tabs in place and caches each page", function()
            local menu = open_home()
            local calls = 0
            plugin.fetchPage = function(_, url, parse, label, on_success)
                calls = calls + 1
                if url:find("/series", 1, true) then
                    on_success(parse(read_fixture("author/series.html")))
                else
                    on_success(parse(read_fixture("author/dashboard.html")))
                end
            end
            local ok, err = pcall(function()
                plugin:showAuthor("Kingsaxcul", "https://archiveofourown.org/users/Kingsaxcul")
                assert.are.equal(1, calls)
                author_tabs(menu).segments[3].onTap()
                assert.are.equal(2, calls)
                local series = author_rows(menu, "author_series")
                assert.are.equal("Coils AU", series[1].text)
                assert.are.equal("2 works", series[1].mandatory)
                assert.is_truthy(series[1].ao3_series)
                assert.are.equal("Series", menu.ao3_title)
                -- Re-visiting a tab uses its cached page, no extra request.
                author_tabs(menu).segments[3].onTap()
                author_tabs(menu).segments[1].onTap()
                assert.are.equal(2, calls)
            end)
            plugin.fetchPage = nil
            assert.is_true(ok, err)
        end)

        it("opens one fandom's works for the author from the dashboard", function()
            local menu = open_home()
            plugin.fetchPage = function(_, url, parse, label, on_success)
                on_success(parse(read_fixture("author/dashboard.html")))
            end
            local opened_url, opened_title
            plugin.loadListing = function(_, url, title)
                opened_url, opened_title = url, title
            end
            local ok, err = pcall(function()
                plugin:showAuthor("Kingsaxcul", "https://archiveofourown.org/users/Kingsaxcul")
                author_rows(menu, "author_fandom")[1].action()
            end)
            plugin.fetchPage = nil
            plugin.loadListing = nil
            assert.is_true(ok, err)
            assert.are.equal(
                "https://archiveofourown.org/users/Kingsaxcul/works?fandom_id=136512",
                opened_url)
            assert.are.equal("Harry Potter - J. K. Rowling", opened_title)
        end)

        it("opens an author page from the work screen", function()
            local menu = open_home()
            local opened_name, opened_profile
            plugin.showAuthor = function(_, name, profile)
                opened_name, opened_profile = name, profile
            end
            local ok, err = pcall(function()
                plugin:showWork({
                    id = "9930", title = "A work",
                    authors = "A Writer, B Writer",
                    author_names = { "A Writer", "B Writer" },
                    author_urls = { "/users/a/pseuds/A_Writer", "/users/b/pseuds/B_Writer" },
                })
                local author_rows = {}
                for _, row in ipairs(menu.item_table) do
                    if row.role == "author" then
                        author_rows[#author_rows + 1] = row
                    end
                end
                assert.are.equal(2, #author_rows)
                assert.are.equal("A Writer", author_rows[1].text)
                assert.are.equal("B Writer", author_rows[2].text)
                assert.are.equal("Author page", author_rows[1].mandatory)
                author_rows[1].action()
            end)
            plugin.showAuthor = nil
            assert.is_true(ok, err)
            assert.are.equal("A Writer", opened_name)
            assert.are.equal("/users/a/pseuds/A_Writer", opened_profile)
        end)

        it("keeps an anonymous author as plain text", function()
            local menu = open_home()
            local ok, err = pcall(function()
                plugin:showWork({ id = "9931", title = "A work", authors = "Anonymous" })
            end)
            assert.is_true(ok, err)
            for _, row in ipairs(menu.item_table) do
                assert.are_not.equal("author", row.role)
            end
        end)

        it("browses works by a typed author from home", function()
            local UIManager = require("ui/uimanager")
            local old_show, old_close = UIManager.show, UIManager.close
            local shown
            UIManager.show = function(_, widget) shown = widget end
            UIManager.close = function() end
            local opened_url, opened_title
            plugin.showAuthor = function(_, name, profile)
                opened_url, opened_title = name, profile
            end
            local ok, err = pcall(function()
                local author_tile
                for _, row in ipairs(plugin:homeRows()) do
                    for _, entry in ipairs(row.tiles or {}) do
                        if entry.role == "author" then
                            author_tile = entry
                        end
                    end
                end
                assert.is_truthy(author_tile)
                author_tile.action()
                assert.is_truthy(shown)
                shown.getInputValue = function() return "An Author" end
                shown.buttons[1][2].callback()
            end)
            UIManager.show, UIManager.close = old_show, old_close
            plugin.showAuthor = nil
            assert.is_true(ok, err)
            assert.are.equal("An Author", opened_url)
            assert.are.equal(
                "https://archiveofourown.org/users/An%20Author/works", opened_title)
        end)

        it("labels Read as an offline action for a cached work", function()
            local dir = DataStorage:getFullDataDir() .. "/ao3"
            local file = assert(io.open(dir .. "/Available [9921].html", "wb"))
            file:write("offline")
            file:close()
            local menu = open_home()
            local ok, err = pcall(function()
                plugin:showWork({ id = "9921", title = "Available" })
            end)
            assert.is_true(ok, err)
            assert.are.equal("Open saved copy", menu.item_table[2].read_label)
        end)

        it("does not delete the offline copy before Refresh downloads", function()
            local dir = DataStorage:getFullDataDir() .. "/ao3"
            local cached = dir .. "/Keep me [9903].html"
            local file = assert(io.open(cached, "wb"))
            file:write("offline")
            file:close()

            local menu = open_home()
            local old_read = plugin.readWork
            local present_during_download
            plugin.readWork = function(_, id, title, refresh)
                local existing = io.open(cached, "rb")
                present_during_download = existing ~= nil
                if existing then existing:close() end
                assert.are.equal("9903", id)
                assert.is_true(refresh)
            end
            local ok, err = pcall(function()
                plugin:showWork({ id = "9903", title = "Keep me" })
                menu.item_table[2].refresh()
            end)
            plugin.readWork = old_read
            assert.is_true(ok, err)
            assert.is_true(present_during_download)
        end)

        it("shows an empty state when nothing is saved", function()
            clear_downloads()
            local menu = open_home()
            plugin:showDownloads()
            assert.are.equal("No saved works yet.", menu.item_table[1].text)
            assert.is_truthy(menu.ao3_title:find("Downloads", 1, true))
        end)

        it("offers Sign in on the landing page and the account name after it", function()
            local previous = plugin.session
            plugin.session = nil
            local ok, err = pcall(function()
                local menu = open_home()
                local entry = tile(menu, "account")
                assert.is_truthy(entry)
                assert.are.equal("Sign in", entry.text)
                assert.are.equal("login", entry.icon)
                assert.are.equal("Kudos, bookmarks and subscriptions", entry.hint)

                local opened = 0
                local old_show_account = plugin.showAccount
                plugin.showAccount = function() opened = opened + 1 end
                entry.action()
                plugin.showAccount = old_show_account

                -- Signing in replaces the way in with the reader's own name;
                -- the tile keeps its position and becomes the account door.
                plugin.session = { username = "demo_reader" }
                menu = open_home()
                entry = tile(menu, "account")
                assert.are.equal("demo_reader", entry.text)
                assert.are.equal("user", entry.icon)
                assert.are.equal(
                    "Bookmarks, marked for later, history, subscriptions",
                    entry.hint)
                assert.are.equal(1, opened)
            end)
            plugin.session = previous
            assert.is_true(ok, err)
        end)

        it("asks for sign-in when the account tile is tapped anonymously", function()
            local previous = plugin.session
            plugin.session = nil
            local called = 0
            local old_login = plugin.loginDialog
            plugin.loginDialog = function() called = called + 1 end
            local ok, err = pcall(function()
                local menu = open_home()
                tile(menu, "account").action()
            end)
            plugin.loginDialog = old_login
            plugin.session = previous
            assert.is_true(ok, err)
            assert.are.equal(1, called)
        end)

        it("lays the account page out as AO3's four lists plus log out", function()
            local previous = plugin.session
            plugin.session = { username = "demo_reader" }
            local menu = open_home()
            local ok, err = pcall(function() plugin:showAccount() end)
            local roles = {}
            for _, row in ipairs(menu.item_table) do
                roles[#roles + 1] = row.role
            end
            local texts = {}
            for _, row in ipairs(menu.item_table) do
                if row.text then texts[#texts + 1] = row.text end
            end
            plugin.session = previous
            assert.is_true(ok, err)
            assert.are.same({ "account_hero", "lists_label",
                "list_bookmarks", "list_marked", "list_history",
                "list_subscriptions", "author_label", "works", "session" },
                roles)
            assert.are.equal(
                "Bookmarks|Marked for later|History|Subscriptions"
                .. "|Works by demo_reader",
                table.concat(texts, "|"))
        end)

        it("logs out back to a home page that offers sign in again", function()
            local previous = plugin.session
            plugin.session = { username = "demo_reader" }
            local menu = open_home()
            local ok, err = pcall(function()
                plugin:showAccount()
                -- The session panel holds one control: the outlined Log out.
                local button
                local function walk(widget)
                    if widget.onTap and not button then button = widget end
                    for _, child in ipairs(widget) do walk(child) end
                end
                walk(menu.item_table[#menu.item_table].ao3_static)
                assert.is_truthy(button)
                button.onTap()
            end)
            local signed_out = plugin.session
            menu = open_home()
            local entry = tile(menu, "account")
            plugin.session = previous
            assert.is_true(ok, err)
            assert.is_nil(signed_out)
            assert.are.equal("Sign in", entry.text)
        end)

        it("checks the work actions that are already on", function()
            local menu = open_home()
            plugin.work_social = { ["9001"] = { kudos = true, bookmark = true } }
            local ok, err = pcall(function()
                plugin:showWork({ id = "9001", title = "Marked", authors = "A" })
            end)
            plugin.work_social = nil
            assert.is_true(ok, err)

            local social
            for _, row in ipairs(menu.item_table) do
                if row.role == "social" then social = row.ao3_static end
            end
            assert.is_truthy(social)
            local marked = {}
            local function walk(widget)
                if widget.text and widget.text:find("✓", 1, true) then
                    marked[#marked + 1] = widget.text
                end
                for _, child in ipairs(widget) do walk(child) end
            end
            walk(social)
            assert.are.equal(2, #marked)
            assert.is_truthy(marked[1]:find("Kudos", 1, true))
            assert.is_truthy(marked[2]:find("Bookmark", 1, true))
        end)

        it("tells a signed-out reader what the account actions need", function()
            local previous = plugin.session
            plugin.session = nil
            local menu = open_home()
            local ok, err = pcall(function()
                plugin:showWork({ id = "9002", title = "Anon", authors = "A" })
            end)
            plugin.session = previous
            assert.is_true(ok, err)
            local social
            for _, row in ipairs(menu.item_table) do
                if row.role == "social" then social = row.ao3_static end
            end
            local found
            local function walk(widget)
                if widget.text and widget.text:find("Sign in", 1, true) then
                    found = widget.text
                end
                for _, child in ipairs(widget) do walk(child) end
            end
            walk(social)
            assert.are.equal("Sign in to your AO3 account to use these.", found)
        end)

        it("lists cached works newest first", function()
            clear_downloads()
            local DataStorage = require("datastorage")
            local lfs = require("libs/libkoreader-lfs")
            local dir = DataStorage:getFullDataDir() .. "/ao3"

            local function write(name, mtime)
                local path = dir .. "/" .. name
                local f = assert(io.open(path, "wb"))
                f:write("<html></html>")
                f:close()
                assert.is_truthy(lfs.touch(path, mtime, mtime))
            end
            write("Older Work [111].html", os.time() - 600)
            write("Newer Work [222].html", os.time())

            local items = plugin:listDownloads()
            assert.are.equal(2, #items)
            assert.are.equal("Newer Work", items[1].title)
            assert.are.equal("222", items[1].id)
            assert.are.equal("Older Work", items[2].title)
        end)
    end)

    describe("menu", function()
        it("registers a single AO3 entry that opens the home screen", function()
            local registered
            local self = setmetatable({
                ui = {
                    menu = {
                        registerToMainMenu = function(_, p)
                            registered = p
                        end,
                    },
                },
            }, { __index = Ao3 })

            self:init()
            assert.are.equal(self, registered)

            local menu = {}
            self:addToMainMenu(menu)
            assert.is_truthy(menu.ao3_browser)
            assert.are.equal("KO3", menu.ao3_browser.text)
            assert.are.equal("tools", menu.ao3_browser.sorting_hint)
            assert.is_truthy(menu.ao3_browser.callback)
            assert.is_nil(menu.ao3_browser.sub_item_table)

            -- Directly on the Tools tab, fourth from the top so it stays on
            -- the first page instead of being pushed to page 2.
            local order = require("ui/elements/reader_menu_order")
            local at
            for i, id in ipairs(order.tools) do
                if id == "ao3_browser" then at = i end
            end
            assert.are.equal(4, at)
        end)
    end)
end)

describe("AO3 reader hooks", function()
    local function fake_reader()
        local reader = {
            closed = false,
            status = {},
            document = {
                getToc = function()
                    return {
                        { title = "Preface", depth = 0, page = 1 },
                        { title = "A Work", depth = 0, page = 1 },
                        { title = "Chapter 1", depth = 1, page = 2 },
                    }
                end,
            },
        }
        reader.menu = {
            registerToMainMenu = function(_, widget) reader.registered = widget end,
            onCloseReaderMenu = function() reader.menu_closed = true end,
        }
        reader.toc = {
            resetToc = function(this) this.was_reset = true end,
            onShowToc = function(this)
                this.toc_menu = {
                    is_enable_shortcut = true,
                    items_per_page = 14,
                    page = 1,
                    dimen = {},
                    updateItems = function(menu) menu.updated = true end,
                }
            end,
        }
        reader.onClose = function(this)
            this.closed = true
            this.document = nil
        end
        return reader
    end

    it("cleans the TOC the reader sees", function()
        local reader = fake_reader()
        plugin:installReaderHooks(reader)
        local toc = reader.document:getToc()
        assert.are.equal(1, #toc)
        assert.are.equal("Chapter 1", toc[1].title)
        assert.are.equal(0, toc[1].depth)
    end)

    it("returns to the AO3 screen from Home/Back", function()
        local reader = fake_reader()
        plugin.menu = nil
        plugin:installReaderHooks(reader)
        assert.is_true(reader.onHome())
        assert.is_true(reader.closed)
    end)

    it("adds a Back to AO3 item to the reader menu", function()
        local reader = fake_reader()
        plugin.menu = nil
        plugin:installReaderHooks(reader)
        local items = {}
        reader.registered:addToMainMenu(items)
        assert.are.equal("Back to AO3", items.ao3_back_to_browser.text)
        assert.are.equal("navi", items.ao3_back_to_browser.sorting_hint)
        items.ao3_back_to_browser.callback()
        assert.is_true(reader.menu_closed)
        assert.is_true(reader.closed)
    end)

    it("drops the TOC cache filled before the hooks were installed", function()
        local reader = fake_reader()
        plugin:installReaderHooks(reader)
        assert.is_true(reader.toc.was_reset)
    end)

    it("hides the TOC's shortcut boxes and gives rows more padding", function()
        local reader = fake_reader()
        plugin:installReaderHooks(reader)
        reader.toc:onShowToc()
        local menu = reader.toc.toc_menu
        assert.is_false(menu.is_enable_shortcut)
        assert.are.equal(11, menu.items_per_page)
        assert.is_true(menu.updated)
    end)

    it("puts Back to AO3 at the bottom of the first Navigation page", function()
        local reader = fake_reader()
        plugin:installReaderHooks(reader)
        local order = require("ui/elements/reader_menu_order")
        local after_skim, found = false, false
        for _, key in ipairs(order.navi) do
            if key == "skim_to" then after_skim = true
            elseif after_skim and key == "ao3_back_to_browser" then found = true break
            elseif key ~= "----------------------------" and after_skim then break end
        end
        assert.is_true(found)
    end)

    it("keeps the standard end-of-document handler", function()
        local reader = fake_reader()
        local called = false
        reader.status.onEndOfBook = function() called = true end
        plugin:installReaderHooks(reader)
        reader.status:onEndOfBook()
        assert.is_true(called)
    end)
end)
