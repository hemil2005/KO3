--[[--
Inline plugin updater for KOReader.

The plugin is distributed through GitHub Releases. A release carries:

    ao3.koplugin-<version>.zip   the plugin tree, rooted at ao3.koplugin/
    manifest.json                version, asset URL, SHA-256, notes

Checking is one small JSON GET from `releases/latest/download/manifest.json`
(no GitHub API token, no rate-limit surprises). Updating downloads the zip,
verifies its SHA-256, unpacks it next to the installed plugin, validates it,
and swaps directories. The running code stays untouched until KOReader
restarts, so a bad download can never leave a half-updated plugin in memory.

All filesystem work happens outside the live plugin directory:

    plugins/ao3.koplugin           the install
    plugins/ao3.koplugin.update    staging (removed on failure)
    plugins/ao3.koplugin.bak       previous install (for rollback)

KOReader only loads `*.koplugin` folders, so neither sibling is picked up.

Pure helpers (version parsing, manifest validation, zip entry planning) are
separated from the side effects so they can be tested offline.
]]

local DataStorage = require("datastorage")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local socketurl = require("socket.url")
local http = require("socket.http")
local JSON = require("json")
local ffiutil = require("ffi/util")
local _ = require("gettext")
local T = ffiutil.template

local Updater = {}

Updater.REPO = "hemil2005/KO3"
Updater.RELEASES_URL = "https://github.com/" .. Updater.REPO .. "/releases"
Updater.MANIFEST_URL = Updater.RELEASES_URL .. "/latest/download/manifest.json"
Updater.API_URL = "https://api.github.com/repos/" .. Updater.REPO .. "/releases/latest"
Updater.ARCHIVE_ROOT = "ao3.koplugin/"
Updater.UA = "KO3-updater/1.0 (+https://github.com/" .. Updater.REPO .. ")"

Updater.STAGING_SUFFIX = ".update"
Updater.BACKUP_SUFFIX = ".bak"

-- ---------------------------------------------------------------------------
-- Versions
-- ---------------------------------------------------------------------------

-- "v1.2.3", "1.2", "1.2.3-beta.1" -> {1,2,3}
function Updater.parseVersion(text)
    if type(text) ~= "string" then return nil end
    local major, minor, patch = text:match("^[vV]?(%d+)%.(%d+)%.?(%d*)")
    if not major then
        major, minor, patch = text:match("^[vV]?(%d+)$")
        minor, patch = "0", "0"
    end
    if not major then return nil end
    return {
        tonumber(major) or 0,
        tonumber(minor) or 0,
        tonumber(patch) or 0,
    }
end

-- True when `candidate` is a later version than `current`.
function Updater.isNewer(candidate, current)
    local a = Updater.parseVersion(candidate)
    local b = Updater.parseVersion(current)
    if not a then return false end
    if not b then return true end
    for i = 1, 3 do
        if a[i] ~= b[i] then
            return a[i] > b[i]
        end
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Manifest
-- ---------------------------------------------------------------------------

-- Validate the manifest before trusting any URL in it. `zip_url` may be
-- absolute or a bare asset name (resolved against the release page).
function Updater.parseManifest(body)
    if type(body) ~= "string" or body == "" then
        return nil, _("The update server returned an empty answer.")
    end
    local ok, data = pcall(JSON.decode, body)
    if not ok or type(data) ~= "table" then
        return nil, _("The update server sent a malformed manifest.")
    end
    if type(data.version) ~= "string" or not Updater.parseVersion(data.version) then
        return nil, _("The update manifest has no valid version.")
    end
    local zip_url = data.zip_url
    if type(zip_url) ~= "string" or zip_url == "" then
        -- Assets are versioned so a cached old manifest can never point at a
        -- replaced zip. Fall back to the conventional tag/asset names.
        local version = data.version:gsub("^[vV]", "")
        zip_url = Updater.RELEASES_URL .. "/download/v" .. version
            .. "/ao3.koplugin-" .. version .. ".zip"
    elseif not zip_url:match("^https?://") then
        local version = data.version:gsub("^[vV]", "")
        zip_url = Updater.RELEASES_URL .. "/download/v" .. version .. "/" .. zip_url
    end
    if not zip_url:match("^https://") then
        return nil, _("The update manifest points at a non-HTTPS download.")
    end
    if data.sha256 ~= nil and (type(data.sha256) ~= "string"
            or not data.sha256:match("^[0-9a-fA-F]+$")
            or #data.sha256 ~= 64) then
        return nil, _("The update manifest has an invalid checksum.")
    end
    return {
        version = data.version,
        zip_url = zip_url,
        sha256 = data.sha256 and data.sha256:lower() or nil,
        notes = type(data.notes) == "string" and data.notes or "",
        published_at = type(data.published_at) == "string" and data.published_at or nil,
    }
end

-- Map a GitHub API `releases/latest` response to the same manifest shape.
-- Used when the convenience asset URL is stale or missing in the CDN.
function Updater.manifestFromRelease(data)
    if type(data) ~= "table" or type(data.tag_name) ~= "string" then
        return nil, _("The update server sent a malformed release.")
    end
    local version = data.tag_name:gsub("^[vV]", "")
    if not Updater.parseVersion(version) then
        return nil, _("The release has no valid version tag.")
    end
    local asset
    for _, item in ipairs(data.assets or {}) do
        local name = item.name or ""
        if asset == nil and name:match("^ao3%.koplugin%-.*%.zip$") then
            asset = item
        end
    end
    if not asset then
        for _, item in ipairs(data.assets or {}) do
            if (item.name or ""):match("%.zip$") then
                asset = item
                break
            end
        end
    end
    if not asset or type(asset.browser_download_url) ~= "string" then
        return nil, _("The latest release has no plugin zip.")
    end
    local sha
    if type(asset.digest) == "string" then
        sha = asset.digest:match("^sha256:(%x+)$")
    end
    local notes = type(data.body) == "string" and data.body:gsub("%s+$", "") or ""
    if #notes > 500 then notes = notes:sub(1, 500) .. "…" end
    return {
        version = version,
        zip_url = asset.browser_download_url,
        sha256 = sha,
        notes = notes,
        published_at = type(data.published_at) == "string" and data.published_at or nil,
    }
end

-- ---------------------------------------------------------------------------
-- Zip entry planning (pure)
-- ---------------------------------------------------------------------------

-- Turn archive paths into relative install paths, rejecting anything that
-- could write outside the plugin directory.
function Updater.planEntries(entries, root)
    root = root or Updater.ARCHIVE_ROOT
    local plan, total = {}, 0
    for _, entry in ipairs(entries or {}) do
        local path = entry.path or ""
        if entry.mode == "file" and path:sub(1, #root) == root then
            local rel = path:sub(#root + 1)
            local bad = rel == ""
                or rel:sub(1, 1) == "/"
                or rel == ".."
                or rel:sub(1, 2) == ".."
                or rel:find("/../", 1, true) ~= nil
                or rel:sub(-3) == "/.."
            if not bad then
                plan[#plan + 1] = { path = path, rel = rel, size = entry.size or 0 }
                total = total + (entry.size or 0)
            end
        end
    end
    return plan, total
end

-- ---------------------------------------------------------------------------
-- Filesystem helpers
-- ---------------------------------------------------------------------------

local function removeTree(path)
    local mode = lfs.attributes(path, "mode")
    if not mode then return true end
    if mode ~= "directory" then
        return os.remove(path) ~= nil
    end
    local ok = true
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            if not removeTree(path .. "/" .. name) then ok = false end
        end
    end
    if ok then
        return lfs.rmdir(path) ~= nil
    end
    return false
end

Updater.removeTree = removeTree

local function ensureDir(path)
    if lfs.attributes(path, "mode") == "directory" then
        return true
    end
    local parent = path:match("^(.*)/[^/]*$")
    if parent and parent ~= "" and parent ~= path then
        ensureDir(parent)
    end
    lfs.mkdir(path)
    return lfs.attributes(path, "mode") == "directory"
end

local function readAll(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local body = f:read("*a")
    f:close()
    return body
end

Updater.readAll = readAll

local function fileExists(path)
    return lfs.attributes(path, "mode") == "file"
end

local function dirExists(path)
    return lfs.attributes(path, "mode") == "directory"
end

-- Version declared in a plugin's _meta.lua, without executing the file.
function Updater.versionFromMeta(plugin_dir)
    local body = readAll(plugin_dir .. "/_meta.lua") or ""
    local version = body:match('version%s*=%s*"([^"]+)"')
    return version
end

function Updater.currentVersion(plugin_dir)
    return Updater.versionFromMeta(plugin_dir) or "0.0.0"
end

function Updater.stagingDir(plugin_dir)
    return plugin_dir .. Updater.STAGING_SUFFIX
end

function Updater.backupDir(plugin_dir)
    return plugin_dir .. Updater.BACKUP_SUFFIX
end

-- GitHub serves release assets from a CDN host that some Kindle networks
-- cannot reach even though api.github.com works. The tag's source archive is
-- on codeload.github.com and contains the same ao3.koplugin tree.
function Updater.sourceUrl(version)
    local v = tostring(version or ""):gsub("^[vV]", "")
    if not Updater.parseVersion(v) then return nil end
    return "https://codeload.github.com/" .. Updater.REPO .. "/zip/refs/tags/v" .. v
end

-- The release zip roots entries at "ao3.koplugin/"; the source archive adds
-- the repository folder in front ("KO3-1.2.1/ao3.koplugin/").
function Updater.pluginRoot(entries)
    for _, entry in ipairs(entries or {}) do
        local path = entry.path or ""
        if path:sub(1, #Updater.ARCHIVE_ROOT) == Updater.ARCHIVE_ROOT then
            return Updater.ARCHIVE_ROOT
        end
        local root = path:match("^([^/]+/ao3%.koplugin/)")
        if root then return root end
    end
    return Updater.ARCHIVE_ROOT
end

-- ---------------------------------------------------------------------------
-- Network
-- ---------------------------------------------------------------------------

local function uaHeaders()
    return {
        ["User-Agent"] = Updater.UA,
        ["Accept"] = "application/json, application/zip, */*",
    }
end

local MAX_REDIRECTS = 5
local REDIRECT_CODES = {
    [301] = true, [302] = true, [303] = true, [307] = true, [308] = true,
}

-- GET with manual redirects. LuaSocket's automatic redirect reuses the
-- original request for the new host; on the Kindle's LuaSec it can sit on the
-- redirect to GitHub's asset CDN until the socket times out, even though the
-- API request that produced the changelog went through. Rebuilding each hop
-- keeps the request (and a resume Range) valid for the host that answers.
local function get(url, sink, timeout, headers, on_redirect)
    local current = url
    local hops = 0
    local block, total = socketutil:set_timeout(timeout or 20, (timeout or 20) * 3)
    while true do
        local ok, code, response_headers, status = pcall(function()
            return socket.skip(1, http.request{
                url = current,
                method = "GET",
                headers = headers or uaHeaders(),
                sink = sink,
                redirect = false,
            })
        end)
        if not ok or type(code) ~= "number" then
            socketutil:reset_timeout()
            return nil, "network", tostring(code or status), block, total
        end
        local location = response_headers and response_headers["location"]
        if REDIRECT_CODES[code] and location then
            hops = hops + 1
            if hops > MAX_REDIRECTS then
                socketutil:reset_timeout()
                return nil, "redirect", _("The update server redirected too many times.")
            end
            local next_url = socketurl.absolute(current, location)
            if not next_url
                    or (current:match("^https:") and next_url:match("^http:")) then
                socketutil:reset_timeout()
                return nil, "redirect", _("The update server redirected to an unsafe address.")
            end
            if on_redirect then on_redirect() end
            current = next_url
        else
            socketutil:reset_timeout()
            return code
        end
    end
end

local function getJson(url, timeout)
    local chunks = {}
    local code, err = get(url, ltn12.sink.table(chunks), timeout, nil, function()
        for i = #chunks, 1, -1 do chunks[i] = nil end
    end)
    if not code then
        return nil, err
    end
    if code ~= 200 then
        return nil, T(_("The update server answered HTTP %1."), tostring(code))
    end
    return table.concat(chunks)
end

-- Read the published manifest. The GitHub API is authoritative and not
-- affected by the release-asset CDN, which can serve a stale manifest for
-- minutes after a release. The asset URL is the fallback (it costs no API
-- quota). Anonymous API use is one small request per check.
function Updater.fetchManifest(timeout)
    local api_body, api_err = getJson(Updater.API_URL, timeout)
    local parse_err
    if api_body then
        local ok, data = pcall(JSON.decode, api_body)
        if ok then
            local manifest, api_parse_err = Updater.manifestFromRelease(data)
            if manifest then return manifest end
            parse_err = api_parse_err
        end
    end

    local body, fetch_err = getJson(Updater.MANIFEST_URL, timeout)
    if body then
        local manifest, asset_parse_err = Updater.parseManifest(body)
        if manifest then return manifest end
        parse_err = asset_parse_err or parse_err
    end
    return nil, parse_err or api_err or fetch_err
end

-- Download an asset to `dest`. Verifies SHA-256 when the manifest has one.
-- The caller owns `dest` on success; it is removed on failure.
--
-- A stalled connection is retried, resuming from the bytes already on disk
-- with an HTTP Range request. Kindle Wi-Fi drops long transfers often enough
-- that starting a 2.7 MB zip over from zero would usually fail again.
Updater.DOWNLOAD_ATTEMPTS = 3

local function downloadOnce(url, dest, offset, timeout)
    local file, err = io.open(dest, offset > 0 and "r+b" or "wb")
    if not file then
        return nil, "write", err
    end
    if offset > 0 then
        file:seek("set", offset)
    end

    -- A redirect body is written at the current position, so drop it by
    -- restoring the file to `offset` (the resume point) before the next hop.
    -- ltn12.sink.file cannot be used here: it closes the handle at the end of
    -- each response, and the next hop would write to a closed file.
    local function truncate_to(n)
        file:close()
        if n == 0 then
            file = assert(io.open(dest, "wb"))
        else
            local src = assert(io.open(dest, "rb"))
            local keep = src:read(n)
            src:close()
            local out = assert(io.open(dest, "wb"))
            out:write(keep)
            out:close()
            file = assert(io.open(dest, "r+b"))
        end
        file:seek("set", n)
    end

    local current = url
    local hops = 0
    while true do
        local headers = uaHeaders()
        if offset > 0 then
            headers["Range"] = "bytes=" .. offset .. "-"
        end
        socketutil:set_timeout(timeout or 20, (timeout or 20) * 3)
        local ok, code, response_headers, status = pcall(function()
            return socket.skip(1, http.request{
                url = current,
                method = "GET",
                headers = headers,
                sink = function(chunk)
                    if chunk then
                        return file:write(chunk) and 1 or nil
                    end
                    return 1
                end,
                redirect = false,
            })
        end)
        socketutil:reset_timeout()

        if not ok or type(code) ~= "number" then
            file:close()
            return nil, "network", tostring(code or status)
        end

        local location = response_headers and response_headers["location"]
        if REDIRECT_CODES[code] and location then
            hops = hops + 1
            if hops > MAX_REDIRECTS then
                file:close()
                return nil, "redirect", _("The update server redirected too many times.")
            end
            local next_url = socketurl.absolute(current, location)
            if not next_url
                    or (current:match("^https:") and next_url:match("^http:")) then
                file:close()
                return nil, "redirect", _("The update server redirected to an unsafe address.")
            end
            truncate_to(offset)
            current = next_url
        else
            file:close()
            if offset > 0 and code == 200 then
                -- The server ignored Range and sent the whole file, so the
                -- appended copy is corrupt. Start over from zero.
                return nil, "restart", "range ignored"
            end
            if code ~= 200 and code ~= 206 then
                return nil, "http", code
            end
            return true
        end
    end
end

function Updater.download(manifest, dest, timeout)
    local last_err
    for attempt = 1, Updater.DOWNLOAD_ATTEMPTS do
        local offset = lfs.attributes(dest, "size") or 0
        local ok, kind, detail, block, total = downloadOnce(
            manifest.zip_url, dest, offset, timeout)
        if ok then
            break
        end
        if kind == "write" then
            os.remove(dest)
            return nil, T(_("Cannot write %1: %2"), dest, tostring(detail)), "write"
        end
        if kind == "http" then
            os.remove(dest)
            return nil, T(_("Download failed (HTTP %1)."), tostring(detail)), "http"
        end
        if kind == "redirect" then
            os.remove(dest)
            return nil, detail, "redirect"
        end
        if kind == "restart" then
            os.remove(dest)
            last_err = _("The update server restarted the download.")
        else
            last_err = socketutil.describe_error(detail, block, total)
                or T(_("Download failed (%1)."), tostring(detail))
        end
        if attempt == Updater.DOWNLOAD_ATTEMPTS then
            os.remove(dest)
            return nil, last_err, kind
        end
    end

    if manifest.sha256 then
        local has_sha2, sha2 = pcall(require, "ffi/sha2")
        if not has_sha2 or not sha2 then
            os.remove(dest)
            return nil, _("This KOReader build cannot verify downloads. Install this update from the release zip instead."), "verify"
        end
        local data = readAll(dest)
        if not data then
            os.remove(dest)
            return nil, T(_("Could not read the downloaded file.")), "read"
        end
        local actual = sha2.sha256(data)
        if actual:lower() ~= manifest.sha256 then
            os.remove(dest)
            return nil, _("The downloaded update failed its checksum and was discarded."), "checksum"
        end
    end
    return true
end

-- ---------------------------------------------------------------------------
-- Install
-- ---------------------------------------------------------------------------

local function listZip(zip_path)
    local has_archiver, Archiver = pcall(require, "ffi/archiver")
    if not has_archiver or not Archiver then
        return nil, _("This KOReader build cannot unpack updates. Install this update from the release zip instead.")
    end
    local reader = Archiver.Reader:new()
    if not reader:open(zip_path) then
        return nil, reader.err or _("The update archive could not be opened.")
    end
    local entries = {}
    for entry in reader:iterate() do
        entries[#entries + 1] = {
            path = entry.path,
            mode = entry.mode,
            size = entry.size,
        }
    end
    return { reader = reader, entries = entries }
end

-- Options (all optional, for tests):
--   extract(zip, plan, staging) -> ok, err   replaces the real extractor
--   rename(old, new) -> ok, err              replaces os.rename
function Updater.install(plugin_dir, zip_path, manifest, options)
    options = options or {}
    local staging = Updater.stagingDir(plugin_dir)
    local backup = Updater.backupDir(plugin_dir)
    manifest = manifest or {}

    removeTree(staging)
    local archive, list_err
    if options.entries then
        archive = { entries = options.entries }
    else
        archive, list_err = listZip(zip_path)
    end
    if not archive then
        return nil, list_err
    end
    local root = options.root or Updater.pluginRoot(archive.entries)
    local plan = Updater.planEntries(archive.entries, root)
    if #plan == 0 then
        return nil, _("The update archive does not contain the plugin.")
    end

    local extract = options.extract
    if not extract then
        local reader = archive.reader
        extract = function(_, entries, dest_dir)
            for _, item in ipairs(entries) do
                local dest = dest_dir .. "/" .. item.rel
                ensureDir(dest:match("^(.*)/[^/]*$") or dest_dir)
                local ok, err = reader:extractToPath(item.path, dest)
                if not ok then
                    return nil, err or T(_("Could not extract %1."), item.rel)
                end
            end
            return true
        end
    end

    ensureDir(staging)
    local ok, err = extract(zip_path, plan, staging)
    if not ok then
        removeTree(staging)
        return nil, err or _("The update archive could not be extracted.")
    end

    if not fileExists(staging .. "/main.lua") or not fileExists(staging .. "/_meta.lua") then
        removeTree(staging)
        return nil, _("The update archive is incomplete; the installed copy was left alone.")
    end
    local staged_version = Updater.versionFromMeta(staging)
    if manifest.version and staged_version
            and Updater.parseVersion(staged_version)
            and not (staged_version == manifest.version) then
        removeTree(staging)
        return nil, T(_("The update archive is version %1, but the manifest says %2."),
            staged_version, manifest.version)
    end

    local rename = options.rename or os.rename
    removeTree(backup)
    local moved_away, move_err = rename(plugin_dir, backup)
    if not moved_away then
        removeTree(staging)
        return nil, T(_("Could not move the old copy aside: %1"), tostring(move_err))
    end
    local installed, install_err = rename(staging, plugin_dir)
    if not installed then
        rename(backup, plugin_dir)
        removeTree(staging)
        return nil, T(_("Could not install the update: %1"), tostring(install_err))
    end
    return true, backup
end

-- Swap the previous copy back. Used when a new version misbehaves.
function Updater.rollback(plugin_dir, options)
    options = options or {}
    local backup = Updater.backupDir(plugin_dir)
    if not dirExists(backup) then
        return nil, _("There is no previous version to restore.")
    end
    local failed = plugin_dir .. ".failed"
    local rename = options.rename or os.rename
    removeTree(failed)
    if dirExists(plugin_dir) then
        if not rename(plugin_dir, failed) then
            return nil, _("Could not move the current copy aside.")
        end
    end
    if not rename(backup, plugin_dir) then
        if dirExists(failed) then rename(failed, plugin_dir) end
        return nil, _("Could not restore the previous copy.")
    end
    removeTree(failed)
    return true
end

-- Where downloads are kept. The plugin already has an `ao3` data folder.
function Updater.downloadPath(version)
    local dir = DataStorage:getDataDir() .. "/ao3/updates"
    ensureDir(dir)
    local safe = tostring(version or "latest"):gsub("[^%w%._-]", "_")
    return dir .. "/ao3.koplugin-" .. safe .. ".zip"
end

-- Download + verify + install in one call. Returns ok, backup_dir or nil, err.
function Updater.update(plugin_dir, manifest, options)
    options = options or {}
    local zip_path = options.zip_path or Updater.downloadPath(manifest.version)
    local ok, err, kind = Updater.download(manifest, zip_path, options.timeout)
    if not ok and kind ~= "checksum" and kind ~= "write"
            and kind ~= "verify" and kind ~= "read" then
        -- The release asset lives on GitHub's asset CDN, which some Kindle
        -- networks cannot reach even when the API request for the changelog
        -- works. The tag's source archive is on codeload.github.com and
        -- carries the same plugin tree; it has no manifest checksum, so the
        -- staged _meta.lua version is the version check.
        local source = Updater.sourceUrl(manifest.version)
        if source and source ~= manifest.zip_url then
            local fallback_ok, fallback_err = Updater.download(
                { zip_url = source }, zip_path, options.timeout)
            if fallback_ok then
                ok, err = true, nil
            else
                err = fallback_err or err
            end
        end
    end
    if not ok then
        return nil, err
    end
    local installed, backup_or_err = Updater.install(plugin_dir, zip_path, manifest, options)
    os.remove(zip_path)
    if not installed then
        return nil, backup_or_err
    end
    return true, backup_or_err
end

return Updater
