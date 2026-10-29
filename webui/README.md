# Cyber-Butler Web UI

Phase 2: email OTP login, read-only status/temperature/plugin/log APIs, and a
fixed-recipient plain-text chat. No delete, restore, reload, persona or
arbitrary-path endpoints exist.

## Requirements

- Python 3.13 (3.11+ should work)
- The project's `.astrbot_token` (read by the sidecar, never returned to the page)
- A running AstrBot on `127.0.0.1:6185`
- LibreHardwareMonitor on `127.0.0.1:18085` for CPU/GPU temperatures
- The `otp-mailer` process for email delivery

## Setup

```powershell
cd webui
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
Copy-Item config.example.json config.json
```

Edit `webui/config.json`:

- `admin_email`: the only mailbox allowed to receive OTPs;
- `owner_umo`: the fixed AstrBot conversation, e.g.
  `qq_sujinyan:FriendMessage:YOUR_QQ_ID`;
- `project_root`: project root containing `AstrBot/`;
- `host`: `127.0.0.1` for local only, or `0.0.0.0` for LAN;
- `cookie_secure`: `false` for local HTTP, `true` behind HTTPS.

The live `config.json` is git-ignored and must never be packaged.

## Run

Start the mailer from an elevated prompt (it reads the DPAPI-protected SMTP
secret; the Web API never sees the SMTP password):

```powershell
python otp_mailer.py
```

Start the API:

```powershell
$env:WEBUI_CONFIG = 'D:\path\to\webui\config.json'
.\.venv\Scripts\python.exe run.py
```

Open `http://127.0.0.1:8765`.

## LAN access

The firewall rule must be limited to the local subnet:

```powershell
New-NetFirewallRule -DisplayName 'Cyber-Butler Web UI (LAN)' `
  -Direction Inbound -Protocol TCP -LocalPort 8765 -Action Allow `
  -Profile Public,Private -RemoteAddress LocalSubnet
```

Then open `http://<LAN-IP>:8765` from a phone on the same Wi-Fi. LAN HTTP is
not encrypted; use it only on a trusted home network. Tailscale/HTTPS is the
next hardening step.

## Tests

```powershell
.\.venv\Scripts\python.exe -m pytest tests -q
```
