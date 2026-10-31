# v1.4.3 — Tailscale remote access and dynamic Secure cookie

## Added

- Detailed, step-by-step Tailscale guide for Windows + iPhone/Android in
  `docs/TAILSCALE_WEBUI.md`.
- The Web sidecar already binds `0.0.0.0`; this release makes the LAN/Tailscale
  deployment explicit and documents the two firewall rules:
  - LocalSubnet for the LAN;
  - `100.64.0.0/10` for Tailscale.
- No router port forwarding or public exposure is used. Access is only through
  the encrypted Tailscale interface.
- `cookie_secure: "auto"`:
  - HTTP (LAN or `http://100.x.x.x`) receives a non-Secure cookie;
  - HTTPS (including Tailscale Serve behind loopback) receives `Secure`.
  - This prevents the common “login succeeds but cookie is dropped over HTTP”
    failure while keeping Secure cookies on HTTPS.
- Optional Tailscale Serve HTTPS (`https://<machine>.<tailnet>.ts.net`) with the
  same `auto` cookie behavior.
- File sandbox is unchanged and remains root-locked/read-only over Tailscale.

## Verified

```text
webui pytest                 14 passed
release pytest               43 passed
auto cookie HTTP             no Secure flag
auto cookie HTTPS            Secure flag
Web UI bind                  0.0.0.0:8765
LAN health                   200
Tailscale service             Running (Automatic)
Tailscale firewall            TCP 8765 from 100.64.0.0/10
```

## Current prerequisite

Tailscale on this PC is installed and running, but the account login is still
pending (`Logged out`). Complete the browser login once; then `tailscale ip -4`
returns the `100.x.x.x` address used by the phone.
