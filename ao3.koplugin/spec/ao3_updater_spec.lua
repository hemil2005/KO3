-- Offline tests for the inline updater.
--
-- No network and no real archives: a fake extractor and a stubbed HTTP
-- request exercise the same code paths the plugin uses on a device.

require("commonrequire")

local http = require("socket.http")
local lfs = require("libs/libkoreader-lfs")
local Updater = dofile("plugins/ao3.koplugin/updater.lua")

local tmp_root

local function mkdirp(path)
    local current = path:sub(1, 1) == "/" and "" or nil
    for part in path:gmatch("[^/]+") do
        if current then
            current = current .. "/" .. part
        else
            current = part
        end
        lfs.mkdir(current)
    end
end

local function write_file(path, body)
    local f = assert(io.open(path, "wb"))
    f:write(body)
    f:close()
end

local function make_install(dir, version)
    mkdirp(dir .. "/data/fandoms")
    write_file(dir .. "/main.lua", "-- main " .. version .. "\n")
    write_file(dir .. "/_meta.lua", 'return { version = "' .. version .. '" }\n')
    write_file(dir .. "/data/fandoms/index.lua", "return {}\n")
    return dir
end

local function entry(path, mode, size)
    return { path = path, mode = mode or "file", size = size or 1 }
end

-- Writes the planned entries, as the real extractor would.
local function fake_extract(contents)
    return function(_, plan, staging)
        for _, item in ipairs(plan) do
            local body = contents[item.rel] or ("-- " .. item.rel .. "\n")
            mkdirp(staging .. "/" .. (item.rel:match("^(.*)/") or ""))
            write_file(staging .. "/" .. item.rel, body)
        end
        return true
    end
end

setup(function()
    tmp_root = os.tmpname()
    os.remove(tmp_root)
    assert(lfs.mkdir(tmp_root))
end)

teardown(function()
    Updater.removeTree(tmp_root)
end)

describe("AO3 updater versions", function()
    it("parses tags with or without a leading v", function()
        assert.are.same({ 1, 2, 3 }, Updater.parseVersion("v1.2.3"))
        assert.are.same({ 1, 2, 0 }, Updater.parseVersion("1.2"))
        assert.are.same({ 2, 0, 0 }, Updater.parseVersion("2"))
        assert.are.same({ 1, 2, 3 }, Updater.parseVersion("v1.2.3-beta.1"))
        assert.is_nil(Updater.parseVersion("nightly"))
        assert.is_nil(Updater.parseVersion(nil))
    end)

    it("only reports a genuinely later version", function()
        assert.is_true(Updater.isNewer("1.0.1", "1.0.0"))
        assert.is_true(Updater.isNewer("v2.0.0", "1.9.9"))
        assert.is_false(Updater.isNewer("1.0.0", "1.0.0"))
        assert.is_false(Updater.isNewer("0.9", "1.0.0"))
        -- An unreadable installed version must not block a real update.
        assert.is_true(Updater.isNewer("1.0.0", "not-a-version"))
    end)

    it("reads the version from _meta.lua without running it", function()
        local dir = tmp_root .. "/meta"
        mkdirp(dir)
        write_file(dir .. "/_meta.lua", 'return { fullname = "x", version = "4.5.6" }\n')
        assert.are.equal("4.5.6", Updater.versionFromMeta(dir))
        assert.are.equal("4.5.6", Updater.currentVersion(dir))
        assert.are.equal("0.0.0", Updater.currentVersion(tmp_root .. "/missing"))
    end)
end)

describe("AO3 updater manifest", function()
    local sha = string.rep("a", 64)

    it("accepts a complete manifest", function()
        local manifest = assert(Updater.parseManifest(
            '{"version":"1.2.0","zip_url":"https://example.test/ao3.zip",'
            .. '"sha256":"' .. sha .. '","notes":"N"}'))
        assert.are.equal("1.2.0", manifest.version)
        assert.are.equal("https://example.test/ao3.zip", manifest.zip_url)
        assert.are.equal(sha, manifest.sha256)
        assert.are.equal("N", manifest.notes)
    end)

    it("defaults a missing asset to the versioned tag asset", function()
        local manifest = assert(Updater.parseManifest('{"version":"1.0.0"}'))
        assert.are.equal(
            "https://github.com/hemil2005/KO3/releases/download/v1.0.0/ao3.koplugin-1.0.0.zip",
            manifest.zip_url)
    end)

    it("rejects insecure, malformed and untrustworthy manifests", function()
        assert.is_nil(Updater.parseManifest(""))
        assert.is_nil(Updater.parseManifest("not json"))
        assert.is_nil(Updater.parseManifest('{"zip_url":"https://x/y.zip"}'))
        assert.is_nil(Updater.parseManifest(
            '{"version":"1.0.0","zip_url":"http://x/y.zip"}'))
        assert.is_nil(Updater.parseManifest(
            '{"version":"1.0.0","sha256":"abc"}'))
        assert.is_nil(Updater.parseManifest(
            '{"version":"soon","zip_url":"https://x/y.zip"}'))
    end)
end)

describe("AO3 updater archive planning", function()
    it("strips the plugin root and keeps only regular files under it", function()
        local plan, total = Updater.planEntries({
            entry("ao3.koplugin/main.lua"),
            entry("ao3.koplugin/data/fandoms/index.lua", "file", 10),
            entry("ao3.koplugin/data/", "directory", 0),
            entry("ao3.koplugin/link.lua", "link", 0),
            entry("other/main.lua"),
        })
        assert.are.equal(2, #plan)
        assert.are.equal("main.lua", plan[1].rel)
        assert.are.equal("data/fandoms/index.lua", plan[2].rel)
        assert.are.equal(11, total)
    end)

    it("refuses path traversal and absolute paths", function()
        local plan = Updater.planEntries({
            entry("ao3.koplugin/../evil.lua"),
            entry("ao3.koplugin/sub/../../evil.lua"),
            entry("ao3.koplugin//abs.lua"),
            entry("ao3.koplugin/ok.lua"),
        })
        assert.are.equal(1, #plan)
        assert.are.equal("ok.lua", plan[1].rel)
    end)
end)

describe("AO3 updater install", function()
    local entries = {
        entry("ao3.koplugin/main.lua", "file", 4),
        entry("ao3.koplugin/_meta.lua", "file", 4),
    }

    it("swaps in a validated tree and keeps the previous one", function()
        local plugin_dir = make_install(tmp_root .. "/good/ao3.koplugin", "1.0.0")
        local ok, backup = Updater.install(plugin_dir, "unused.zip",
            { version = "2.0.0" }, {
                entries = entries,
                extract = fake_extract({
                    ["_meta.lua"] = 'return { version = "2.0.0" }\n',
                }),
            })
        assert.is_true(ok)
        assert.are.equal(Updater.backupDir(plugin_dir), backup)
        assert.are.equal("2.0.0", Updater.currentVersion(plugin_dir))
        assert.are.equal("1.0.0", Updater.currentVersion(backup))
    end)

    it("rejects an archive whose version disagrees with the manifest", function()
        local plugin_dir = make_install(tmp_root .. "/mismatch/ao3.koplugin", "1.0.0")
        local ok, err = Updater.install(plugin_dir, "unused.zip",
            { version = "3.0.0" }, {
                entries = entries,
                extract = fake_extract({
                    ["_meta.lua"] = 'return { version = "2.5.0" }\n',
                }),
            })
        assert.is_nil(ok)
        assert.is_truthy(err:find("2.5.0", 1, true))
        assert.are.equal("1.0.0", Updater.currentVersion(plugin_dir))
        assert.is_nil(lfs.attributes(Updater.stagingDir(plugin_dir), "mode"))
    end)

    it("leaves the install alone when the archive is incomplete", function()
        local plugin_dir = make_install(tmp_root .. "/partial/ao3.koplugin", "1.0.0")
        local ok = Updater.install(plugin_dir, "unused.zip",
            { version = "2.0.0" }, {
                entries = {
                    entry("ao3.koplugin/_meta.lua", "file", 4),
                },
                extract = fake_extract({
                    ["_meta.lua"] = 'return { version = "2.0.0" }\n',
                }),
            })
        assert.is_nil(ok)
        assert.are.equal("1.0.0", Updater.currentVersion(plugin_dir))
    end)

    it("restores the old copy when the final rename fails", function()
        local plugin_dir = make_install(tmp_root .. "/rename/ao3.koplugin", "1.0.0")
        local calls = 0
        local ok, err = Updater.install(plugin_dir, "unused.zip",
            { version = "2.0.0" }, {
                entries = entries,
                extract = fake_extract({
                    ["_meta.lua"] = 'return { version = "2.0.0" }\n',
                }),
                rename = function(old, new)
                    calls = calls + 1
                    if calls == 2 then
                        return nil, "simulated failure"
                    end
                    return os.rename(old, new)
                end,
            })
        assert.is_nil(ok)
        assert.is_truthy(err:find("simulated failure", 1, true))
        assert.are.equal("1.0.0", Updater.currentVersion(plugin_dir))
        assert.is_nil(lfs.attributes(Updater.backupDir(plugin_dir), "mode"))
    end)

    it("rolls back to the previous tree", function()
        local plugin_dir = make_install(tmp_root .. "/rollback/ao3.koplugin", "1.0.0")
        assert.is_true(Updater.install(plugin_dir, "unused.zip",
            { version = "2.0.0" }, {
                entries = entries,
                extract = fake_extract({
                    ["_meta.lua"] = 'return { version = "2.0.0" }\n',
                }),
            }))
        assert.are.equal("2.0.0", Updater.currentVersion(plugin_dir))
        assert.is_true(Updater.rollback(plugin_dir))
        assert.are.equal("1.0.0", Updater.currentVersion(plugin_dir))
        assert.is_nil(lfs.attributes(Updater.backupDir(plugin_dir), "mode"))
    end)
end)

describe("AO3 updater download", function()
    local old_request

    before_each(function()
        old_request = http.request
    end)

    after_each(function()
        http.request = old_request
    end)

    it("discards a download whose checksum does not match", function()
        http.request = function(request)
            request.sink("payload")
            return 1, 200, {}, "HTTP/1.1 200 OK"
        end
        local dest = tmp_root .. "/bad.zip"
        local ok, err = Updater.download(
            { zip_url = "https://example.test/x.zip", sha256 = string.rep("0", 64) },
            dest)
        assert.is_nil(ok)
        assert.is_truthy(err:find("checksum", 1, true))
        assert.is_nil(lfs.attributes(dest, "mode"))
    end)

    it("keeps a download that matches its checksum", function()
        local sha2 = require("ffi/sha2")
        http.request = function(request)
            request.sink("payload")
            return 1, 200, {}, "HTTP/1.1 200 OK"
        end
        local dest = tmp_root .. "/good.zip"
        local ok = Updater.download(
            { zip_url = "https://example.test/x.zip", sha256 = sha2.sha256("payload") },
            dest)
        assert.is_true(ok)
        assert.are.equal("payload", Updater.readAll(dest))
    end)
end)
