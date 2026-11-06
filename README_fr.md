# Cyber-Butler Security (CBS)


## Release verification

CBS release packages pass CBP baseline gates; this does not prove absolute security.

## État en un coup d’œil

| Composant | État | Note |
|---|---|---|
| Service SCM, lecture/écriture SQLite, Job Object | ✅ | |
| Broker TOTP/approbation 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| Blocage sortant WFP — audit uniquement | ⚠️ | |
| OTP Mailer 8766 / AuxRuntime 5099 | ✅ | |
| Adaptateur AgentProtocol 6199 — à configurer manuellement | ❌ | |
| Niveau Light — installation validée ; isolation réduite | ✅ | |
Plan de contrôle défensif pour agents LLM auto-hébergés.

## Démarrage rapide

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAgentRuntime`; port 6185 must listen.

## Architecture High : service SCM Windows natif

AgentRuntime s’exécute comme service SCM natif `CyberButlerAgentRuntime` sous `CyberButlerSvc`. Le binaire est protégé par ACL, la connexion interactive est refusée et un Job Object gère l’arbre de processus.

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AgentRuntime\data\logs\service-agentruntime.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## État de cette version

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

## Limites connues

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. L’installation Light a été validée sur une machine réelle ; l’isolation est plus faible que High. v1.6.2 n’a pas de validation sur VM propre. See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## Documentation

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 n’est pas un service système CBS/AgentRuntime ; il est ouvert dynamiquement par l’adaptateur AgentProtocol d’AgentRuntime après configuration et activation.

La voie de tâche planifiée legacy S4U est retirée ; ne pas enregistrer AgentRuntime comme tâche du Planificateur.

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

