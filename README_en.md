# Cyber-Butler Security (CBS)


## Status at a glance

| Component | Status | Note |
|---|---|---|
| SCM service, SQLite read/write, Job Object | ✅ | |
| TOTP/approval broker 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| WFP outbound blocking — audit only | ⚠️ | |
| OTP Mailer 8766 / AuxRuntime 5099 | ✅ | |
| 6199 AgentProtocol adapter — configure manually | ❌ | |
| Light tier — install passed; reduced isolation | ✅ | |
A defensive control plane for self-hosted LLM agents.

## Quick start

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAgentRuntime`; port 6185 must listen.

## High architecture: native Windows SCM service

AgentRuntime runs as the native SCM service `CyberButlerAgentRuntime` under `CyberButlerSvc`. The service binary is ACL-locked, interactive logon is denied, and a Job Object owns the child tree.

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AgentRuntime\data\logs\service-agentruntime.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## State of this release

| Item | State |
|---|---|
| SCM service 6185 | verified on host |
| SQLite write probe | passed |
| Broker 18090 | listening |
| WebUI 8765 / OTP 8766 | listening |
| AuxRuntime 5099 | listening |
| WFP | audit-only, enforce not enabled |
| 6199 | dynamic AgentProtocol adapter port, not a service |
| Light install / clean VM | ✅ install; clean VM not accepted |

Canonical source: [`docs/_data/status-v1.6.2.json`](docs/_data/status-v1.6.2.json).

## Ports

```text
6185  AgentRuntime SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  AuxRuntime
6199  AgentRuntime AgentProtocol adapter (dynamic; not a CBS service)
```

## Known limitations

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light installation passed on a real machine; isolation is weaker than High. v1.6.2 has no clean-VM acceptance. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## Documentation

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 is not a CBS/AgentRuntime system service; it is opened dynamically by the AgentRuntime AgentProtocol adapter after configuration and enablement.

The legacy S4U scheduled-task path is retired; do not register AgentRuntime as a Task Scheduler task.

- [FAQ — why not?](docs/00-overview/why-not-faq.md)

## Signature format change (v1.6.3)

Starting with v1.6.3, `update-manifest.json` uses the four-file signature format
(manifest + BUILD_REPORT + FINAL_QA_REPORT + ACCEPTANCE_PROOF). Old v1.6.2 and
earlier signatures return INVALID under the new `verify_release.py`; use
`--legacy` only for explicit legacy verification.

## Boundary Statement

CBS is a generic local Agent approval and evidence layer.
It does not own, support, certify, or endorse any specific third-party QQ client or unofficial ecosystem.

CBS provides only a generic external Agent boundary.
Whether a third-party application uses CBS, how it integrates, and whether it is compliant, is the sole responsibility of the user.

CBS tests use synthetic external agents, not real third-party applications as fixtures.

