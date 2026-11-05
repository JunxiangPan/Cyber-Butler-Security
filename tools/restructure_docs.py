from pathlib import Path
import json

base = Path('docs')
for d in ['_data', '00-overview', '10-security', '20-operations', '30-development', '40-history/incidents', '40-history/legacy-readmes', '90-audit']:
    (base / d).mkdir(parents=True, exist_ok=True)

status = {
    "version": "1.6.2",
    "generated_for": "v1.6.2-rc2",
    "completed": [
        "AgentRuntime runs as native Windows SCM service CyberButlerAgentRuntime",
        "AgentRuntime 6185 listening; SQLite write probe succeeded",
        "Job Object KILL_ON_JOB_CLOSE covers the child tree",
        "TOTP Broker 18090 listening",
        "Cyber-Butler Web UI 8765 listening",
        "OTP Mailer 8766 listening",
        "AuxRuntime 5099 listening",
        "WFP Guard runs as SYSTEM in audit mode; wfp-guard-status.json ok=true"
    ],
    "not_completed": [
        "WFP enforce mode is not enabled; applied=0 in audit mode",
        "Native WFP filter API (FwpmEngineOpen0/FwpmFilterAdd0) is not implemented",
        "Light tier has no real-machine acceptance",
        "No clean-VM full install/uninstall acceptance for v1.6.2-rc2",
        "Credential Proxy is not fully installer/service integrated",
        "Full audit-chain replacement of legacy AUDIT writes is incomplete"
    ],
    "ports": {
        "6185": "AgentRuntime SCM service (CyberButlerAgentRuntime)",
        "18090": "TOTP Broker (SYSTEM task)",
        "8765": "WebUI (desktop task)",
        "8766": "OTP Mailer (desktop task)",
        "5099": "AuxRuntime (desktop task)",
        "6199": "Dynamic AgentRuntime AgentProtocol adapter port, not a system service"
    },
    "service": {
        "name": "CyberButlerAgentRuntime",
        "account": "CyberButlerSvc",
        "binary_acl": "CyberButlerSvc:RX, SYSTEM:F, Administrators:F",
        "interactive_logon": "denied",
        "log": "AgentRuntime\\data\\logs\\service-agentruntime.log"
    }
}
(base / '_data/status-v1.6.2.json').write_text(json.dumps(status, indent=2, ensure_ascii=False) + '\n', encoding='utf-8')

files = {}
files['00-overview/project-overview.md'] = """# Project overview

Cyber-Butler Security (CBS) is a defensive control plane for self-hosted LLM agents. It provides installer-driven isolation, TOTP approvals, a local broker, network guard scaffolding, and operational diagnostics.

## Scope

- Windows 10/11 x64, PowerShell 5.1, Python 3.10-3.13.
- High tier: dedicated local service account, native SCM service, ACL-separated data, TOTP approval.
- Medium/Light: reduced isolation; not equivalent to High.

## Non-goals

- Not a sandbox for arbitrary untrusted code.
- Not a replacement for OS patching, EDR, backups, or human review.
- Not a guarantee that an agent cannot exfiltrate data through every possible channel.

## Canonical status

The single source of truth is [`docs/_data/status-v1.6.2.json`](../_data/status-v1.6.2.json). The eight language README files mirror that status and must not invent different completion claims.
"""
files['00-overview/architecture-scm.md'] = """# High-tier architecture: native Windows SCM service

## Why the SCM service replaced S4U

On this local non-domain Windows host, Task Scheduler rejected both local-account S4U registration and Password registration with `Access is denied` / `username or password incorrect`. A `runas` test proved the account and password were valid. The temporary SYSTEM-launcher workaround was rejected because it creates a SYSTEM parent process and a privilege-escalation surface.

High tier therefore uses a native Windows service:

```text
Service: CyberButlerAgentRuntime
Account: CyberButlerSvc
Binary:  <InstallPath>\\tools\\service\\CyberButlerAgentRuntimeService.exe
Log:     <InstallPath>\\AgentRuntime\\data\\logs\\service-agentruntime.log
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
"""
files['00-overview/quickstart.md'] = """# Quick start

1. Use a clean Windows 10/11 x64 machine with administrator rights.
2. Run `START-INSTALLER.exe` as administrator.
3. Choose the install path, tier (High recommended for isolation testing), WebUI bind = Loopback, and personal plugin path.
4. Leave the API key blank unless a key file is explicitly prepared.
5. At the TOTP step scan the QR and save the recovery codes offline.
6. After installation verify:

```powershell
Get-Service CyberButlerAgentRuntime
Get-NetTCPConnection -State Listen |
  Where-Object { $_.LocalPort -in 6185,18090,8765,8766,5099 }
```

See `../20-operations/ports-and-adapters.md` for each port.
"""
files['00-overview/glossary.md'] = """# Glossary

| Term | Meaning |
|---|---|
| CBS | Cyber-Butler Security, the control plane in this repository |
| SCM | Windows Service Control Manager; hosts `CyberButlerAgentRuntime` |
| S4U | Service-for-User Task Scheduler logon; retired for AgentRuntime on this host |
| WFP | Windows Filtering Platform; current guard writes audit status, not a native filter |
| Broker | Local TOTP/approval HTTP service on 18090 |
| AgentProtocol adapter | AgentRuntime platform adapter; it dynamically opens 6199 |
| Job Object | Windows kernel object used to kill the whole child tree |
"""
files['10-security/defense-layers.md'] = """# Defense layers

| Layer | Control | Current state |
|---|---|---|
| Account isolation | `CyberButlerSvc` + `SeDenyInteractiveLogonRight` | implemented |
| Service hosting | SCM service `CyberButlerAgentRuntime` | implemented and host-tested |
| Binary integrity | service binary ACL `Svc:RX / SYSTEM:F / Administrators:F` | implemented |
| Process tree | Job Object `KILL_ON_JOB_CLOSE` | implemented |
| Data split | sensitive subdirectories read-only; runtime DB root writable | implemented with host repair |
| TOTP approval | local Broker 18090 | implemented |
| Network policy | WFP Guard audit mode | not enforcement |
| Audit | JSONL / audit_chain sidecar | partial replacement only |
| Credential proxy | fake token / loopback injection | module exists, not fully installer-integrated |

## Non-claims

This release does not claim a native WFP filter, full audit-chain replacement, Light real-machine acceptance, or clean-VM acceptance.
"""
files['10-security/scm-service-hardening.md'] = """# SCM service hardening

## Required binary ACL

```text
CyberButlerAgentRuntimeService.exe
  CyberButlerSvc:RX
  SYSTEM:F
  Administrators:F
```

The service directory must not be writable by `CyberButlerSvc` or by a desktop user.

## Required account rights

```text
SeServiceLogonRight
SeBatchLogonRight
SeDenyInteractiveLogonRight
```

`SeDenyInteractiveLogonRight` is restored after service creation. The SCM service does not require interactive logon.

## Runtime environment

The wrapper sets:

```text
AgentRuntime_SERVICE_MODE=1
AgentRuntime_ROOT=<install root>
AgentRuntime_DISABLE_GUI=1
NO_GUI=1
PYTHONUTF8=1
PYTHONIOENCODING=utf-8
MPLBACKEND=Agg
QT_QPA_PLATFORM=offscreen
DISPLAY=
```

Any GUI initialization must fail closed in Session 0, not block on a desktop.
"""
files['10-security/wfp-network-policy.md'] = """# WFP / Windows Firewall guard

## Current mode

```text
mode: audit
applied: 0
status: wfp-guard-status.json ok=true
```

The guard runs as SYSTEM. It validates the service SID, reads `webui\\data\\network-policy.json`, and writes status. Audit mode does **not** install block rules.

## Why enforcement is not enabled

- The native WFP filter API (`FwpmEngineOpen0` / `FwpmFilterAdd0`) is not implemented.
- Firewall rule cleanup previously failed on an empty rule set; the guard now checks for matching rules before removing them.
- Enforce mode has not passed real-machine pressure or recovery testing.
- A failed firewall update must not silently leave a deny-all state.

## Do not claim

Do not describe v1.6.2 as "WFP enforced" or "network default-deny validated". It is audit-only.
"""
files['10-security/known-limitations.md'] = """# Known limitations (v1.6.2-rc2)

This file is the authoritative list of current boundaries. It is linked from every language README.

## WFP enforce mode is not enabled

- Current policy mode: `audit`; `applied=0`.
- The native WFP filter path (`FwpmEngineOpen0` / `FwpmFilterAdd0`) is not implemented.
- The guard uses Windows Firewall rule scaffolding, not a kernel WFP filter.
- Enforce mode is blocked by: no real-machine pressure test, no clean recovery test for a failed rule update, and no proof that a deny-all state cannot survive a crash.
- Do **not** claim default-deny enforcement.

## Light tier

Light has no real-machine acceptance. It is not a substitute for High.

## Clean VM acceptance

v1.6.2-rc2 has not completed a clean-VM install/upgrade/uninstall run. Host-side SCM validation passed on one machine only.

## 6199 is not a service

`6199` is opened dynamically by the AgentRuntime AgentProtocol adapter after the adapter is configured and enabled. It is not a CBS or AgentRuntime system service.

## Other partial controls

- Credential Proxy exists but is not fully integrated into the installer/service lifecycle.
- Full replacement of legacy audit writes with `audit_chain` is incomplete.
- Native WFP filtering remains unimplemented.
- Full clean install of the SCM installer branch has not been re-run end-to-end.

## What is verified

AgentRuntime SCM service, 6185, SQLite write probe, Job Object assignment, Broker 18090, WebUI 8765, OTP Mailer 8766, AuxRuntime 5099, and WFP audit status on the current host.
"""
for rel, text in files.items():
    (base / rel).write_text(text, encoding='utf-8')

incidents = {
's4u-retirement.md': """# Incident: S4U retirement

## Symptom

Task Scheduler returned `Access is denied` for S4U registration and `username or password incorrect` for Password registration, even though `runas` opened cmd with the same account.

## Alternatives predicted and abandoned

1. **S4U scheduled task** - theoretically best: no stored password, service account, Task Scheduler. Rejected because local non-domain Windows refused registration.
2. **Password scheduled task** - rejected because Task Scheduler still failed authentication and High's interactive-logon deny conflicts with the task logon model.
3. **SYSTEM launcher** - works, but creates a SYSTEM parent process and a privilege-escalation surface. Rejected.
4. **Medium desktop account** - works, but removes High isolation. Rejected for High.

## Resolution

Native SCM service `CyberButlerAgentRuntime` running as `CyberButlerSvc`, with a locked binary ACL and SCM-managed recovery.
""",
'sqlite-readonly.md': """# Incident: SQLite readonly under High isolation

## Symptom

`sqlite3.OperationalError: attempt to write a readonly database` or `unable to open database file` while AgentRuntime started under the service account.

## Root causes found

- High's data ACL initially made the data root read-only; SQLite needs to create `-wal` and `-shm` beside the database.
- A stale broad `Everyone: DeleteSubdirectoriesAndFiles` deny on the install root was inherited by data.
- The service's first binary did not write a probe before launching Python, so the failure looked silent in Task Scheduler.

## Alternatives predicted and abandoned

- Move the DB into a writable subdirectory: rejected because AgentRuntime's database path is fixed at `data\\data_v4.db`.
- Run AgentRuntime as SYSTEM: rejected, loses High isolation.
- Use Medium: works but not High.
- Replace the DB file with a copy: rejected as unsafe without a consistent SQLite backup; the final design keeps the existing data and grants the service account write/delete on the data root.

## Resolution

Data write probe in the service wrapper; SQLite write test; data ACL repair; SCM service starts AgentRuntime and 6185 listens.
""",
'wfp-empty-rules.md': """# Incident: WFP empty-rule Remove failure

## Symptom

`WFP policy apply failed: Remove-NetFirewallRule failed` on every watch cycle.

## Cause

`Get-NetFirewallRule ... | Remove-NetFirewallRule` was executed even when no matching rules existed. An empty pipeline makes the remove call fail.

## Alternatives predicted and abandoned

- Ignore all errors: rejected, would hide real permission failures.
- Disable WFP Guard: rejected, removes audit evidence.
- Enable enforce mode immediately: rejected, no pressure/recovery test and no native filter.

## Resolution

Check rule count first; only call `Remove-NetFirewallRule` when rules exist. Guard remains audit-only. Current status: `ok=true`, `applied=0`.
""",
'acl-self-lock.md': """# Incident: ACL self-lock

## Symptom

After hardening, administrators could not read/replace the service task or task binary; `Register-ScheduledTask` returned access denied even after `takeown` of the task file.

## Cause

Task definition and directory ACLs were changed without preserving the administrators/SYSTEM management path; a running service also locked its binary.

## Alternatives predicted and abandoned

- Delete the service/task without backup: rejected.
- Run everything as SYSTEM: rejected.
- Add Everyone full control: rejected, privilege escalation.

## Resolution

Stop the SCM service before replacing the binary; keep administrators/SYSTEM full control of the service directory; use a dedicated read-only service binary ACL for `CyberButlerSvc`. Task rollback preserves the AgentRuntime service definition on assertion failure.
""",
'task-rollback.md': """# Incident: task rollback deleted the diagnostic target

## Symptom

After a Services assertion failure, `AgentRuntime Service` disappeared from Task Scheduler, so the failure could not be reproduced or inspected.

## Cause

The rollback unconditionally unregistered tasks created during the install.

## Alternatives predicted and abandoned

- Keep every task: rejected for other components that may be broken.
- Keep no tasks and reinstall: rejected, loses evidence.
- Manual task creation: rejected, service account password was not recoverable.

## Resolution

`Undo-CyberButlerServices` now accepts `KeepTaskDefinitions`; the Services failure path keeps `AgentRuntime Service` (now the SCM service definition) and only stops processes/ports.
"""
}
for name, text in incidents.items():
    (base / '40-history/incidents' / name).write_text(text, encoding='utf-8')

print('canonical + incidents written')
