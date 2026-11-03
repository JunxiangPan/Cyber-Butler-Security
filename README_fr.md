# Cyber-Butler Security (CBS)


## État en un coup d’œil

| Composant | État | Note |
|---|---|---|
| Service SCM, lecture/écriture SQLite, Job Object | ✅ | |
| Broker TOTP/approbation 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| Blocage sortant WFP — audit uniquement | ⚠️ | |
| OTP Mailer 8766 / SnowLuma 5099 | ✅ | |
| Adaptateur OneBot 6199 — à configurer manuellement | ❌ | |
| Niveau Light — aucune validation matérielle | ❌ | |
Plan de contrôle défensif pour agents LLM auto-hébergés.

## Démarrage rapide

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAstrBot`; port 6185 must listen.

## Architecture High : service SCM Windows natif

AstrBot s’exécute comme service SCM natif `CyberButlerAstrBot` sous `CyberButlerSvc`. Le binaire est protégé par ACL, la connexion interactive est refusée et un Job Object gère l’arbre de processus.

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AstrBot\data\logs\service-astrbot.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## État de cette version

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

## Ports

```text
6185  AstrBot SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  SnowLuma
6199  AstrBot OneBot adapter (dynamic; not a CBS service)
```

## Limites connues

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light has no real-machine acceptance, and v1.6.2 has no clean-VM acceptance. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## Documentation

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 n’est pas un service système CBS/AstrBot ; il est ouvert dynamiquement par l’adaptateur OneBot d’AstrBot après configuration et activation.

La voie de tâche planifiée S4U est retirée ; ne pas enregistrer AstrBot comme tâche du Planificateur.

- [FAQ — why not?](docs/00-overview/why-not-faq.md)
