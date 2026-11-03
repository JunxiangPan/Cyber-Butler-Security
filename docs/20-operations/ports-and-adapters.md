# Ports and adapters

## Contents

- [6199 is not a system service](#6199-is-not-a-system-service)
- [Verification](#verification)

| Port | Owner | Meaning |
|---|---|---|
| 6185 | SCM service `CyberButlerAstrBot` | AstrBot WebUI/API |
| 18090 | SYSTEM task `AstrBot TOTP Broker` | local approval/TOTP broker |
| 8765 | desktop task `Cyber-Butler Web UI Services` | CBS dashboard |
| 8766 | desktop task `Cyber-Butler OTP Mailer` | email OTP delivery |
| 5099 | desktop task `SnowLuma Startup` | SnowLuma WebUI |
| 6199 | AstrBot OneBot adapter | **dynamic**, only after adapter configuration |

## 6199 is not a system service

`6199` is created dynamically by AstrBot's OneBot adapter after the adapter is configured and enabled. It is not installed by CBS and must not be expected to listen before that configuration.

## Verification

```powershell
Get-NetTCPConnection -State Listen |
  Where-Object { $_.LocalPort -in 6185,18090,8765,8766,5099,6199 }
```
