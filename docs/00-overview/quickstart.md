# Quick start

## Status at a glance

| Component | Status | Note |
|---|---|---|
| SCM service / SQLite / Job Object | ✅ | 6185 verified |
| TOTP Broker | ✅ | 18090 |
| WebUI | ✅ | 8765 |
| WFP outbound blocking | ⚠️ | audit only |
| OTP Mailer / SnowLuma | ✅ | 8766 / 5099 |
| 6199 OneBot adapter | ❌ | configure manually |
| Light tier | ✅ | install passed; reduced isolation |


1. Use a clean Windows 10/11 x64 machine with administrator rights.
2. Run `START-INSTALLER.exe` as administrator.
3. Choose the install path, tier (High recommended for isolation testing), WebUI bind = Loopback, and personal plugin path.
4. Leave the API key blank unless a key file is explicitly prepared.
5. At the TOTP step scan the QR and save the recovery codes offline.
6. After installation verify:

```powershell
Get-Service CyberButlerAstrBot
Get-NetTCPConnection -State Listen |
  Where-Object { $_.LocalPort -in 6185,18090,8765,8766,5099 }
```

See `../20-operations/ports-and-adapters.md` for each port.
