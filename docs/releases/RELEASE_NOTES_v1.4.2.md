# v1.4.2 — Read-only hardware, usage, backups, alerts and file sandbox

## Added

- Hardware dashboard: live CPU/GPU temperature + VRAM cards and a lightweight
  SVG trend drawn from `/api/temps` (last 30 samples in the page only).
- Today's token usage from AstrBot's provider stats. Cost is estimated only
  when `token_pricing` contains a blended USD-per-million rate; otherwise the
  UI says "未配置" rather than showing a false zero.
- Safe fixed shortcuts: weather, voice request and model-status message. These
  post through the inbound bridge; no model-switching control is added because
  that would be a state-changing action.
- Read-only backup list (`backups/` names and sizes only; no restore/download).
- Red security banner polling `/api/security/pending`; it shows action, basename
  and approval channel only. There is no OTP input or approve button in the Web
  UI.
- Read-only sandbox file manager:
  - `GET /api/files/list` and `GET /api/files/download` only;
  - configured root, absolute/`..`/symlink/junction escape rejected with 403;
  - executable/script/active-content extensions hidden and blocked on download;
  - 20MB per-file limit; text and image preview in the browser;
  - every denial appended to `webui/data/files-audit.log`.
- The WPF Settings security section now exposes the file sandbox root; the
  sidecar re-reads it from `webui-config.json`, so no Web write API is needed.

## Security boundary

No file write/delete/upload/rename/restore endpoint exists. Backups are
list-only. The security banner never accepts a TOTP or email challenge. The
sidecar still only binds to the configured LAN address and keeps the OTP mailer
on loopback.

## Verified

```text
webui pytest                 12 passed
release pytest               43 passed
files traversal              403
executable download          403
over-20MB download           403
empty TOTP pending          {"ok": true, "pending": false}
LAN health                  200
```
