--[[--
Inline plugin updater for KOReader.

The plugin is distributed through GitHub Releases. A release carries:

    ao3.koplugin.zip     the plugin tree, rooted at ao3.koplugin/
    manifest.json        version, asset URL, SHA-256, notes

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
local http = require("socket.http")
local JSON = require("json")
local ffiutil = require("ffi/util")
local _ = require("gettext")
local T = ffiutil.template

local Updater = {}

Updater.REPO = "hemil2005/KO3"
Updater.RELEASES_URL = "https://github.com/" .. Updater.REPO .. "/releases"
Updater.MANIFEST_URL = Updater.RELEASES_URL .. "/latest/download/manifest.json"
Updater.ZIP_NAME = "ao3.koplugin.zip"
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
        zip_url = Updater.RELEASES_URL .. "/latest/download/" .. Updater.ZIP_NAME
    elseif not zip_url:match("^https?://") then
        zip_url = Updater.RELEASES_URL .. "/latest/download/" .. zip_url
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

-- ---------------------------------------------------------------------------
-- Network
-- ---------------------------------------------------------------------------

local function uaHeaders()
    return {
        ["User-Agent"] = Updater.UA,
        ["Accept"] = "application/json, application/zip, */*",
    }
end

-- GET a small text resource. Returns body or nil, error.
function Updater.fetchManifest(timeout)
    local chunks = {}
    socketutil:set_timeout(timeout or 20, (timeout or 20) * 2)
    local ok, code, status = pcall(function()
        return socket.skip(1, http.request{
            url = Updater.MANIFEST_URL,
            method = "GET",
            headers = uaHeaders(),
            sink = ltn12.sink.table(chunks),
            redirect = true,
        })
    end)
    socketutil:reset_timeout()
    if not ok then
        return nil, tostring(code)
    end
    if code ~= 200 then
        return nil, T(_("The update server answered HTTP %1."), tostring(code or status))
    end
    return Updater.parseManifest(table.concat(chunks))
end

-- Download an asset to `dest`. Verifies SHA-256 when the manifest has one.
-- The caller owns `dest` on success; it is removed on failure.
function Updater.download(manifest, dest, timeout)
    local file, err = io.open(dest, "wb")
    if not file then
        return nil, T(_("Cannot write %1: %2"), dest, tostring(err))
    end
    socketutil:set_timeout(timeout or 120, (timeout or 120) * 3)
    local ok, code, status = pcall(function()
        return socket.skip(1, http.request{
            url = manifest.zip_url,
            method = "GET",
            headers = uaHeaders(),
            sink = ltn12.sink.file(file),
            redirect = true,
        })
    end)
    socketutil:reset_timeout()
    if not ok or code ~= 200 then
        pcall(function() file:close() end)
        os.remove(dest)
        return nil, T(_("Download failed (HTTP %1)."), tostring(code or status or "network error"))
    end
    pcall(function() file:close() end)

    if manifest.sha256 then
        local has_sha2, sha2 = pcall(require, "ffi/sha2")
        if not has_sha2 or not sha2 then
            os.remove(dest)
            return nil, _("This KOReader build cannot verify downloads. Install this update from the release zip instead.")
        end
        local data = readAll(dest)
        if not data then
            os.remove(dest)
            return nil, T(_("Could not read the downloaded file."))
        end
        local actual = sha2.sha256(data)
        if actual:lower() ~= manifest.sha256 then
            os.remove(dest)
            return nil, _("The downloaded update failed its checksum and was discarded.")
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
    local plan = Updater.planEntries(archive.entries)
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
    local ok, err = Updater.download(manifest, zip_path, options.timeout)
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
