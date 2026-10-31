# v1.4.0 — Web UI Phase 2: read-only monitor + fixed-recipient chat

## Added

- Independent FastAPI sidecar under `webui/` with its own virtual environment
  and `otp-mailer` process. The Web API never reads the SMTP password.
- Email OTP login (6 digits, 5 minutes, one use, attempt/rate limits),
  HttpOnly/SameSite=Strict sessions and CSRF-protected actions.
- Read-only APIs:
  - `GET /api/status` — AstrBot, Broker, SnowLuma TCP health;
  - `GET /api/temps` — CPU/GPU temperature, GPU load, VRAM;
  - `GET /api/astrbot/plugins` — plugin names/versions/activated state;
  - `GET /api/logs?name=...` — allowlisted tails with secret/path redaction.
- `POST /api/chat/send` — fixed `owner_umo`, plain text, 500 characters,
  5 sends/minute/IP, CSRF required.
- Mobile-first dashboard cards, temperature/VRAM meters, service dots, plugin
  list, log viewer and chat box; dark/light theme.
- LAN binding support (`host: 0.0.0.0`) and a subnet-scoped firewall rule.

## Security boundary

The Web UI exposes no delete, restore, reload, persona, config-write or
arbitrary-file API. Chat cannot choose a recipient. The dashboard and OTP mailer
run separately; the SMTP secret stays in the elevated mailer process.

## Verified

```text
release pytest              43 passed
webui pytest                 9 passed
Live read-only APIs         200
Live fixed chat send        200 (test message delivered)
LAN health                  200 (192.168.1.111:8765)
```

## Remaining

Tailscale/HTTPS, SYSTEM service installation and the final external security
review remain for the next revision.
