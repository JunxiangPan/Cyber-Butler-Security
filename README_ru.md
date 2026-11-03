# Cyber-Butler Security (CBS)


## Статус с первого взгляда

| Компонент | Статус | Примечание |
|---|---|---|
| Служба SCM, чтение/запись SQLite, Job Object | ✅ | |
| Брокер TOTP/одобрения 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| Исходящая блокировка WFP — только аудит | ⚠️ | |
| OTP Mailer 8766 / SnowLuma 5099 | ✅ | |
| Адаптер OneBot 6199 — настроить вручную | ❌ | |
| Уровень Light — без приёмки на реальной машине | ❌ | |
Защитная плоскость управления для самостоятельно размещённых LLM-агентов.

## Быстрый старт

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAstrBot`; port 6185 must listen.

## Архитектура High: собственная служба Windows SCM

AstrBot работает как собственная служба SCM `CyberButlerAstrBot` под `CyberButlerSvc`. Бинарный файл защищён ACL, интерактивный вход запрещён, а Job Object управляет деревом процессов.

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AstrBot\data\logs\service-astrbot.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## Состояние этого выпуска

| Item | State |
|---|---|
| SCM service 6185 | verified on host |
| SQLite write probe | passed |
| Broker 18090 | listening |
| WebUI 8765 / OTP 8766 | listening |
| SnowLuma 5099 | listening |
| WFP | audit-only, enforce not enabled |
| 6199 | dynamic OneBot adapter port, not a service |
| Light / clean VM | not accepted yet |

Canonical source: [`docs/_data/status-v1.6.2.json`](docs/_data/status-v1.6.2.json).

## Порты

```text
6185  AstrBot SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  SnowLuma
6199  AstrBot OneBot adapter (dynamic; not a CBS service)
```

## Известные ограничения

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light has no real-machine acceptance, and v1.6.2 has no clean-VM acceptance. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## Документация

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 — не системная служба CBS/AstrBot; порт динамически открывается адаптером OneBot после настройки и включения.

Путь задачи S4U выведен из эксплуатации; не регистрируйте AstrBot как задачу планировщика.

- [FAQ — why not?](docs/00-overview/why-not-faq.md)
