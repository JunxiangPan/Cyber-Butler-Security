# Troubleshooting

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
