-- Offline tests for bug reports and the diagnostic log.

require("commonrequire")

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local http = require("socket.http")
local BugReport = dofile("plugins/ao3.koplugin/bugreport.lua")

local tmp_root
local old_full_data_dir
local old_settings_dir

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

setup(function()
    tmp_root = os.tmpname()
    os.remove(tmp_root)
    assert(lfs.mkdir(tmp_root))
    old_full_data_dir = DataStorage.getFullDataDir
    old_settings_dir = DataStorage.getSettingsDir
    DataStorage.getFullDataDir = function() return tmp_root end
    DataStorage.getSettingsDir = function() return tmp_root .. "/settings" end
end)

teardown(function()
    DataStorage.getFullDataDir = old_full_data_dir
    DataStorage.getSettingsDir = old_settings_dir
    remove_tree(tmp_root)
end)

describe("AO3 bug report log", function()
    it("strips query strings and fragments before logging a URL", function()
        assert.are.equal(
            "https://archiveofourown.org/tags/Harry%20Potter/works",
            BugReport.sanitizeUrl(
                "https://archiveofourown.org/tags/Harry%20Potter/works?page=2&q=secret#comments"))
        assert.are.equal("", BugReport.sanitizeUrl(nil))
    end)

    it("records lines and returns the newest ones", function()
        BugReport.log("session", "first")
        BugReport.log("http", "second")
        local body = BugReport.readLog()
        assert.is_truthy(body:find("first", 1, true))
        assert.is_truthy(body:find("second", 1, true))
        local tail, count = BugReport.tail(1)
        assert.are.equal(1, count)
        assert.is_truthy(tail:find("second", 1, true))
        assert.is_nil(tail:find("first", 1, true))
    end)

    it("reports the environment without user content", function()
        local env = table.concat(BugReport.environment(), "\n")
        assert.is_truthy(env:find("Plugin: KO3", 1, true))
        assert.is_truthy(env:find("KOReader:", 1, true))
        assert.is_truthy(env:find("Device:", 1, true))
        assert.is_truthy(env:find("Screen:", 1, true))
    end)
end)

describe("AO3 bug report contents", function()
    it("uses the first line as the issue title", function()
        assert.are.equal("It crashes", BugReport.title("It crashes\nwhen opening"))
        assert.are.equal("Bug report", BugReport.title("  \n"))
        assert.are.equal(80, #BugReport.title(string.rep("a", 120)))
    end)

    it("only includes the log when it was consented to", function()
        local without = BugReport.build("Something broke", false)
        assert.is_truthy(without:find("No diagnostic log was attached.", 1, true))
        assert.is_nil(without:find("```text", 1, true))

        BugReport.log("error", "sample diagnostic line")
        local with = BugReport.build("Something broke", true)
        assert.is_truthy(with:find("## Log", 1, true))
        assert.is_truthy(with:find("sample diagnostic line", 1, true))
        assert.is_truthy(with:find("Something broke", 1, true))
    end)

    it("saves report.md and log.txt in a timestamped folder", function()
        local dir, report_path, log_path = BugReport.save("It fails on read", true)
        assert.is_truthy(dir)
        assert.are.equal("file", lfs.attributes(report_path, "mode"))
        assert.are.equal("file", lfs.attributes(log_path, "mode"))
        local file = assert(io.open(report_path, "rb"))
        local report = file:read("*a")
        file:close()
        assert.is_truthy(report:find("It fails on read", 1, true))
        local log_file = assert(io.open(log_path, "rb"))
        local log = log_file:read("*a")
        log_file:close()
        assert.is_truthy(log:find("sample diagnostic line", 1, true))
    end)

    it("omits log.txt when the log is not attached", function()
        local dir, _, log_path = BugReport.save("No log please", false)
        assert.is_truthy(dir)
        assert.is_nil(log_path)
        assert.are.equal("file", lfs.attributes(dir .. "/report.md", "mode"))
        assert.is_nil(lfs.attributes(dir .. "/log.txt", "mode"))
    end)
end)

describe("AO3 bug report delivery", function()
    it("encodes the issue URL title", function()
        local url = BugReport.issueUrl("It crashes & stops")
        assert.is_truthy(url:find("issues/new?title=", 1, true))
        assert.is_nil(url:find(" ", 1, true))
    end)

    it("refuses to submit without a token", function()
        local url, err = BugReport.submit(nil, "title", "body")
        assert.is_nil(url)
        assert.is_truthy(err:find("token", 1, true))
        assert.is_nil(BugReport.token())
    end)

    it("reads a token file and rejects an empty one", function()
        lfs.mkdir(tmp_root .. "/settings")
        local path = tmp_root .. "/settings/ao3_report_token"
        local f = assert(io.open(path, "wb"))
        f:write("  ghp_example\n")
        f:close()
        assert.are.equal("ghp_example", BugReport.token())
        local empty = assert(io.open(path, "wb"))
        empty:write("\n")
        empty:close()
        assert.is_nil(BugReport.token())
    end)

    it("posts a report through the relay", function()
        local old_request = http.request
        local old_url = BugReport.RELAY_URL
        BugReport.RELAY_URL = "https://relay.test/report"
        local seen
        http.request = function(request)
            seen = request
            request.sink('{"url":"https://github.com/hemil2005/KO3/issues/7"}')
            return 1, 200, {}, "HTTP/1.1 200 OK"
        end
        local url, err = BugReport.submitRelay("A title", "A body")
        http.request = old_request
        BugReport.RELAY_URL = old_url
        assert.is_truthy(url, err)
        assert.are.equal("https://github.com/hemil2005/KO3/issues/7", url)
        assert.are.equal("POST", seen.method)
        assert.are.equal("https://relay.test/report", seen.url)
        assert.are.equal("application/json", seen.headers["Content-Type"])
    end)

    it("reports relay limits and missing configuration", function()
        local old_request = http.request
        local old_url = BugReport.RELAY_URL
        http.request = function(request)
            request.sink('{"error":"too many reports"}')
            return 1, 429, {}, "HTTP/1.1 429 Too Many Requests"
        end
        BugReport.RELAY_URL = "https://relay.test/report"
        local url, err = BugReport.submitRelay("T", "B")
        assert.is_nil(url)
        assert.is_truthy(err:find("Too many reports", 1, true))

        BugReport.RELAY_URL = nil
        url, err = BugReport.submitRelay("T", "B")
        assert.is_nil(url)
        assert.is_truthy(err:find("relay", 1, true))

        http.request = old_request
        BugReport.RELAY_URL = old_url
    end)

    it("delivers through the relay when no token is configured", function()
        os.remove(tmp_root .. "/settings/ao3_report_token")
        local old_request = http.request
        local old_url = BugReport.RELAY_URL
        BugReport.RELAY_URL = "https://relay.test/report"
        http.request = function(request)
            request.sink('{"url":"https://github.com/hemil2005/KO3/issues/8"}')
            return 1, 200, {}, "HTTP/1.1 200 OK"
        end
        local url, err = BugReport.deliver("T", "B")
        http.request = old_request
        BugReport.RELAY_URL = old_url
        assert.is_truthy(url, err)
        assert.are.equal("https://github.com/hemil2005/KO3/issues/8", url)
    end)
end)
