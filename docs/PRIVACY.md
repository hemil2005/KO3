# Privacy

KO3 has no analytics, no telemetry, no advertising and no account of its own.
It talks to AO3 when you ask it to, and to GitHub for updates and bug reports.

## On the device

| Path | What it holds |
|---|---|
| `koreader/ao3/<title> [<id>].html` | Works you chose to download |
| `settings/ao3.lua` | AO3's session cookie, and `remember_user_token` when AO3 sets it |
| `settings/ao3_prefs.lua` | Display choices, favourite fandoms, the last-read path, update-check state and saved-work check results |
| `koreader/ao3/logs/ao3.log` | The diagnostic log, capped at 256 KB with one rotation |
| `koreader/ao3/reports/bug-<timestamp>/` | A report bundle saved when the relay cannot be reached |
| `settings/ao3_report_token` | Only on the maintainer's device; bypasses the relay |

The AO3 password is posted once, directly to AO3 over HTTPS, and is never
written to disk. The session cookie lives in plain text in
`settings/ao3.lua`, like KOReader's other service settings. **Log out** removes
that file and its `.old` backup. Cloudflare cookies are never stored or
replayed.

Cookies are scoped to `archiveofourown.org` and
`download.archiveofourown.org`, and the plugin refuses an HTTPS → HTTP
redirect rather than send them over plain HTTP.

## What is sent, and when

- **AO3.** Only on a tap: one page per screen, one form post per action, one
  download per **Read** or **Refresh**. The standing exceptions are the quiet
  saved-work watch and, when enabled, work subscriptions. Both ask AO3 for a
  work's chapter menu, not the work; one work per tick, at most once a day per
  work, and the subscriptions list once a day.
- **GitHub.** Once a day for a release check while the plugin is open, and only
  when you start an update. Update downloads are checksum-verified before they
  replace anything.
- **The bug-report relay.** Only when you create a report and consent to send
  it.

## Bug reports

A report contains your description and, only if you choose **With log**, the
diagnostic log. It is POSTed to the project's Cloudflare Worker, which files a
GitHub issue with a fine-grained token that never ships in the plugin. Reports
become public GitHub issues, so do not put personal details in the description.
The relay accepts 10 reports per IP per day and needs no GitHub account.

If the relay is unreachable, the same bundle is written to
`koreader/ao3/reports/bug-<timestamp>/` on the device and nothing is sent. You
can attach it to a new issue yourself.

The log contains:

- plugin version, KOReader revision, device model, screen size and time;
- each request's host and path with its HTTP status, download outcomes and
  error text.

It never contains your AO3 password, cookies, search text, work titles or work
text. Query strings and fragments are stripped before anything is written.

See [Reporting a bug](USER-GUIDE.md#reporting-a-bug) for the screen flow, and
[`relay/README.md`](../relay/README.md) for the relay's deployment and token
rotation.
