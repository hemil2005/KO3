-- KOReader busted spec for AO3 account sign-in.
--
-- Offline: the login handshake is mocked with the same HTTP interface as the
-- fixture-backed ao3_spec. Fixtures under spec/fixtures/account are trimmed
-- pages: login.html is real AO3 markup captured 2026-11-23; subscriptions.html
-- mirrors AO3's li.subscription markup so the tolerant parser is covered.

require("commonrequire")

local DataStorage = require("datastorage")
local http = require("socket.http")
local socket = require("socket")
local lfs = require("libs/libkoreader-lfs")
local socketutil = require("socketutil")

local Ao3 = dofile("plugins/ao3.koplugin/main.lua")
local Account = dofile("plugins/ao3.koplugin/account.lua")
local AuthorPage = dofile("plugins/ao3.koplugin/authorpage.lua")

local plugin = setmetatable({}, { __index = Ao3 })

local fixture_dir = "plugins/ao3.koplugin/spec/fixtures/account/"

local function read_fixture(name)
    local f = assert(io.open(fixture_dir .. name, "rb"))
    local body = f:read("*a")
    f:close()
    return body
end

local function read_root_fixture(name)
    local f = assert(io.open("plugins/ao3.koplugin/spec/fixtures/" .. name, "rb"))
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

local function has_row(rows, needle)
    for _, row in ipairs(rows) do
        if (row.text or ""):find(needle, 1, true) then return true end
    end
    return false
end

local tmp_root, settings_dir
local saved = {}

setup(function()
    tmp_root = os.tmpname()
    os.remove(tmp_root)
    assert(lfs.mkdir(tmp_root))
    settings_dir = tmp_root .. "/settings"
    assert(lfs.mkdir(settings_dir))

    saved.get_full = DataStorage.getFullDataDir
    DataStorage.getFullDataDir = function() return tmp_root end
    saved.get_settings = DataStorage.getSettingsDir
    DataStorage.getSettingsDir = function() return settings_dir end

    saved.set_timeout = socketutil.set_timeout
    saved.reset_timeout = socketutil.reset_timeout
    socketutil.set_timeout = function() end
    socketutil.reset_timeout = function() end

    -- The request throttle sleeps one second between calls; tests do not need
    -- to wait for it.
    saved.sleep = socket.sleep
    socket.sleep = function() end
end)

teardown(function()
    DataStorage.getFullDataDir = saved.get_full
    DataStorage.getSettingsDir = saved.get_settings
    socketutil.set_timeout = saved.set_timeout
    socketutil.reset_timeout = saved.reset_timeout
    socket.sleep = saved.sleep
    if tmp_root then remove_tree(tmp_root) end
end)

local function with_http(mock, fn)
    local old_request = http.request
    http.request = mock
    local ok, err = pcall(fn)
    http.request = old_request
    assert(ok, err)
end

local function read_source(source)
    local chunks = {}
    if not source then return "" end
    while true do
        local chunk, err = source()
        if chunk == nil then
            assert(err == nil, tostring(err))
            break
        end
        chunks[#chunks + 1] = chunk
    end
    return table.concat(chunks)
end

describe("AO3 account", function()
    describe("login form parsing", function()
        it("reads the hidden authenticity token", function()
            local html = read_fixture("login.html")
            assert.are.equal("form-token-123", Account.parseCsrf(html))
        end)

        it("falls back to the csrf-token meta tag", function()
            local html = '<meta name="csrf-token" content="meta-only" />'
            assert.are.equal("meta-only", Account.parseCsrf(html))
        end)

        it("returns nil when the page has no token", function()
            assert.is_nil(Account.parseCsrf("<html><body>Nothing</body></html>"))
        end)

        it("reads the JSON token from the token endpoint", function()
            assert.are.equal("abc123", Account.parseToken('{"token":"abc123"}'))
            assert.are.equal("fallback", Account.parseToken('not json "token":"fallback"'))
            assert.is_nil(Account.parseToken('{"other":1}'))
            assert.is_nil(Account.parseToken(""))
        end)

        it("builds a Rails login body", function()
            local body = Account.loginBody("tok", "me@example.com", "p&ss word")
            assert.is_truthy(body:find("authenticity_token=tok", 1, true))
            assert.is_truthy(body:find("user%5Blogin%5D=me%40example.com", 1, true))
            assert.is_truthy(body:find("user%5Bpassword%5D=p%26ss%20word", 1, true))
            assert.is_truthy(body:find("user%5Bremember_me%5D=1", 1, true))
            assert.is_truthy(body:find("commit=Log+In", 1, true))
        end)

        it("recognizes the login form and a flash error", function()
            local login = read_fixture("login.html")
            assert.is_true(Account.isLoginPage(login))
            assert.is_false(Account.isLoginPage(read_fixture("subscriptions.html")))

            local failed = read_fixture("login_error.html")
            assert.are.equal("Invalid username or password.", Account.loginError(failed))
        end)
    end)

    describe("session cookies", function()
        it("keeps only AO3's own session cookies", function()
            local jar, changed = Account.mergeCookies({}, table.concat({
                "_otwarchive_session=abc123; path=/; HttpOnly; Secure",
                "remember_user_token=rem456; path=/",
                "__cf_bm=bot; path=/",
                "cf_clearance=pass; path=/",
            }, ", "))
            assert.is_true(changed)
            assert.are.equal("abc123", jar._otwarchive_session)
            assert.are.equal("rem456", jar.remember_user_token)
            assert.is_nil(jar.__cf_bm)
            assert.is_nil(jar.cf_clearance)
            assert.are.equal(
                "_otwarchive_session=abc123; remember_user_token=rem456",
                Account.cookieHeader(jar))
        end)

        it("reports no change for a repeated cookie", function()
            local jar = { _otwarchive_session = "same" }
            local _, changed = Account.mergeCookies(jar, "_otwarchive_session=same")
            assert.is_false(changed)
        end)

        it("accepts a table of Set-Cookie headers", function()
            local jar, changed = Account.mergeCookies({}, {
                "_otwarchive_session=first; path=/",
                "remember_user_token=second; path=/",
                "__cf_bm=drop; path=/",
            })
            assert.is_true(changed)
            assert.are.equal("first", jar._otwarchive_session)
            assert.are.equal("second", jar.remember_user_token)
            assert.is_nil(jar.__cf_bm)
        end)

        it("does not let an expired session cookie overwrite the live one", function()
            local live_then_delete = Account.mergeCookies({}, table.concat({
                "_otwarchive_session=live; path=/",
                "_otwarchive_session=old; path=/; max-age=0",
            }, ", "))
            assert.are.equal("live", live_then_delete._otwarchive_session)

            local delete_then_live = Account.mergeCookies({}, table.concat({
                "_otwarchive_session=old; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT",
                "_otwarchive_session=live; path=/",
            }, ", "))
            assert.are.equal("live", delete_then_live._otwarchive_session)
        end)

        it("round-trips a session through settings", function()
            local path = settings_dir .. "/session-test.lua"
            local session = {
                username = "testuser",
                cookies = { _otwarchive_session = "sess-1" },
                saved_at = 123,
            }
            assert.is_true(Account.save(path, session))
            local loaded = Account.load(path)
            assert.are.equal("testuser", loaded.username)
            assert.are.equal("sess-1", loaded.cookies._otwarchive_session)
            assert.is_nil(loaded.password)
            assert.is_true(Account.clear(path))
            assert.is_nil(Account.load(path))
        end)

        it("refuses to save a jar without a session cookie", function()
            local path = settings_dir .. "/empty.lua"
            assert.is_false(Account.save(path, { cookies = {} }))
            assert.is_nil(Account.load(path))
        end)

        it("removes the settings backup when logging out", function()
            local path = settings_dir .. "/backup-test.lua"
            Account.save(path, {
                username = "testuser",
                cookies = { _otwarchive_session = "secret" },
            })
            local backup = assert(io.open(path .. ".old", "wb"))
            backup:write("return { session = { cookies = { _otwarchive_session = 'secret' } } }")
            backup:close()
            assert.is_true(Account.clear(path))
            assert.is_nil(lfs.attributes(path .. ".old", "mode"))
        end)
    end)

    describe("greeting and URLs", function()
        it("learns the account name from the header greeting", function()
            assert.are.equal("testuser", Account.loggedInName(read_fixture("logged_in.html")))
            assert.is_nil(Account.loggedInName("<html><body>Hi!</body></html>"))
        end)

        it("builds personal-list URLs", function()
            assert.are.equal(
                "https://archiveofourown.org/users/name_here/marked_for_later",
                Account.listUrl("name_here", "/marked_for_later"))
            assert.is_nil(Account.listUrl("", "/bookmarks"))
        end)
    end)

    describe("sign-in handshake", function()
        it("posts credentials once and keeps the session cookie", function()
            local token_json = '{"token":"form-token-123"}'
            local seen = {}
            with_http(function(req)
                seen[#seen + 1] = req
                if req.url == Account.TOKEN_URL and (req.method or "GET") == "GET" then
                    req.sink(token_json)
                    req.sink(nil)
                    return 1, 200, {
                        ["set-cookie"] = "_otwarchive_session=anonymous-1; path=/; HttpOnly, __cf_bm=bot; path=/",
                    }, "OK"
                elseif req.method == "POST" then
                    local body = read_source(req.source)
                    assert.are.equal("POST", req.method)
                    assert.is_truthy(body:find("authenticity_token=form-token-123", 1, true))
                    assert.is_truthy(body:find("user%5Blogin%5D=testuser", 1, true))
                    assert.is_truthy(body:find("user%5Bpassword%5D=hunter2", 1, true))
                    assert.are.equal(
                        "_otwarchive_session=anonymous-1; view_adult=true",
                        req.headers["Cookie"])
                    assert.are.equal("https://archiveofourown.org/users/login", req.url)
                    req.sink("")
                    req.sink(nil)
                    return 1, 302, {
                        location = "/",
                        ["set-cookie"] = "_otwarchive_session=logged-in-2; path=/; HttpOnly; Secure",
                    }, "Found"
                else
                    assert.are.equal("https://archiveofourown.org/", req.url)
                    assert.is_truthy(req.headers["Cookie"]:find(
                        "_otwarchive_session=logged-in-2", 1, true))
                    req.sink(read_fixture("logged_in.html"))
                    req.sink(nil)
                    return 1, 200, {}, "OK"
                end
            end, function()
                local session, err = plugin:performLogin("testuser", "hunter2")
                assert.is_nil(err)
                assert.are.equal("testuser", session.username)
                assert.are.equal("logged-in-2", session.cookies._otwarchive_session)
                assert.is_nil(session.cookies.__cf_bm)
                assert.is_nil(session.password)
                assert.are.equal(3, #seen)
            end)
        end)

        it("rejects a redirect back to the form even though a cookie was set", function()
            local login_html = read_fixture("login.html")
            with_http(function(req)
                if req.method == "POST" then
                    read_source(req.source)
                    req.sink("")
                    req.sink(nil)
                    return 1, 302, { location = "/users/login" }, "Found"
                elseif req.url == Account.TOKEN_URL then
                    req.sink('{"token":"form-token-123"}')
                    req.sink(nil)
                    return 1, 200, {
                        ["set-cookie"] = "_otwarchive_session=anonymous-only; path=/",
                    }, "OK"
                end
                req.sink(login_html)
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local session, err = plugin:performLogin("testuser", "wrong")
                assert.is_nil(session)
                assert.is_truthy(err:find("did not confirm", 1, true))
            end)
        end)

        it("surfaces AO3's flash error for a rejected sign-in", function()
            local failed = read_fixture("login_error.html")
            with_http(function(req)
                if (req.method or "GET") == "GET" then
                    req.sink('{"token":"form-token-123"}')
                else
                    read_source(req.source)
                    req.sink(failed)
                end
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local session, err = plugin:performLogin("testuser", "wrong")
                assert.is_nil(session)
                assert.are.equal("Invalid username or password.", err)
            end)
        end)
    end)

    describe("requests", function()
        it("sends the saved session and view_adult cookies", function()
            local seen
            plugin.session = {
                username = "testuser",
                cookies = { _otwarchive_session = "sess-9" },
            }
            with_http(function(req)
                seen = req
                req.sink("<html>ok</html>")
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local body = plugin:fetchHtml("https://archiveofourown.org/users/testuser/bookmarks")
                assert.are.equal("<html>ok</html>", body)
            end)
            assert.are.equal(
                "_otwarchive_session=sess-9; view_adult=true",
                seen.headers["Cookie"])
            plugin.session = nil
        end)

        it("absorbs a rotated session cookie and persists it", function()
            plugin.session = {
                username = "testuser",
                cookies = { _otwarchive_session = "old" },
            }
            with_http(function(req)
                req.sink("ok")
                req.sink(nil)
                return 1, 200, {
                    ["set-cookie"] = "_otwarchive_session=new; path=/, cf_clearance=drop-me; path=/",
                }, "OK"
            end, function()
                plugin:fetchHtml("https://archiveofourown.org/")
            end)
            assert.are.equal("new", plugin.session.cookies._otwarchive_session)
            assert.is_nil(plugin.session.cookies.cf_clearance)
            local saved_session = Account.load(settings_dir .. "/ao3.lua")
            assert.are.equal("new", saved_session.cookies._otwarchive_session)
            plugin.session = nil
        end)

        it("drops a session when AO3 shows the login form again", function()
            plugin.session = {
                username = "testuser",
                cookies = { _otwarchive_session = "stale" },
            }
            local parse = plugin:accountParser("bookmarks")
            local data, err = parse(read_fixture("login.html"))
            assert.is_nil(data)
            assert.is_truthy(err:find("expired", 1, true))
            assert.is_nil(plugin.session)
        end)

        it("does not send the session to a non-AO3 host", function()
            local seen
            plugin.session = {
                username = "testuser",
                cookies = { _otwarchive_session = "private" },
            }
            with_http(function(req)
                seen = req
                req.sink("ok")
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                plugin:fetchHtml("https://example.test/page")
            end)
            assert.are.equal("view_adult=true", seen.headers["Cookie"])
            plugin.session = nil
        end)

        it("follows a redirect without leaking the session cookie", function()
            local calls = {}
            plugin.session = {
                username = "testuser",
                cookies = { _otwarchive_session = "keep-me" },
            }
            with_http(function(req)
                calls[#calls + 1] = req
                if req.url == "https://archiveofourown.org/start" then
                    req.sink("")
                    req.sink(nil)
                    return 1, 302, { location = "https://example.test/away" }, "Found"
                end
                req.sink("final")
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local body = plugin:fetchHtml("https://archiveofourown.org/start")
                assert.are.equal("final", body)
            end)
            assert.are.equal(2, #calls)
            assert.are.equal("_otwarchive_session=keep-me; view_adult=true",
                calls[1].headers["Cookie"])
            assert.are.equal("view_adult=true", calls[2].headers["Cookie"])
            plugin.session = nil
        end)

        it("refuses a redirect from HTTPS to HTTP", function()
            local calls = 0
            with_http(function(req)
                calls = calls + 1
                req.sink("")
                req.sink(nil)
                return 1, 302, { location = "http://archiveofourown.org/works" }, "Found"
            end, function()
                local body, err = plugin:fetchHtml("https://archiveofourown.org/works")
                assert.is_nil(body)
                assert.is_truthy(err:find("insecure", 1, true))
            end)
            assert.are.equal(1, calls)
        end)

        it("keeps the session on the download host and off a foreign redirect", function()
            local work_html = read_root_fixture("work.html")
            local calls = {}
            plugin.session = {
                username = "testuser",
                cookies = { _otwarchive_session = "download-session" },
            }
            with_http(function(req)
                calls[#calls + 1] = req
                if req.url:find("download.archiveofourown.org", 1, true) then
                    req.sink("")
                    req.sink(nil)
                    return 1, 302, { location = "https://example.test/work.html" }, "Found"
                end
                assert.is_nil(req.headers["Cookie"]:find("download-session", 1, true))
                req.sink(work_html)
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local path, err = plugin:downloadWork("54321", "Test Work")
                assert.is_nil(err)
                assert.is_truthy(path)
                os.remove(path)
            end)
            assert.are.equal(2, #calls)
            assert.is_truthy(calls[1].headers["Cookie"]:find("download-session", 1, true))
            plugin.session = nil
        end)
    end)

    describe("home screen", function()
        it("offers Sign in when signed out", function()
            plugin.session = nil
            local rows = plugin:homeRows()
            assert.is_true(has_row(rows, "Sign in"))
            assert.is_true(has_row(rows, "Browse"))
            assert.is_true(has_row(rows, "Downloads"))
        end)

        it("shows the account name when signed in", function()
            plugin.session = { username = "testuser", cookies = { _otwarchive_session = "x" } }
            local rows = plugin:homeRows()
            assert.is_true(has_row(rows, "Signed in as testuser"))
            assert.is_false(has_row(rows, "Sign in"))
            plugin.session = nil
        end)
    end)

    describe("subscriptions", function()
        it("classifies work, series and user subscriptions", function()
            local data = assert(AuthorPage.parseSubscriptions(read_fixture("subscriptions.html")))
            assert.are.equal(3, #data.items)
            assert.are.equal("3", data.count)

            assert.are.equal("work", data.items[1].kind)
            assert.are.equal("111", data.items[1].id)
            assert.are.equal("A Subscribed Work", data.items[1].title)
            assert.are.equal("Author One", data.items[1].authors)

            assert.are.equal("series", data.items[2].kind)
            assert.are.equal("222", data.items[2].id)

            assert.are.equal("user", data.items[3].kind)
            assert.are.equal("authorthree", data.items[3].name)
        end)

        it("keeps rows readable for each kind", function()
            local data = assert(AuthorPage.parseSubscriptions(read_fixture("subscriptions.html")))
            plugin.session = { username = "testuser", cookies = { _otwarchive_session = "x" } }
            local rows = plugin:accountRows("subscriptions", data)
            assert.are.equal(3, #rows)
            assert.are.equal("A Subscribed Work", rows[1].text)
            assert.are.equal("A Subscribed Series", rows[2].text)
            assert.are.equal("Series", rows[2].mandatory)
            assert.are.equal("Author Three", rows[3].text)
            assert.are.equal("Author", rows[3].mandatory)
            plugin.session = nil
        end)

        it("shows an empty state and paging rows", function()
            local rows = plugin:accountRows("bookmarks", {
                items = {},
                next_url = "https://archiveofourown.org/users/me/bookmarks?page=2",
            })
            assert.are.equal("No bookmarks.", rows[1].text)
            assert.are.equal("Next page →", rows[#rows].text)
        end)
    end)

    describe("work actions", function()
        local work = { id = "123", title = "A Test Work" }

        local function signed_in()
            plugin.session = {
                username = "testuser",
                cookies = { _otwarchive_session = "live-session" },
            }
            plugin.work_actions = nil
            plugin.csrf_token = nil
            plugin.csrf_fingerprint = nil
            plugin.blocked_until = nil
            plugin.blocked_code = nil
        end

        local function token_request(req)
            req.sink('{"token":"tok-123"}')
            req.sink(nil)
            return 1, 200, {}, "OK"
        end

        it("builds the website's own action requests", function()
            local url, body = Account.workActionRequest("kudos", "123", "tok")
            assert.are.equal("https://archiveofourown.org/kudos.js", url)
            assert.is_truthy(body:find("kudo%5Bcommentable_id%5D=123", 1, true))
            assert.is_truthy(body:find("kudo%5Bcommentable_type%5D=Work", 1, true))
            assert.is_truthy(body:find("authenticity_token=tok", 1, true))

            url, body = Account.workActionRequest("bookmark", "123", "tok", {
                pseud_id = "3",
                notes = "Loved it & saved it",
                tags = "comfort",
                private = true,
                rec = true,
            })
            assert.are.equal("https://archiveofourown.org/works/123/bookmarks", url)
            assert.is_truthy(body:find("bookmark%5Bpseud_id%5D=3", 1, true))
            assert.is_truthy(body:find("bookmark%5Bprivate%5D=1", 1, true))
            assert.is_truthy(body:find("bookmark%5Brec%5D=1", 1, true))
            assert.is_truthy(body:find("Loved%20it%20%26%20saved%20it", 1, true))

            url, body = Account.workActionRequest("subscribe", "123", "tok", {
                username = "testuser",
            })
            assert.are.equal(
                "https://archiveofourown.org/users/testuser/subscriptions.json", url)
            assert.is_truthy(body:find(
                "subscription%5Bsubscribable_id%5D=123", 1, true))

            url, body = Account.workActionRequest("mark_for_later", "123", "tok")
            assert.are.equal(
                "https://archiveofourown.org/works/123/mark_for_later", url)
            assert.is_truthy(body:find("_method=patch", 1, true))

            assert.is_nil(Account.workActionRequest("unbookmark", "123", "tok"))
            assert.is_nil(Account.workActionRequest("kudos", "not-a-number", "tok"))
        end)

        it("reads a fresh work page's action state", function()
            local state = assert(Account.parseWorkActions(
                read_fixture("work_actions_new.html")))
            assert.are.equal("work-token-abc", state.token)
            assert.is_true(state.signed_in)
            assert.is_true(state.kudos_available)
            assert.is_false(state.kudos_done)

            assert.is_true(state.bookmark.available)
            assert.is_false(state.bookmark.bookmarked)
            assert.is_nil(state.bookmark.id)
            assert.are.equal("3", state.bookmark.pseud_id)

            assert.is_true(state.subscribe.available)
            assert.is_false(state.subscribe.subscribed)
            assert.are.equal("testuser", state.subscribe.username)

            assert.is_true(state.mark_available)
            assert.is_false(state.marked_for_later)
        end)

        it("reads an already bookmarked, subscribed and marked work", function()
            local state = assert(Account.parseWorkActions(
                read_fixture("work_actions_existing.html")))
            assert.is_true(state.bookmark.bookmarked)
            assert.are.equal("77", state.bookmark.id)
            assert.is_true(state.subscribe.subscribed)
            assert.are.equal("45", state.subscribe.id)
            assert.is_true(state.marked_for_later)
        end)

        it("reads the selected pseud when the user has several", function()
            local state = assert(Account.parseWorkActions([[
                <html><body class="logged-in">
                <div class="post bookmark" id="bookmark-form">
                  <form action="/works/123/bookmarks" method="post">
                    <select name="bookmark[pseud_id]">
                      <option value="9">Other Pseud</option>
                      <option selected="selected" value="3">Test User</option>
                    </select>
                  </form>
                </div>
                </body></html>
            ]]))
            assert.are.equal("3", state.bookmark.pseud_id)
            -- A bookmark form alone is not a Mark for Later form.
            assert.is_false(state.mark_available)
        end)

        it("does not invent forms on a signed-out work page", function()
            local state = assert(Account.parseWorkActions(
                read_root_fixture("work.html")))
            assert.is_false(state.signed_in)
            assert.is_false(state.bookmark.available)
            assert.is_false(state.subscribe.available)
            assert.is_false(state.mark_available)
            assert.is_false(state.kudos_available)
        end)

        it("leaves kudos once with the token endpoint's token", function()
            signed_in()
            local calls = {}
            with_http(function(req)
                calls[#calls + 1] = req
                if req.url == Account.TOKEN_URL then return token_request(req) end
                assert.are.equal("POST", req.method)
                assert.are.equal("https://archiveofourown.org/kudos.js", req.url)
                local body = read_source(req.source)
                assert.is_truthy(body:find("kudo%5Bcommentable_id%5D=123", 1, true))
                req.sink("")
                req.sink(nil)
                return 1, 201, {}, "Created"
            end, function()
                local result, err = plugin:performWorkAction(work, "kudos")
                assert.is_nil(err)
                assert.is_true(result.done)
                assert.is_false(result.already or false)
            end)
            assert.are.equal(2, #calls)
            assert.is_truthy(calls[2].headers["Cookie"]:find(
                "live-session", 1, true))
        end)

        it("treats AO3's duplicate-kudos answer as already done", function()
            signed_in()
            with_http(function(req)
                if req.url == Account.TOKEN_URL then return token_request(req) end
                req.sink('{"error_message":"You have already left kudos here. :)"}')
                req.sink(nil)
                return 1, 422, {}, "Unprocessable Entity"
            end, function()
                local result, err = plugin:performWorkAction(work, "kudos")
                assert.is_nil(err)
                assert.is_true(result.done)
                assert.is_true(result.already)
                assert.is_truthy(result.message:find("already left kudos", 1, true))
            end)
        end)

        it("creates a bookmark with the work page's pseud and a fresh token", function()
            signed_in()
            local calls = {}
            with_http(function(req)
                calls[#calls + 1] = req
                if req.url == "https://archiveofourown.org/works/123" then
                    req.sink(read_fixture("work_actions_new.html"))
                    req.sink(nil)
                    return 1, 200, {}, "OK"
                end
                if req.url == Account.TOKEN_URL then return token_request(req) end
                assert.are.equal("POST", req.method)
                assert.are.equal(
                    "https://archiveofourown.org/works/123/bookmarks", req.url)
                local body = read_source(req.source)
                assert.is_truthy(body:find("bookmark%5Bpseud_id%5D=3", 1, true))
                -- The work page's own token is form-scoped; use the fresh one.
                assert.is_truthy(body:find("authenticity_token=tok-123", 1, true))
                assert.is_falsy(body:find("work-token-abc", 1, true))
                req.sink("")
                req.sink(nil)
                return 1, 302, { location = "/bookmarks/77" }, "Found"
            end, function()
                local result, err = plugin:performWorkAction(work, "bookmark")
                assert.is_nil(err)
                assert.are.equal("77", result.bookmark_id)
            end)
            assert.are.equal(3, #calls)
            local state = plugin:workActionState(work)
            assert.is_true(state.bookmark.bookmarked)
            assert.are.equal("77", state.bookmark.id)
        end)

        it("refuses a second bookmark without another form post", function()
            signed_in()
            local calls = 0
            with_http(function(req)
                calls = calls + 1
                assert.are.equal("https://archiveofourown.org/works/123", req.url)
                req.sink(read_fixture("work_actions_existing.html"))
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local result, err = plugin:performWorkAction(work, "bookmark")
                assert.is_nil(result)
                assert.is_truthy(err:find("already bookmarked", 1, true))
            end)
            assert.are.equal(1, calls)
        end)

        it("removes the bookmark by id from the work page", function()
            signed_in()
            local calls = {}
            with_http(function(req)
                calls[#calls + 1] = req
                if req.url == "https://archiveofourown.org/works/123" then
                    req.sink(read_fixture("work_actions_existing.html"))
                    req.sink(nil)
                    return 1, 200, {}, "OK"
                end
                if req.url == Account.TOKEN_URL then return token_request(req) end
                assert.are.equal("https://archiveofourown.org/bookmarks/77", req.url)
                local body = read_source(req.source)
                assert.is_truthy(body:find("_method=delete", 1, true))
                req.sink("")
                req.sink(nil)
                return 1, 302, { location = "/users/testuser/bookmarks" }, "Found"
            end, function()
                local result, err = plugin:performWorkAction(work, "unbookmark")
                assert.is_nil(err)
                assert.is_true(result.done)
            end)
            assert.are.equal(3, #calls)
            assert.is_false(plugin:workActionState(work).bookmark.bookmarked)
        end)

        it("subscribes through the JSON endpoint and keeps the new id", function()
            signed_in()
            local calls = {}
            with_http(function(req)
                calls[#calls + 1] = req
                if req.url == Account.TOKEN_URL then return token_request(req) end
                assert.are.equal(
                    "https://archiveofourown.org/users/testuser/subscriptions.json",
                    req.url)
                local body = read_source(req.source)
                assert.is_truthy(body:find(
                    "subscription%5Bsubscribable_type%5D=Work", 1, true))
                req.sink('{"item_id":45,"item_success_message":"You are now following"}')
                req.sink(nil)
                return 1, 201, {}, "Created"
            end, function()
                local result, err = plugin:performWorkAction(work, "subscribe")
                assert.is_nil(err)
                assert.are.equal("45", result.subscription_id)
            end)
            assert.are.equal(2, #calls)
        end)

        it("treats an existing subscription as already done", function()
            signed_in()
            with_http(function(req)
                if req.url == Account.TOKEN_URL then return token_request(req) end
                req.sink('{"errors":["You are already subscribed to this work."]}')
                req.sink(nil)
                return 1, 422, {}, "Unprocessable Entity"
            end, function()
                local result, err = plugin:performWorkAction(work, "subscribe")
                assert.is_nil(err)
                assert.is_true(result.already)
                assert.is_truthy(result.message:find("already subscribed", 1, true))
            end)
        end)

        it("unsubscribes by the subscription id in the work page", function()
            signed_in()
            local calls = {}
            with_http(function(req)
                calls[#calls + 1] = req
                if req.url == "https://archiveofourown.org/works/123" then
                    req.sink(read_fixture("work_actions_existing.html"))
                    req.sink(nil)
                    return 1, 200, {}, "OK"
                end
                if req.url == Account.TOKEN_URL then return token_request(req) end
                assert.are.equal(
                    "https://archiveofourown.org/users/testuser/subscriptions/45.json",
                    req.url)
                local body = read_source(req.source)
                assert.is_truthy(body:find("_method=delete", 1, true))
                req.sink('{"item_success_message":"unsubscribed"}')
                req.sink(nil)
                return 1, 200, {}, "OK"
            end, function()
                local result, err = plugin:performWorkAction(work, "unsubscribe")
                assert.is_nil(err)
                assert.is_true(result.done)
            end)
            assert.are.equal(3, #calls)
            assert.is_false(plugin:workActionState(work).subscribe.subscribed)
        end)

        it("drops a rejected form token so the next tap refreshes it", function()
            signed_in()
            with_http(function(req)
                if req.url == Account.TOKEN_URL then return token_request(req) end
                req.sink("<h1>ActionController::InvalidAuthenticityToken</h1>")
                req.sink(nil)
                return 1, 422, {}, "Unprocessable Entity"
            end, function()
                local result, err = plugin:performWorkAction(work, "mark_for_later")
                assert.is_nil(result)
                assert.is_truthy(err:find("form token", 1, true))
                assert.is_nil(plugin.csrf_token)
            end)
        end)

        it("adds to Marked for Later with one PATCH-over-POST", function()
            signed_in()
            local calls = {}
            with_http(function(req)
                calls[#calls + 1] = req
                if req.url == Account.TOKEN_URL then return token_request(req) end
                assert.are.equal(
                    "https://archiveofourown.org/works/123/mark_for_later", req.url)
                local body = read_source(req.source)
                assert.is_truthy(body:find("_method=patch", 1, true))
                req.sink("")
                req.sink(nil)
                return 1, 302, { location = "/works/123" }, "Found"
            end, function()
                local result, err = plugin:performWorkAction(work, "mark_for_later")
                assert.is_nil(err)
                assert.is_true(result.done)
            end)
            assert.are.equal(2, #calls)
        end)

        it("reuses one token for several actions in the same session", function()
            signed_in()
            local token_calls, post_calls = 0, 0
            with_http(function(req)
                if req.url == Account.TOKEN_URL then
                    token_calls = token_calls + 1
                    return token_request(req)
                end
                post_calls = post_calls + 1
                req.sink("")
                req.sink(nil)
                return 1, 302, {}, "Found"
            end, function()
                assert.is_truthy(plugin:performWorkAction(work, "mark_for_later"))
                assert.is_truthy(plugin:performWorkAction(work, "mark_as_read"))
            end)
            assert.are.equal(1, token_calls)
            assert.are.equal(2, post_calls)
        end)

        it("does not touch the network when signed out", function()
            plugin.session = nil
            plugin.work_actions = nil
            local calls = 0
            with_http(function()
                calls = calls + 1
                error("must not request")
            end, function()
                local result, err = plugin:performWorkAction(work, "kudos")
                assert.is_nil(result)
                assert.is_truthy(err:find("Sign in", 1, true))
            end)
            assert.are.equal(0, calls)
        end)
    end)
end)
