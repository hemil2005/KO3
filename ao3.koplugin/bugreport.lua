--[[--
Bug reports with an optional diagnostic log.

A report is built on the device so the user can read exactly what would be
sent. The log is only included after an explicit consent dialog that states
what it is for (finding the cause of the issue).

What the log contains: session start (plugin/KOReader/device), the cleaned
URL path and HTTP status of each request, download outcomes and error text.
What it never contains: cookies, passwords, search queries, work titles or
work text. Query strings and fragments are stripped before logging.

Delivery:

  * With a token file (`settings/ao3_report_token`, a fine-grained GitHub
    token with Issues: write), the report is filed directly through the API
    and the log is embedded in the issue body.
  * Without one, the report is saved under `ao3/reports/` as `report.md`
    plus `log.txt`, ready to attach to a new issue. This is the only
    credential-free option: GitHub does not allow anonymous issue creation.
]]

local DataStorage = require("datastorage")
local Device = require("device")
local Version = require("version")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local socket = require("socket")
local socketutil = require("socketutil")
local http = require("socket.http")
local JSON = require("json")
local _ = require("gettext")
local T = require("ffi/util").template

local BugReport = {}

local MODULE_DIR = debug.getinfo(1, "S").source:sub(2):gsub("[/\\][^/\\]*$", "")
local MAX_LOG_BYTES = 256 * 1024
local MAX_LINE_CHARS = 500
local TAIL_LINES = 300
local TAIL_CHARS = 20000

BugReport.REPO = "hemil2005/KO3"
BugReport.ISSUE_URL = "https://github.com/" .. BugReport.REPO .. "/issues/new"
BugReport.MAX_LOG_BYTES = MAX_LOG_BYTES

-- ---------------------------------------------------------------------------
-- Paths
-- ---------------------------------------------------------------------------

local function ensureDir(path)
    if lfs.attributes(path, "mode") == "directory" then return true end
    local parent = path:match("^(.*)/[^/]*$")
    if parent and parent ~= "" and parent ~= path then ensureDir(parent) end
    lfs.mkdir(path)
    return lfs.attributes(path, "mode") == "directory"
end

function BugReport.dataRoot()
    return DataStorage:getFullDataDir() .. "/ao3"
end

function BugReport.logsDir()
    return BugReport.dataRoot() .. "/logs"
end

function BugReport.reportsDir()
    return BugReport.dataRoot() .. "/reports"
end

function BugReport.logPath()
    return BugReport.logsDir() .. "/ao3.log"
end

function BugReport.tokenPath()
    return DataStorage:getSettingsDir() .. "/ao3_report_token"
end

-- ---------------------------------------------------------------------------
-- Logging
-- ---------------------------------------------------------------------------

-- Keep only the scheme, host and path; drop query strings and fragments so
-- searches, usernames in parameters, etc. never reach the log.
function BugReport.sanitizeUrl(url)
    if type(url) ~= "string" then return "" end
    local clean = url:gsub("[?#].*$", "")
    return clean
end

local function rotateIfNeeded(path)
    local size = lfs.attributes(path, "size")
    if size and size > MAX_LOG_BYTES then
        os.remove(path .. ".1")
        os.rename(path, path .. ".1")
    end
end

-- Append one line. Never raises: a failed log must not break the plugin.
function BugReport.log(event, detail)
    pcall(function()
        ensureDir(BugReport.logsDir())
        local path = BugReport.logPath()
        rotateIfNeeded(path)
        local line = os.date("%Y-%m-%d %H:%M:%S") .. " " .. tostring(event or "")
        if detail ~= nil and detail ~= "" then
            line = line .. ": " .. tostring(detail)
        end
        line = line:gsub("[\r\n]+", " "):gsub("%s+$", "")
        if #line > MAX_LINE_CHARS then
            line = line:sub(1, MAX_LINE_CHARS) .. "…"
        end
        local file = io.open(path, "a")
        if file then
            file:write(line, "\n")
            file:close()
        end
    end)
end

function BugReport.readLog()
    local file = io.open(BugReport.logPath(), "rb")
    if not file then return "" end
    local body = file:read("*a")
    file:close()
    return body or ""
end

-- Last `max_lines` lines, capped at TAIL_CHARS so issue bodies stay valid.
function BugReport.tail(max_lines)
    local body = BugReport.readLog()
    if body == "" then return "", 0 end
    local lines = {}
    for line in body:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    local first = math.max(1, #lines - (max_lines or TAIL_LINES) + 1)
    local picked = {}
    for i = first, #lines do picked[#picked + 1] = lines[i] end
    local text = table.concat(picked, "\n")
    if #text > TAIL_CHARS then
        text = "…\n" .. text:sub(#text - TAIL_CHARS + 1)
    end
    return text, #picked
end

-- ---------------------------------------------------------------------------
-- Report contents
-- ---------------------------------------------------------------------------

function BugReport.pluginVersion()
    local file = io.open(MODULE_DIR .. "/_meta.lua", "rb")
    if not file then return "unknown" end
    local body = file:read("*a")
    file:close()
    return (body or ""):match('version%s*=%s*"([^"]+)"') or "unknown"
end

function BugReport.environment()
    local screen = Device.screen
    local width = screen and screen:getWidth() or 0
    local height = screen and screen:getHeight() or 0
    return {
        "Plugin: KO3 " .. BugReport.pluginVersion(),
        "KOReader: " .. tostring(Version:getCurrentRevision() or "unknown"),
        "Device: " .. tostring(Device:info() or Device.model or "unknown"),
        "Screen: " .. tostring(width) .. "x" .. tostring(height),
        "Time: " .. os.date("%Y-%m-%d %H:%M:%S"),
    }
end

function BugReport.title(description)
    local line = tostring(description or ""):match("[^\r\n]+") or ""
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line == "" then return _("Bug report") end
    if #line > 80 then
        line = line:sub(1, 77) .. "…"
    end
    return line
end

-- Markdown body. The log is included only when `include_log` is true, which
-- the caller must have put behind a consent dialog.
function BugReport.build(description, include_log)
    local lines = {
        "# " .. BugReport.title(description),
        "",
        tostring(description or ""),
        "",
        "## Environment",
    }
    for _, item in ipairs(BugReport.environment()) do
        lines[#lines + 1] = "- " .. item
    end
    if include_log then
        local text, count = BugReport.tail()
        lines[#lines + 1] = ""
        lines[#lines + 1] = T(_("## Log (%1 lines, attached for diagnosis)"), count)
        lines[#lines + 1] = ""
        lines[#lines + 1] = "```text"
        lines[#lines + 1] = text
        lines[#lines + 1] = "```"
    else
        lines[#lines + 1] = ""
        lines[#lines + 1] = _("No diagnostic log was attached.")
    end
    return table.concat(lines, "\n") .. "\n"
end

local function writeFile(path, body)
    local file, err = io.open(path, "wb")
    if not file then return nil, err end
    file:write(body)
    file:close()
    return true
end

-- Save `report.md` (and `log.txt` when consented) in a timestamped folder.
-- Returns the folder plus both paths, or nil and an error.
function BugReport.save(description, include_log)
    local stamp = os.date("%Y%m%d-%H%M%S")
    local dir = BugReport.reportsDir() .. "/bug-" .. stamp
    local n = 1
    while lfs.attributes(dir, "mode") do
        n = n + 1
        dir = BugReport.reportsDir() .. "/bug-" .. stamp .. "-" .. n
    end
    if not ensureDir(dir) then
        return nil, T(_("Could not create %1"), dir)
    end
    local report_path = dir .. "/report.md"
    local ok, err = writeFile(report_path, BugReport.build(description, include_log))
    if not ok then
        return nil, T(_("Could not write %1: %2"), report_path, tostring(err))
    end
    local log_path
    if include_log then
        log_path = dir .. "/log.txt"
        local text = BugReport.tail()
        if text == "" then text = _("No log entries were recorded.") end
        local log_ok, log_err = writeFile(log_path, text)
        if not log_ok then
            return nil, T(_("Could not write %1: %2"), log_path, tostring(log_err))
        end
    end
    return dir, report_path, log_path
end

-- ---------------------------------------------------------------------------
-- Submission (optional, only when a token is configured)
-- ---------------------------------------------------------------------------

function BugReport.token()
    local file = io.open(BugReport.tokenPath(), "rb")
    if not file then return nil end
    local token = file:read("*a")
    file:close()
    token = (token or ""):gsub("%s+", "")
    if token == "" then return nil end
    return token
end

function BugReport.issueUrl(title)
    local escaped = tostring(title or ""):gsub("[^%w%-%._~ ]", function(c)
        return string.format("%%%02X", c:byte())
    end):gsub(" ", "+")
    return BugReport.ISSUE_URL .. "?title=" .. escaped
end

-- File the report through the GitHub API. Returns the issue URL.
function BugReport.submit(token, title, body)
    if not token or token == "" then
        return nil, _("No report token is configured.")
    end
    local payload = JSON.encode({
        title = title,
        body = body,
        labels = { "bug" },
    })
    local chunks = {}
    socketutil:set_timeout(30, 60)
    local ok, code, status = pcall(function()
        return socket.skip(1, http.request{
            url = "https://api.github.com/repos/" .. BugReport.REPO .. "/issues",
            method = "POST",
            headers = {
                ["User-Agent"] = "KO3-bugreport/1.0",
                ["Accept"] = "application/vnd.github+json",
                ["Authorization"] = "Bearer " .. token,
                ["Content-Type"] = "application/json",
                ["Content-Length"] = tostring(#payload),
            },
            source = ltn12.source.string(payload),
            sink = ltn12.sink.table(chunks),
        })
    end)
    socketutil:reset_timeout()
    if not ok then
        return nil, tostring(code)
    end
    local response = table.concat(chunks)
    if code == 201 then
        local decoded_ok, data = pcall(JSON.decode, response)
        if decoded_ok and type(data) == "table" and data.html_url then
            return data.html_url
        end
        return nil, _("The issue was created, but its URL could not be read.")
    elseif code == 401 then
        return nil, _("The report token was rejected (401). Check settings/ao3_report_token.")
    elseif code == 403 then
        return nil, _("GitHub refused the report (403). The token may lack Issues: write.")
    elseif code == 422 then
        return nil, _("GitHub rejected the report as invalid (422).")
    end
    return nil, T(_("GitHub answered HTTP %1."), tostring(code or status))
end

return BugReport
