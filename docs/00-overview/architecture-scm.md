> Historical document. S4U and Task Scheduler are legacy/deprecated; retained for migration context only.

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
Service: CyberButlerAgentRuntime
Account: CyberButlerSvc
Binary:  <InstallPath>\tools\service\CyberButlerAgentRuntimeService.exe
Log:     <InstallPath>\AgentRuntime\data\logs\service-agentruntime.log
```

## Service wrapper properties

- Absolute Python and working-directory paths.
- Session 0 / GUI fail-closed environment (`AgentRuntime_SERVICE_MODE`, `AgentRuntime_DISABLE_GUI`, `QT_QPA_PLATFORM=offscreen`, `MPLBACKEND=Agg`, empty `DISPLAY`).
- stdout and stderr redirected to one log.
- machine-readable startup lines: account, cwd, workdir, root, child PID, Job Object assignment.
- `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`; descendants are killed when the service stops.
- data-directory write probe before launching AgentRuntime.

## Security boundary

```text
CyberButlerAgentRuntimeService.exe:
  CyberButlerSvc:RX
  SYSTEM:F
  Administrators:F
```

`SeDenyInteractiveLogonRight` is restored for `CyberButlerSvc`. Service logon uses `SeServiceLogonRight`, so interactive logon is not required.

## Operational checks

```powershell
Get-Service CyberButlerAgentRuntime
Get-CimInstance Win32_Service -Filter "Name='CyberButlerAgentRuntime'" |
  Select-Object Name,State,StartName,ProcessId
Get-NetTCPConnection -LocalPort 6185 -State Listen
```
