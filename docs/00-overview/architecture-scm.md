# High-tier architecture: native Windows SCM service

## Contents

- [Why the SCM service replaced S4U](#why-the-scm-service-replaced-s4u)
- [Service wrapper properties](#service-wrapper-properties)
- [Security boundary](#security-boundary)
- [Operational checks](#operational-checks)

## Why the SCM service replaced S4U

On this local non-domain Windows host, Task Scheduler rejected both local-account S4U registration and Password registration with `Access is denied` / `username or password incorrect`. A `runas` test proved the account and password were valid. The temporary SYSTEM-launcher workaround was rejected because it creates a SYSTEM parent process and a privilege-escalation surface.

High tier therefore uses a native Windows service:

```text
Service: CyberButlerAstrBot
Account: CyberButlerSvc
Binary:  <InstallPath>\tools\service\CyberButlerAstrBotService.exe
Log:     <InstallPath>\AstrBot\data\logs\service-astrbot.log
```

## Service wrapper properties

- Absolute Python and working-directory paths.
- Session 0 / GUI fail-closed environment (`ASTRBOT_SERVICE_MODE`, `ASTRBOT_DISABLE_GUI`, `QT_QPA_PLATFORM=offscreen`, `MPLBACKEND=Agg`, empty `DISPLAY`).
- stdout and stderr redirected to one log.
- machine-readable startup lines: account, cwd, workdir, root, child PID, Job Object assignment.
- `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`; descendants are killed when the service stops.
- data-directory write probe before launching AstrBot.

## Security boundary

```text
CyberButlerAstrBotService.exe:
  CyberButlerSvc:RX
  SYSTEM:F
  Administrators:F
```

`SeDenyInteractiveLogonRight` is restored for `CyberButlerSvc`. Service logon uses `SeServiceLogonRight`, so interactive logon is not required.

## Operational checks

```powershell
Get-Service CyberButlerAstrBot
Get-CimInstance Win32_Service -Filter "Name='CyberButlerAstrBot'" |
  Select-Object Name,State,StartName,ProcessId
Get-NetTCPConnection -LocalPort 6185 -State Listen
```
