-- KOReader busted spec for the AO3 browser plugin.
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
            assert.are.equal("AO3 browser", loaded.fullname)
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
                assert.are.equal(200, plugin:findFandomOffset(category, "N", "name 207"))
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

        it("opens a home menu with the browse entries", function()
            local menu = open_home()
            assert.is_truthy(menu)
            assert.are.equal("AO3", menu.title_bar.title)

            local joined = texts(menu)
            assert.is_truthy(joined:find("Latest works", 1, true))
            assert.is_truthy(joined:find("Fandoms", 1, true))
            assert.is_truthy(joined:find("Search", 1, true))
            assert.is_truthy(joined:find("Author", 1, true))
            assert.is_truthy(joined:find("Downloads", 1, true))
            assert.is_truthy(joined:find("Open work", 1, true))
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
            assert.are.equal("AO3", menu.ao3_title)
            assert.is_truthy(texts(menu):find("Latest works", 1, true))
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
            assert.are.equal("AO3", menu.ao3_title)
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
            assert.are.same({ "hero", "actions", "stats", "facts",
                "summary", "tags" }, roles)

            -- A work with nothing but a title still gets the hero and the
            -- actions; empty metadata rows are not invented.
            plugin:showWork({ id = "9922", title = "Bare", authors = "A" })
            local bare = {}
            for _, row in ipairs(menu.item_table) do
                bare[#bare + 1] = row.role
            end
            assert.are.same({ "hero", "actions" }, bare)
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

            assert.are.same({ "hero", "actions", "summary", "tags" }, roles())

            -- Expanding replaces the current page instead of pushing a new
            -- one, so Back still returns to the listing that opened the work.
            local depth = #menu.item_table_stack
            row_with("summary").action()
            assert.are.equal(depth, #menu.item_table_stack)
            assert.are.same({ "hero", "actions", "summary", "summary_body",
                "tags" }, roles())

            row_with("summary").action()
            assert.are.same({ "hero", "actions", "summary", "tags" }, roles())

            row_with("tags").action()
            assert.are.same({ "hero", "actions", "summary", "tags",
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
            -- The tab strip is the first row, then the fandom list.
            assert.is_truthy(menu.item_table[1].ao3_tabs)
            assert.are.equal("Harry Potter - J. K. Rowling", menu.item_table[2].text)
            assert.are.equal("12 works", menu.item_table[2].mandatory)
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
                menu.item_table[1].ao3_tabs[3].callback()
                assert.are.equal(2, calls)
                assert.are.equal("Coils AU", menu.item_table[2].text)
                assert.are.equal("2 works", menu.item_table[2].mandatory)
                assert.is_truthy(menu.ao3_title:find("2 series", 1, true))
                -- Re-visiting a tab uses its cached page, no extra request.
                menu.item_table[1].ao3_tabs[3].callback()
                menu.item_table[1].ao3_tabs[1].callback()
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
                menu.item_table[2].action()
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
                local author_row
                for _, row in ipairs(plugin:homeRows()) do
                    if type(row) == "table" and row.text == "Author" then
                        author_row = row
                        break
                    end
                end
                assert.is_truthy(author_row)
                author_row.action()
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
            assert.are.equal("AO3", menu.ao3_browser.text)
            assert.are.equal("more_tools", menu.ao3_browser.sorting_hint)
            assert.is_truthy(menu.ao3_browser.callback)
            assert.is_nil(menu.ao3_browser.sub_item_table)
        end)
    end)
end)
