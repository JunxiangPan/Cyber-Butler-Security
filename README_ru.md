# Cyber-Butler Security (CBS)


## Статус с первого взгляда

| Компонент | Статус | Примечание |
|---|---|---|
| Служба SCM, чтение/запись SQLite, Job Object | ✅ | |
| Брокер TOTP/одобрения 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| Исходящая блокировка WFP — только аудит | ⚠️ | |
| OTP Mailer 8766 / AuxRuntime 5099 | ✅ | |
| Адаптер AgentProtocol 6199 — настроить вручную | ❌ | |
| Уровень Light — установка пройдена; изоляция слабее | ✅ | |
Защитная плоскость управления для самостоятельно размещённых LLM-агентов.

## Быстрый старт

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAgentRuntime`; port 6185 must listen.

## Архитектура High: собственная служба Windows SCM

AgentRuntime работает как собственная служба SCM `CyberButlerAgentRuntime` под `CyberButlerSvc`. Бинарный файл защищён ACL, интерактивный вход запрещён, а Job Object управляет деревом процессов.

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AgentRuntime\data\logs\service-agentruntime.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## Состояние этого выпуска

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

## Порты

```text
6185  AgentRuntime SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  AuxRuntime
6199  AgentRuntime AgentProtocol adapter (dynamic; not a CBS service)
```

## Известные ограничения

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Установка Light прошла на реальной машине; изоляция слабее, чем в High. Для v1.6.2 нет приёмки на чистой VM. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## Документация

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 — не системная служба CBS/AgentRuntime; порт динамически открывается адаптером AgentProtocol после настройки и включения.

Путь задачи legacy S4U выведен из эксплуатации; не регистрируйте AgentRuntime как задачу планировщика.

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

