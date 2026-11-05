# S4U → Windows SCM service: cross-language audit (v1.6.2)

## Contents

- [Canonical policy](#canonical-policy)
- [Eight-language README inventory](#eight-language-readme-inventory)
- [Cross-language checks](#cross-language-checks)
- [Remaining S4U word occurrences](#remaining-s4u-word-occurrences)

## Canonical policy

High-tier AgentRuntime is a native Windows SCM service named `CyberButlerAgentRuntime`, running as `CyberButlerSvc`. The S4U scheduled-task path is retired. S4U is documented only as a rejected/deprecated historical path, never as a supported deployment mode. The service binary ACL is `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`; `SeDenyInteractiveLogonRight` is restored. The wrapper uses absolute paths, Session 0 GUI-disabled settings, `AgentRuntime\data\logs\service-agentruntime.log`, and a Job Object.

## Eight-language README inventory

| File | Service section | Notes |
|---|---|---|
| README.md | present | service section, S4U deprecation note |
| README_en.md | present | service section, S4U deprecation note |
| README_zh.md | present | service section, S4U deprecation note |
| README_de.md | present | service section, S4U deprecation note |
| README_es.md | present | service section, S4U deprecation note |
| README_fr.md | present | service section, S4U deprecation note |
| README_ja.md | present | service section, S4U deprecation note |
| README_ko.md | present | service section, S4U deprecation note |
| README_ru.md | present | service section, S4U deprecation note |

## Cross-language checks

- All eight README files contain the service name `CyberButlerAgentRuntime`.
- All eight state that S4U is retired, not supported.
- The English and Chinese READMEs explicitly explain the local non-domain Task Scheduler limitation and the SYSTEM-launcher privilege-escalation risk.
- `SECURITY.md` uses the SCM service in the High-account row.
- `installer/README.md` describes the SCM service, not S4U.
- `docs/TROUBLESHOOTING.md` section 13 was rewritten for SCM service failures; its scheduled-task diagnostics were removed.
- Historical v1.6.1 release notes mark S4U/password fallback as superseded by v1.6.2.

## Remaining S4U word occurrences

Intentional occurrences after cleanup are limited to:

```text
the retired/deprecated historical note
the explicit "not supported" statements
```

There must be no instruction telling users to configure or register S4U.
