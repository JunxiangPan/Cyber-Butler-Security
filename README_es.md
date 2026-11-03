# Cyber-Butler Security (CBS)


## Estado de un vistazo

| Componente | Estado | Nota |
|---|---|---|
| Servicio SCM, lectura/escritura SQLite, Job Object | ✅ | |
| Broker TOTP/aprobación 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| Bloqueo saliente WFP — solo auditoría | ⚠️ | |
| OTP Mailer 8766 / SnowLuma 5099 | ✅ | |
| Adaptador OneBot 6199 — configurar manualmente | ❌ | |
| Nivel Light — instalación superada; aislamiento reducido | ✅ | |
Plano de control defensivo para agentes LLM autoalojados.

## Inicio rápido

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAstrBot`; port 6185 must listen.

## Arquitectura High: servicio SCM nativo de Windows

AstrBot se ejecuta como servicio SCM nativo `CyberButlerAstrBot` con `CyberButlerSvc`. El binario está protegido por ACL, el inicio de sesión interactivo está denegado y un Job Object controla el árbol de procesos.

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AstrBot\data\logs\service-astrbot.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## Estado de esta versión

| Item | State |
|---|---|
| SCM service 6185 | verified on host |
| SQLite write probe | passed |
| Broker 18090 | listening |
| WebUI 8765 / OTP 8766 | listening |
| SnowLuma 5099 | listening |
| WFP | audit-only, enforce not enabled |
| 6199 | dynamic OneBot adapter port, not a service |
| Light install / clean VM | ✅ install; clean VM not accepted |

Canonical source: [`docs/_data/status-v1.6.2.json`](docs/_data/status-v1.6.2.json).

## Puertos

```text
6185  AstrBot SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  SnowLuma
6199  AstrBot OneBot adapter (dynamic; not a CBS service)
```

## Limitaciones conocidas

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. La instalación Light se superó en una máquina real; el aislamiento es más débil que High. v1.6.2 no tiene aceptación en VM limpia. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## Documentación

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 no es un servicio del sistema de CBS/AstrBot; lo abre dinámicamente el adaptador OneBot de AstrBot tras configurarlo y activarlo.

La ruta de tarea programada S4U está retirada; no registres AstrBot como tarea del Programador.

- [FAQ — why not?](docs/00-overview/why-not-faq.md)
