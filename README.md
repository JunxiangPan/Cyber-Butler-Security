# Cyber-Butler Security (CBS)


## Release verification

CBS release packages pass the Cyber-Butler-Pipeline (CBP) baseline gates, but this does not prove that the code is absolutely secure. CBP is a consistency check for common low-level errors and obvious fabrication; it cannot stop a privileged operator from bypassing the process or replace independent security review.

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


## Community acknowledgements

CBS's architecture is not a solo invention: it was shaped by the global open-source community. See [CONTRIBUTORS.md](CONTRIBUTORS.md) for the full list of red-team critics, product reviewers, and community supporters.

## Documentation

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

## Current release

v1.6.3: AgentRuntime is a native SCM service `CyberButlerAgentRuntime` under `CyberButlerSvc`; 6185/18090/8765/8766/5099 are verified on the host. WFP remains audit-only, 6199 is a dynamic AgentProtocol adapter port, and Light installation passed on a real machine with reduced isolation. Canonical facts: [status-v1.6.2.json](docs/_data/status-v1.6.2.json).

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


## Private vulnerability reporting

Use GitHub Security Advisories: <https://github.com/JunxiangPan/Cyber-Butler-Security/security/advisories/new>. Do not file a public issue for an unfixed vulnerability.

## Quality gates

Cyber-Butler-Security uses [CBP](https://github.com/<YOUR_GITHUB_USER>/cbp-action) to enforce quality gates.
CBP is packaged from `cbp-action/` and consumed here as a pinned, hashed wheel.

