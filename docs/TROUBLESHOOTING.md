# Troubleshooting

What KO3 says, what it means, and what to do next.

---

| Symptom | Likely cause |
|---|---|
| KOReader exits when opening AO3 | An older KOReader build lacking newer font APIs. Current plugin versions fall back automatically — reinstall the latest `ao3.koplugin` |
| `429` or a wait message | Cloudflare's bot layer (or AO3) is refusing the client. A **VPN or privacy browser can trigger this**; wait the time shown, or turn the VPN off and retry. Do not repeatedly tap or reinstall to bypass it. If AO3 sends `Retry-After`, the plugin honours it. |
| `403` or a wait message | AO3 or its edge refused this client. A recognised browser check is not retried; other 403s get one retry, then a five-minute cooldown. |
| `404` | Work deleted, restricted, or downloads disabled |
| “did not return a work file” | Restricted/adult/login page instead of the work |
| “Could not parse the AO3 page” | AO3 changed its HTML, or `htmlparser` failed |
| Nothing happens after tapping Read | Check Wi-Fi and that the Kindle is online |
| “Could not check for updates” | The device cannot reach `github.com`. Check Wi-Fi; the check is a single small request |
| “failed its checksum” | The download was truncated or altered; nothing was installed. Try again |
| “does not contain the plugin” | The release asset is wrong or incomplete; the installed copy was left untouched |
| Update installed but nothing changed | KOReader is still running the old code — use **Restart** in the prompt, or restart it yourself |
| “Report saved” but no issue was created | The relay was unreachable; attach `report.md` (and `log.txt`) to a new issue |
| “Could not send the report” | Token rejected or no network; the report is still saved in `ao3/reports/` |

If a work opens as a login page or an adult warning, the file is rejected
before it reaches the reader, so you should see an error rather than a
broken book.


## If AO3 refuses the device

If AO3 works in your browser but not here, use AO3's **Download → HTML**
button in the browser, transfer the file to your device, and open it from
KOReader's file browser. AO3 currently reports that other download formats
are temporarily disabled. This manual path does not require the plugin's
network client.

