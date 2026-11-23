# KOReader network options for the AO3 plugin

Read-only inspection of `ao3.koplugin/main.lua` and the KOReader checkout at
`~/koreader` on 2026-11-23. **No AO3 request was made while preparing this
document.** The checkout is upstream `koreader/koreader` at
`1294bb3d377c51fdd0b7ef250620aee2ca08927c` (2026-11-21, shallow clone), with
the plugin present but untracked at `plugins/ao3.koplugin`.

**Implementation update:** after this inspection, the plugin was changed to detect explicit browser challenges (`cf-mitigated` or a `Just a moment` page) and skip its 403 retry for those responses. The other findings describe the inspected version; no claim is made that this change restores AO3 access.

## Bottom line

1. The plugin's use of `socket.http` + LuaSec is the correct native KOReader
   path for AO3: HTTPS is supported, certificates and hostnames are verified
   by default, SNI is sent, redirects are followed, and proxies work.
2. There is **no official KOReader or AO3 mechanism that can legitimately get
   past a Cloudflare JavaScript challenge**. KOReader has no embedded WebView
   or JS engine, and none of its HTTP stacks execute challenge JavaScript.
3. The native stack can legitimately improve *reliability and diagnosis*:
   verified TLS, proxy support, correct `Retry-After` handling, transport-error
   retries, 308 redirects, cancelable downloads, and honest error reporting.
   None of those change an external block.
4. The plugin currently has three concrete weaknesses that can look like an
   AO3 block: it discards the 403/429 response headers and body, it retries a
   non-transient 403, and a connected-but-“not online” state can make a tap do
   nothing at all (`NetworkMgr:runWhenOnline`).
5. The README's evidence (plugin got 403, `curl` got 429) is **not sufficient**
   to prove an external block: the two clients sent different User-Agents,
   different headers and different TLS fingerprints. The test in section 6 is
   designed to close that gap with one controlled A/B.

## 1. What the plugin does

All HTTP is plain LuaSocket `http.request`; there is no WebView, no Turbo, no
`httpasync`, no cookie jar and no login.

| Operation | URL | Code | Timeout | Sink |
|---|---|---|---|---|
| Listing/search/tag page | `https://archiveofourown.org/...` | `main.lua:167-218` | block 25 s, total 75 s (`main.lua:192`) | `ltn12.sink.table` (`main.lua:186`) |
| Work download | `https://download.archiveofourown.org/downloads/<id>/work.html` | `main.lua:872-944` | block 30 s, total 300 s (`main.lua:883`) | `ltn12.sink.file` (`main.lua:895`) |

Request headers are the same in both paths (`main.lua:180-185`,
`main.lua:888-894`):

```
User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) ... Chrome/142 ...
Accept: text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8
Accept-Language: en-US,en;q=0.9
Cookie: view_adult=true
Referer: https://archiveofourown.org/works/<id>   (download only)
```

The plugin deliberately does not keep or replay Cloudflare cookies
(`main.lua:139-148`). It throttles to one request per second
(`main.lua:146,158-165`), retries one 403 after 3 s (`main.lua:194-200`),
honors a numeric `Retry-After` on 429 with a 60 s floor and 300 s default
(`main.lua:210-215`), and remembers the cooldown only in memory
(`main.lua:169-172`). Listings call it through
`NetworkMgr:runWhenOnline` + `Trapper` (`main.lua:400-428`); downloads do the
same (`main.lua:946-975`).

## 2. Native KOReader networking stack

In the references below, `.../common/...` is shorthand for
`~/koreader/base/build/x86_64-linux-gnu-debug/common/...` (the emulator
build's installed Lua modules).

### 2.1 `socket.http` + LuaSec: the canonical path

The bundled LuaSocket is not HTTP-only. Its `SCHEMES` table includes `https`
and lazily loads `ssl.https`:

- `~/koreader/base/build/x86_64-linux-gnu-debug/common/socket/http.lua:29-42`
  — `http` and `https` schemes; `https` uses `ssl.https.tcp`.
- `.../socket/http.lua:274-305` — parses the URL, sets the scheme's port,
  builds headers and the request URI.
- `.../socket/http.lua:361-410` — opens the socket, sends the request, reads
  status/headers/body, and returns `1, code, headers, status`.
- `.../socket/http.lua:440-443` — wrapped in `socket.protect`, so transport
  and TLS failures return `nil, error-string` instead of throwing.

So `require("socket.http")` with an `https://` URL is supported and is the
right API for AO3. There is no need to require `ssl.https` directly.

### 2.2 TLS behavior

KOReader patches LuaSec so that HTTPS verifies by default when a CA bundle is
available:

- `~/koreader/base/thirdparty/luasec/default_verify.patch:18-23` — if the
  caller did not specify `verify`, load `ssl.get_system_ca()` and use
  `verify = "peer"` if a CA file was found, otherwise `"none"`.
- `~/koreader/base/thirdparty/luasec/check_hostname.patch:53-86` — adds
  `ssl.checkhostname()` and the HTTPS client always calls it after the
  handshake.
- `~/koreader/base/build/x86_64-linux-gnu-debug/common/ssl/https.lua:98-103`
  — the built LuaSec reflects that patch.
- `.../common/ssl/https.lua:162-166` — `ssl.wrap()`, SNI (`sock:sni(host)`),
  handshake, then `checkhostname()`.
- `.../common/ssl/https.lua:29-32` — defaults: `protocol = "any"`,
  `options = {"all","no_sslv2","no_sslv3","no_tlsv1"}`. SSLv2/3 and TLS 1.0
  are disabled; TLS 1.1+ (and whatever the linked LibreSSL allows) is used.
- `~/koreader/base/build/x86_64-linux-gnu-debug/common/ssl.lua:79-107` —
  CA bundle probe order. **`data/ca-bundle.crt` is first and is relative to
  the process CWD**, then `/etc/ssl/certs/ca-certificates.crt`, etc.
- `~/koreader/base/thirdparty/certifi/CMakeLists.txt:4` — installs
  `certifi/cacert.pem` as `data/ca-bundle.crt`.
- `~/koreader/base/build/x86_64-linux-gnu-debug/common/ssl.lua:118-130` —
  `get_system_ca()`; `:449` warms the cache at module load.

Consequences:

- On a normal KOReader install the plugin gets real certificate and hostname
  verification.
- If `data/ca-bundle.crt` is missing and no system bundle exists, LuaSec
  silently falls back to `verify = "none"`. The plugin does not report which
  mode was used, so a TLS problem can be invisible.
- `httpasync.lua` and `httpclient.lua` explicitly disable verification
  (below). Do not move the plugin to either for AO3 without changing that.

### 2.3 Timeouts

- `~/koreader/frontend/socketutil.lua:53-63` — `set_timeout(block,total)`
  sets `socketutil.block_timeout/total_timeout`, plus LuaSocket's
  `http.TIMEOUT` and `https.TIMEOUT`.
- `socketutil.lua:82-90` — monkey-patches `socket.tcp` so each new socket
  gets both block (`"b"`) and total (`"t"`) timeouts. This is what makes the
  timeout apply to both HTTP and HTTPS.
- `.../common/ssl/https.lua:115-118` — LuaSec's HTTPS connection overrides
  `settimeout()` and always uses `https.TIMEOUT`; `socketutil` keeps that
  value in sync at `socketutil.lua:60-61`.
- `socketutil.lua:38-49` — the comments are explicit that the socket-level
  total timeout is reset between polls and is therefore only a weak cap.
- `socketutil.lua:139-181` — `table_sink()` and `file_sink()` are the only
  reliable total-time enforcement. **The plugin uses plain `ltn12` sinks, so
  the 75 s / 300 s total limits are not actually enforced by the sink.** A
  stalled server can keep the request alive in block-timeout increments.
- `socketutil:set_timeout()` mutates process-global `http.TIMEOUT`,
  `https.TIMEOUT` and `socket.tcp`. Concurrent KOReader network activity
  (OPDS, news, Wikipedia) can clobber or inherit the plugin's timeout.
- DNS resolution happens below LuaSocket and is outside these timeouts
  (`socketutil.lua:50-51`).

### 2.4 Redirects

Bundled LuaSocket follows redirects itself:

- `.../socket/http.lua:307-324` — follows `301`, `302`, `303`, `307` for
  `GET`/`HEAD` only, up to 5; resolves relative `Location`; strips whitespace;
  refuses an `https` → `http` downgrade. **`308` is not followed.**
- `.../socket/http.lua:336-359` — `tredirect()` re-issues the request and
  passes the *same* `headers` table onward. This preserves `User-Agent`,
  `Cookie` and `Referer` across redirects, including cross-origin redirects.
  There is no cookie/origin scoping here.
- `.../common/ssl/https.lua:194-198` — LuaSec's own `https.request()` refuses
  `redirect = true` ("redirect not supported"). Using `socket.http` (as the
  plugin does) avoids that limitation; direct `https.request` would need
  manual redirect handling.
- `~/koreader/plugins/opds.koplugin/opdsclient.lua:9-15,40-88` — official
  in-tree example of manual redirects, including 308, same-origin credential
  filtering, HTTPS-downgrade rejection, and a cookie jar.

Practical impact for AO3: a 301/302 from archive to download (or to a login
page) is followed; a 308 would surface as `HTTP 308`. AO3/Cloudflare redirects
to a challenge page are followed too, so the final body/status is what the
plugin sees.

### 2.5 Cookies

There is **no core cookie jar**. `http.request` sends only the `Cookie` header
the caller supplies. `Set-Cookie` is returned in the response headers, and
multiple `Set-Cookie` headers are concatenated with `", "` by
`receiveheaders()`:

- `.../socket/http.lua:47-72`, especially `:58` (header names are
  lowercased) and `:69` (duplicate headers joined with `", "`).
- `~/koreader/plugins/opds.koplugin/cookiejar.lua:61-138` — a robust
  plugin-local jar (domain/path/secure/expiry, `Max-Age`, comma-aware
  `Set-Cookie` splitting). It is not a core API; it is an OPDS implementation
  to copy if a jar is ever needed.
- `~/koreader/frontend/ui/wikipedia.lua:104-125` — a simpler example that
  extracts only `name=value` for rate-limit buckets.

The plugin's no-jar policy is correct for Cloudflare bot cookies. A jar would
only be legitimate for AO3's own session/adult cookies, and AO3 login is out
of scope. Note that LuaSocket's comma-joined `Set-Cookie` makes naive parsing
unsafe; use the OPDS splitter if this is ever revisited.

### 2.6 Retries

No retry policy is built into `socket.http` or `socketutil`. In-tree
precedents:

- `~/koreader/frontend/ui/wikipedia.lua:159-199` — sets timeouts, performs
  the request, retries **once on 429**, uses numeric `Retry-After` capped at
  30 s, uses `socketutil.table_sink` for total time, validates
  `Content-Length` at `:221-225`, and maps timeout/SSL/sink codes at
  `:205-211`.
- `~/koreader/plugins/opds.koplugin/opdsclient.lua:70-74` — retries **once on
  a TLS handshake `wantread`** for idempotent GET/HEAD, and stores cookies
  after each response.
- `~/koreader/frontend/socketutil.lua:93-99,109-134` — the official error
  codes (`timeout`, `wantread`, `wantwrite`, `sink timeout`, `closed`) and
  `describe_error()` for human-readable messages. The plugin does not use
  `describe_error()`.

The plugin instead retries only a 403. That is the least useful thing to
retry: 403 is normally a policy/WAF decision, not a transient transport
failure. A transport retry should target `timeout`/`wantread`/`closed` on
idempotent GETs, with backoff and jitter, and 429 should always honor
`Retry-After`.

### 2.7 Proxy and online state

- `~/koreader/frontend/ui/network/manager.lua:680-696` — `setHTTPProxy()`
  sets `http.PROXY`.
- `.../common/ssl/https.lua:81-158` — LuaSec reads `params.proxy` or
  `http.PROXY`, performs an HTTP `CONNECT`, supports proxy auth, then starts
  TLS to the origin. HTTPS through KOReader's configured proxy therefore
  works.
- `manager.lua:641-649` — `isOnline()` is **not** a ping to AO3; it calls
  `canResolveHostnames()`.
- `manager.lua:348-356` — `canResolveHostnames()` resolves
  `dns.msftncsi.com`. If that name is blocked but AO3 resolves, KOReader
  considers itself offline.
- `manager.lua:698-711` — `runWhenOnline(callback)` runs the callback only
  when `isOnline()` is true. If `isConnected()` is true but `isOnline()` is
  false, it calls `beforeWifiAction()` **without the callback and returns**.
  The callback never runs.
- The plugin's `fetchPage` (`main.lua:400-428`) and `readWork`
  (`main.lua:946-975`) have no `else` branch and no message for the
  “connected but not online” path. A tap can therefore produce **nothing at
  all** (or a Wi-Fi prompt), with no AO3 error. This is a plugin-visible
  failure mode independent of AO3.
- `manager.lua:621-639` — `afterWifiAction()` only acts if
  `beforeWifiAction()` actually ran; when already online it is a no-op.
- `manager.lua:713-725` — `runWhenConnected(callback)` only needs
  `isConnected()`, and `willRerunWhenOnline()` at `:727-741` returns true
  when a rerun was scheduled. Either is a better fit for “attempt and report
  the real error” than `runWhenOnline` with no fallback.

### 2.8 The other in-tree HTTP clients

**`ssl.https.request` directly** (`.../common/ssl/https.lua:186-205`):
forbids `redirect` and `create`; not suitable for AO3 without manual
redirects.

**`httpasync.lua`** (`~/koreader/frontend/httpasync.lua`): a non-blocking
coroutine/socket scheduler used by the built-in Wikipedia image downloader
and news downloader (`frontend/ui/wikipedia.lua:1618-1632`,
`plugins/newsdownloader.koplugin/epubdownloadbackend.lua:686-697`).

- `httpasync.lua:136-141` — hardcodes `verify = "none"`.
- `httpasync.lua:205-210` — follows any 3xx with `Location`, max 5.
- `httpasync.lua:212-215` — turns every `>= 400` into `"HTTP error N"` and
  throws away headers.
- `httpasync.lua:110,159-172` — accepts extra headers but has no cookie jar,
  no `Retry-After`, no conditional requests.

It is useful for many small parallel images, but it is a poor fit for AO3:
it degrades TLS and diagnostics, and concurrency would make 429s worse.

**`httpclient.lua` / Turbo** (`~/koreader/frontend/httpclient.lua:1-37`):
legacy coroutine client; `turbo.async.HTTPClient({verify_ca = false})` at
`:26`, connect/request timeouts at `:15-16`. Only KOSync uses it
(`plugins/kosync.koplugin/KOSyncClient.lua:43`). Not appropriate for AO3.

**`Trapper`** (`~/koreader/frontend/ui/trapper.lua`): `wrap()` at `:42-61`
runs the job in a coroutine, but a synchronous `http.request` still blocks
the UI. `dismissableRunInSubprocess()` at `:500-...` can run the job in a
child process and `SIGKILL` it on dismiss (`:551`, `:595-597`). That gives a
cancelable network action without changing TLS or HTTP behavior. It does not
change whether AO3/Cloudflare accepts the request.

### 2.9 Error surfaces available

From LuaSocket/LuaSec, in order of likelihood:

| Surface | Where | What the plugin currently shows |
|---|---|---|
| DNS failure | `socket.dns.toip` below LuaSocket | `host not found` (or silent no-op via `isOnline`) |
| TCP refusal/timeout | `socketutil.TIMEOUT_CODE` | `timeout` / raw string |
| TLS handshake | `ssl.https` `wantread`/`wantwrite`, `certificate verify failed`, `hostname does not match certificate` | raw string |
| HTTP 403 | `http.lua:410` | first retry, then `blockedMessage("403")`; body/headers discarded |
| HTTP 429 | same | `blockedMessage("429")`; numeric `Retry-After` honored |
| HTTP 404/503/other | same | mapped messages at `main.lua:100-116`; other codes `HTTP N` |
| 200 + challenge HTML | `main.lua:309-313` | “Cloudflare wants a browser check” only if no `li.blurb` |
| 200 + work-page login/adult page | download validation `main.lua:911-921` | “AO3 did not return a work file (<title>)” |
| gzip/binary body | no decompression | “Could not parse the AO3 page” (misleading) |

`main.lua:100-116` maps only 403/404/429/503; everything else is `HTTP N`.
`main.lua:206-215` discards the body for 403/429, so the UI cannot say
whether the response was a Cloudflare challenge, an AO3 refusal, or an
AO3 rate-limit page. `main.lua:309-313` only inspects challenge markers on a
200 response.

## 3. Concrete findings

| # | Finding | Evidence | Impact |
|---|---|---|---|
| 1 | 403/429 body and headers are discarded | `main.lua:206-215` | Cannot distinguish Cloudflare from AO3; all 403s look alike |
| 2 | 403 is retried; transport errors are not | `main.lua:194-200` | Wastes a request on a policy block; misses the actually transient failures |
| 3 | 308 is not followed by LuaSocket | `.../socket/http.lua:307-324` | A 308 from AO3/CDN becomes `HTTP 308`; OPDS has the manual pattern |
| 4 | Total timeout is set but not enforced by the sink | `main.lua:186,895`; `socketutil.lua:38-49,139-181` | Stalled transfer can block far longer than 75/300 s |
| 5 | Timeout state is global | `socketutil.lua:53-63,82-90` | Concurrent KOReader downloads can interfere |
| 6 | Connected-but-`isOnline`-false silently skips the job | `manager.lua:698-711`; `main.lua:400-428,946-975` | Tap does nothing; looks like AO3/plugin failure |
| 7 | CA failure silently means `verify=none` | `https.lua:98-103`; `ssl.lua:79-107` | No visibility into TLS mode; security regression without a message |
| 8 | Chrome UA over a LuaSec/OpenSSL stack | `main.lua:47,180-185` | Plausible WAF signal; A/B needed, not proof |
| 9 | No content-type/encoding check | `main.lua:291-294,911-921` | gzip/challenge body is reported as a parse error or wrong title |
| 10 | Cooldown is memory-only | `main.lua:169-172` | Restart immediately re-requests while blocked |
| 11 | Cookies are replayed across redirects without origin scoping | `.../socket/http.lua:336-359` | `view_adult=true` (and any future cookie) can go to a redirect target |
| 12 | `Retry-After` HTTP-date is ignored | `main.lua:211-212` | Falls back to 300 s; safe but not precise |

The 429 path is otherwise sound: lowercased `retry-after` is correct because
LuaSocket lowercases header names (`.../socket/http.lua:58`), and the plugin
does not immediately retry a 429.

## 4. Can an official non-WebView mechanism improve AO3 access?

### What cannot work

- **No challenge solving.** KOReader core has no embedded WebView or
  JavaScript engine (grep of `frontend/` and `plugins/` finds no WebView; the
  only browser handoff is `Device:openLink`, an external app that cannot
  return parsed HTML). LuaSocket/LuaSec cannot execute a Cloudflare
  challenge.
- **No cookie replay.** `cf_clearance` is bound to the client/IP/UA/TLS
  fingerprint that earned it. Replaying it from LuaSec is exactly what the
  plugin already found made 403s stick (`main.lua:139-148`); it is not a
  supported mechanism and should stay out.
- **No fingerprint spoofing / IP rotation.** Those are bypass techniques,
  not networking APIs, and are outside a legitimate fix.
- **`httpasync` and Turbo do not help.** Both disable certificate
  verification (`httpasync.lua:136-141`, `httpclient.lua:26`), and
  `httpasync` loses response headers. They would make the plugin less safe
  and no more acceptable to Cloudflare.

### What can legitimately help

1. **Keep `socket.http` + verified LuaSec.** Ensure `data/ca-bundle.crt` is
   present; report `ssl.get_system_ca()`/verify mode in diagnostics. Never
   fall back to `verify=none` silently.
2. **Use `NetworkMgr:runWhenConnected` or `willRerunWhenOnline`.** Attempt
   the request and show the real error instead of silently returning when
   `dns.msftncsi.com` is unreachable. This is the highest-value fix for a
   “nothing happens” failure.
3. **Retry the right things.** Retry `timeout`/`wantread`/`closed` once or
   twice on GET with exponential backoff and jitter; honor numeric and
   HTTP-date `Retry-After` on 429; do not retry 403. Respect a persisted
   cooldown across restarts.
4. **Handle 308 manually** (or adopt the OPDS redirect loop) so an AO3/CDN
   redirect change does not become a hard failure.
5. **Capture bounded diagnostics on failure.** Keep the first ~1–2 KB of the
   body and selected headers (`server`, `cf-ray`, `cf-mitigated`,
   `retry-after`, `content-type`, `content-encoding`, `location`) in the log
   or error dialog. Never log cookies or credentials.
6. **Use `socketutil.table_sink`/`file_sink`** so the total timeout means
   something, and consider `Trapper:dismissableRunInSubprocess` so a stalled
   request can be cancelled and the UI stays responsive.
7. **Use `socketutil.describe_error`** for TLS/timeout codes instead of
   showing raw `wantread`/`timeout` strings.
8. **User-configured proxy only.** KOReader's HTTP proxy support is
   legitimate for a user's own network; it is not a Cloudflare bypass and
   should not be used to evade an AO3 block.
9. **AO3's own download endpoint** is already used. Alternate formats
   (`work.epub`, etc.) may reduce HTML parsing, but this document makes no
   claim about their availability or Cloudflare treatment without a request.
   There is no AO3 public API/OAuth client in KOReader or the plugin.
10. **AO3 feeds** (if any) would still traverse the same edge and would need
    a request to verify; no feed parser exists in the plugin. Not a bypass.

## 5. One tight reproducible test

**Goal:** decide whether the failing request is rejected because of the
plugin's request identity, because of the network/TLS stack, or because AO3/
Cloudflare is rejecting this egress. Run it once, from the **same egress**
(same Wi-Fi, same proxy/VPN state) as the failing KOReader, ideally in the
emulator; repeat later on the physical Kindle if possible.

### Test shape

Use KOReader's own test environment (`~/koreader`, `./kodev test`) with a
throwaway spec outside the plugin (do not modify the plugin). The spec wraps
`socket.http.request` only to observe the exact request the plugin makes, then
calls `plugin:fetchHtml()` normally.

Probe 1 — exact plugin request:

```
dofile("plugins/ao3.koplugin/main.lua")  -- fresh instance per probe
GET https://archiveofourown.org/works     -- the failing URL
headers: exactly main.lua:180-185
redirect = true
```

Probe 0 — neutral TLS/DNS control (same process, same stack):

```
GET https://example.com/
```

Probe 2 — only if probe 1 returns 403, after a 10 s wait: repeat the same AO3
URL with a **fresh plugin instance** and remove `User-Agent` and `Cookie` from
the outgoing table (keep `Accept`/`Accept-Language`). This isolates the
spoofed Chrome UA and the `view_adult=true` cookie from the IP/TLS path.
This is one test script, but allow up to two AO3 requests for probe 1 and two
for probe 2 because the plugin itself retries a 403 once; never loop it.

For each probe record:

- final HTTP code, or `nil` + raw LuaSocket/LuaSec error string;
- `headers.server`, `headers["cf-ray"]`, `headers["cf-mitigated"]`,
  `headers["retry-after"]`, `headers["content-type"]`,
  `headers["content-encoding"]`, `headers.location`;
- body length and first 1–2 KB (redact cookies);
- elapsed seconds and number of `http.request` calls (should be 1, or 2 only
  for the plugin's 403 retry);
- whether the body contains `Just a moment`, `cf-challenge`,
  `Enable JavaScript and cookies`, `id="preface"`, `id="chapters"`,
  `li class="blurb`;
- `plugin:parseListing(body)` result: `#items`, `next_url`, and any parser
  error.

Then run the existing offline suite once (`./kodev test
--busted=--pattern=ao3_ front`) to prove the parser path is green.

### Decision table

| Probe 1 | Probe 0 | Probe 2 | Conclusion |
|---|---|---|---|
| 200, `#items > 0` | 200 | n/a | Plugin works now; earlier failure was transient/external, or URL/state-specific |
| 200, `#items = 0`, CF markers | 200 | n/a | External Cloudflare challenge served with 200 |
| 403 + `cf-mitigated`/`cf-ray` | 200 | 403 | External Cloudflare block at this egress |
| 403, no CF headers | 200 | 403 | AO3/edge refusal at this egress (or a non-CF WAF) |
| 403, no CF headers | 200 | **200** | Plugin request identity (UA/cookie/header set) triggered it — plugin-config bug, not an IP block |
| 429 + `retry-after` | 200 | 429 | External AO3 rate limit; wait, do not retry |
| 200 + valid-looking body, parser error | 200 | n/a | Plugin/parser bug; compare body to `fixtures/search.html` |
| `nil, "timeout"`/`wantread` | 200 | n/a | Transport/TLS problem on the device path, not AO3 semantics |
| `nil`, TLS/hostname/CA error | 200 | n/a | Device CA/clock/TLS problem |
| any | **fails** | n/a | Device network/DNS/TLS stack, not AO3; fix control first |

The critical comparison is **probe 1 vs probe 2 on the same egress**: a 403
that becomes 200 when only the plugin's UA/Cookie are removed proves the
plugin's request identity is the trigger. A 403 that stays 403 is an external
block at that egress (or a TLS-fingerprint block, which is still external to
the plugin's Lua code). A 200 whose body parses offline but which the UI
reported as an error is a plugin bug.

## 6. Evidence that is missing today

- **The actual failing response.** The plugin discards 403/429 bodies and
  headers (`main.lua:206-215`); the README only records the status numbers
  (`README.md:135-147`). We do not know whether the 403 was a Cloudflare
  challenge (`cf-mitigated: challenge`, `cf-ray`, “Just a moment”), an AO3
  WAF refusal, or an AO3 error page.
- **A same-client comparison.** “Plugin got 403, `curl` got 429” compares
  different User-Agents, headers and TLS stacks (`README.md:135-137`). It
  does not establish IP-level blocking.
- **Whether the plugin's Chrome UA/cookie is the trigger.** No A/B with the
  same URL, same egress and only the headers changed.
- **The device's TLS state.** `ssl.get_system_ca()` result, whether
  `data/ca-bundle.crt` exists, whether verification was `peer` or `none`,
  the device clock, and the exact TLS error (if any).
- **The network path.** Wi-Fi SSID, proxy on/off, VPN, IPv4 vs IPv6, DNS
  results for `archiveofourown.org` and `dns.msftncsi.com`, and
  `NetworkMgr:isOnline()`. A connected-but-offline NCSI result produces a
  silent no-op, not an AO3 response.
- **Host scope.** Whether `archiveofourown.org` and
  `download.archiveofourown.org` behave differently.
- **Retry evidence.** The number of requests the plugin actually sent,
  including the 403 retry and any restart after the in-memory cooldown.
- **Exact UI symptom.** “Nothing happens” vs “Cloudflare wants a browser
  check” vs “AO3 is limiting this connection (403)” vs a raw Lua error.
- **Reproduction on a second network/device.** One egress cannot distinguish
  an IP/shared-network block from a plugin/client issue.
- **Duration and scope of the block.** Whether the 429's `Retry-After` was
  numeric, and whether the block lifts after the stated interval.
- **A physical Kindle run.** The README says only the emulator was tested
  (`README.md:130-135`).

## 7. References

Plugin (all paths relative to `E:\ao3 plugin`):

- `ao3.koplugin/main.lua:45-47` — base URLs and Chrome UA.
- `ao3.koplugin/main.lua:100-116` — HTTP status/error mapping.
- `ao3.koplugin/main.lua:139-165` — no-cookie policy, 1 s throttle.
- `ao3.koplugin/main.lua:167-218` — `fetchHtml` request, 403 retry, 429
  cooldown, body discard.
- `ao3.koplugin/main.lua:291-313` — listing parse and 200-only Cloudflare
  detection.
- `ao3.koplugin/main.lua:400-428` — `fetchPage` + `runWhenOnline` (no else).
- `ao3.koplugin/main.lua:872-944` — `downloadWork`, download headers, sink,
  validation, rename.
- `ao3.koplugin/main.lua:946-975` — `readWork` + `runWhenOnline` (no else).
- `ao3.koplugin/spec/ao3_spec.lua:195-310` — mocked 200/403/429 tests;
  confirms the 403 retry and cooldown behavior but cannot observe real
  headers.
- `README.md:130-147` — current connectivity claim and its limits.

KOReader (`~/koreader`):

- `frontend/socketutil.lua:20-25` — KOReader User-Agent.
- `frontend/socketutil.lua:38-63,82-90` — timeout semantics, HTTPS timeout,
  `socket.tcp` patch.
- `frontend/socketutil.lua:93-134` — error codes and `describe_error`.
- `frontend/socketutil.lua:139-181` — total-time sinks.
- `frontend/socketutil.lua:183-217` — header/request redaction.
- `frontend/httpasync.lua:110-215` — async client, `verify="none"`,
  redirects, `>=400` handling.
- `frontend/httpclient.lua:15-37` — Turbo client, `verify_ca=false`.
- `frontend/ui/network/manager.lua:348-356` — NCSI DNS check.
- `frontend/ui/network/manager.lua:621-649` — `afterWifiAction`, `isOnline`.
- `frontend/ui/network/manager.lua:680-711` — proxy and `runWhenOnline`.
- `frontend/ui/network/manager.lua:713-741` — `runWhenConnected`,
  `willRerunWhenOnline`.
- `frontend/ui/trapper.lua:42-61` — coroutine wrapper (still blocking HTTP).
- `frontend/ui/trapper.lua:500-551,595-597` — cancelable subprocess.
- `frontend/ui/wikipedia.lua:146-230` — reference HTTP client: timeouts,
  429 retry, `Retry-After`, content-length check, error mapping.
- `plugins/opds.koplugin/opdsclient.lua:9-88` — reference redirect/cookie/
  handshake-retry client.
- `plugins/opds.koplugin/cookiejar.lua:61-138` — reference cookie jar.
- `plugins/kosync.koplugin/KOSyncClient.lua:43` — sole Turbo `httpclient`
  consumer.
- `base/thirdparty/luasec/default_verify.patch:18-23` — peer verification
  default.
- `base/thirdparty/luasec/check_hostname.patch:53-86` — hostname check.
- `base/thirdparty/certifi/CMakeLists.txt:4` — installs
  `data/ca-bundle.crt`.
- `base/build/x86_64-linux-gnu-debug/common/socket/http.lua:29-42` — HTTPS
  scheme support.
- `.../common/socket/http.lua:47-72` — lowercase headers, duplicate-header
  join.
- `.../common/socket/http.lua:274-305,361-410` — request/response flow.
- `.../common/socket/http.lua:307-324` — redirect rules (no 308).
- `.../common/socket/http.lua:336-359` — redirect header reuse.
- `.../common/ssl/https.lua:29-32` — protocol/options defaults.
- `.../common/ssl/https.lua:81-166` — proxy CONNECT, verify default, SNI,
  handshake, hostname.
- `.../common/ssl/https.lua:186-205` — direct `https.request`, redirects
  forbidden.
- `.../common/ssl.lua:79-130,449` — CA bundle paths and discovery.
