# Cyber-Butler Security (CBS)


## Status auf einen Blick

| Komponente | Status | Hinweis |
|---|---|---|
| SCM-Dienst, SQLite Schreiben/Lesen, Job Object | ✅ | |
| TOTP/Approval-Broker 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| WFP-Ausgangsblockierung — nur Audit | ⚠️ | |
| OTP Mailer 8766 / AuxRuntime 5099 | ✅ | |
| 6199 AgentProtocol-Adapter — manuell konfigurieren | ❌ | |
| Light-Stufe — Installation bestanden; geringere Isolation | ✅ | |
Eine defensive Kontrollebene für selbst gehostete LLM-Agenten.

## Schnellstart

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAgentRuntime`; port 6185 must listen.

## High-Architektur: nativer Windows-SCM-Dienst

AgentRuntime läuft als nativer SCM-Dienst `CyberButlerAgentRuntime` unter `CyberButlerSvc`. Die Binärdatei ist ACL-geschützt, interaktive Anmeldung ist gesperrt und ein Job Object steuert den Prozessbaum.

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AgentRuntime\data\logs\service-agentruntime.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## Stand dieser Version

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

## Bekannte Grenzen

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Die Light-Installation wurde auf einer realen Maschine bestanden; die Isolation ist schwächer als High. v1.6.2 hat keine Clean-VM-Abnahme. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## Dokumentation

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 ist kein Systemdienst von CBS/AgentRuntime; der Port wird vom AgentRuntime-AgentProtocol-Adapter nach Konfiguration und Aktivierung dynamisch geöffnet.

Der legacy S4U-Planungsaufgabenpfad ist stillgelegt; AgentRuntime darf nicht als Task-Scheduler-Aufgabe registriert werden.

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

