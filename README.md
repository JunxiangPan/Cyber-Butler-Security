# Cyber-Butler Security (CBS)


## Status at a glance

| Component | Status | Note |
|---|---|---|
| SCM service, SQLite read/write, Job Object | ✅ | |
| TOTP/approval broker 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| WFP outbound blocking — audit only | ⚠️ | |
| OTP Mailer 8766 / SnowLuma 5099 | ✅ | |
| 6199 OneBot adapter — configure manually | ❌ | |
| Light tier — no real-machine acceptance | ❌ | |
Defensive control plane for self-hosted LLM agents. This file is the language selector; the English entry is `README_en.md`.

## Languages

- [English](README_en.md)
- [中文](README_zh.md)
- [Deutsch](README_de.md)
- [Español](README_es.md)
- [Français](README_fr.md)
- [日本語](README_ja.md)
- [한국어](README_ko.md)
- [Русский](README_ru.md)

## Documentation

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

## Current release

v1.6.2: AstrBot is a native SCM service `CyberButlerAstrBot` under `CyberButlerSvc`; 6185/18090/8765/8766/5099 are verified on the host. WFP remains audit-only, 6199 is a dynamic OneBot adapter port, and Light has no real-machine acceptance. Canonical facts: [status-v1.6.2.json](docs/_data/status-v1.6.2.json).

- [FAQ — why not?](docs/00-overview/why-not-faq.md)
