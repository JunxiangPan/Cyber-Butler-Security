# Troubleshooting

## Contents

- [Quick fixes (read this first)](#quick-fixes-read-this-first)
- [AstrBot 6185 does not listen](#astrbot-6185-does-not-listen)
- [Broker 18090 does not listen](#broker-18090-does-not-listen)
- [SnowLuma 5099 does not listen](#snowluma-5099-does-not-listen)
- [6199 does not listen](#6199-does-not-listen)
- [WFP reports `Remove-NetFirewallRule failed`](#wfp-reports-remove-netfirewallrule-failed)

## Quick fixes (read this first)

### 1. AstrBot 6185 does not listen

```powershell
Get-Service CyberButlerAstrBot
Start-Service CyberButlerAstrBot
Get-Content '<InstallPath>\AstrBot\data\logs\service-astrbot.log' -Tail 60 -Encoding UTF8
```

Look for `SERVICE_START`, `SERVICE_DATA_WRITE_OK`, `SERVICE_CHILD ... job=assigned`.

### 2. Installer window flashes and closes

Run `START-INSTALLER.exe` **as administrator**. The report is here:

```text
C:\ProgramData\CyberButler\installer-report\install-report.json
C:\ProgramData\CyberButler\installer\state\<latest>\state.json
```

### 3. Port already in use

```powershell
Get-NetTCPConnection -State Listen |
  Where-Object { $_.LocalPort -in 6185,18090,8765,8766,5099 }
```

Stop the owning process, then start the associated service/task again. Do not delete data.

### 4. TOTP QR is a white box

The installer can rebuild `totp_qr.png` from the existing DPAPI secret. Do not delete `totp_secret.dpapi` or `recovery_codes.txt`.

### 5. 6199 does not listen

6199 is opened dynamically by the AstrBot OneBot adapter; configure and enable that adapter first.


## AstrBot 6185 does not listen

```powershell
Get-Service CyberButlerAstrBot
Get-CimInstance Win32_Service -Filter "Name='CyberButlerAstrBot'" |
  Select-Object Name,State,StartName,ProcessId
Get-NetTCPConnection -LocalPort 6185 -State Listen
Get-Content '<InstallPath>\AstrBot\data\logs\service-astrbot.log' -Tail 100 -Encoding UTF8
```

The log must contain `SERVICE_START`, `SERVICE_DATA_WRITE_OK`, and `SERVICE_CHILD ... job=assigned`.

## Broker 18090 does not listen

```powershell
Get-Content '<InstallPath>	ools\logsroker-startup.log' -Tail 80 -Encoding UTF8
```

The Broker refuses to run if `tools` is writable by a low-privilege principal. Keep `tools` read-only for pjx20.

## SnowLuma 5099 does not listen

Check `SnowLuma\logs\start-snowluma-console.log` and `SnowLuma\logs\startup-snowluma.err.log`. Scripts containing Chinese paths must be UTF-8 with BOM for PowerShell 5.1.

## 6199 does not listen

6199 is not a system service. Configure and enable the AstrBot OneBot adapter first; then the adapter creates the port.

## WFP reports `Remove-NetFirewallRule failed`

The guard now checks for matching rules before removing them. A status of `ok=true, applied=0` means audit mode is healthy. Enforcement is not enabled in v1.6.2.
