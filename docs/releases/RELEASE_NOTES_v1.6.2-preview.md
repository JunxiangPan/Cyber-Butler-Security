> **Historical / superseded.** This file is retained for history only. The current release is `docs/releases/RELEASE_NOTES_v1.6.2.md` (SCM service release). Do not use this preview as current installation guidance.

# v1.6.2 — Advanced Protection

> Release candidate notes. Native WFP filter and full audit-chain replacement
> remain tracked in `docs/TEST_MATRIX.md`; this file does not upgrade them to
> completed claims.

## New features

- **Advanced Protection: Critical file tampering prevention and AI intent mismatch detection.**
- Content-aware approval preview: bounded diff, secret redaction, script
  warning, and magic-byte checks for Shebang / PE / ELF regardless of extension.
- Intent mismatch warning when the agent's reason mentions test/UI/CSS/format
  but the target is a config, credential, secret, or protected test file.
- Hard deny for critical integrity files (`conftest.py`, `pytest.ini`,
  `.github/workflows/*`, `Makefile`, `package.json`, `pyproject.toml`,
  `.claude/settings.json`) with `TEST_TAMPERING_ATTEMPT` audit events.
- Hard deny for CBS policy, audit, quarantine, and installer/test directories
  with `RULE_TAMPERING_ATTEMPT` audit events.
- High-tier installer ACL protection for test files, with `icacls` write/delete
  deny for the service account.
- Credential proxy: the agent can hold a fake token while the loopback proxy
  injects the real key upstream.
- External-read audit: recent web/file/tool reads add an objective HITL warning
  to the TOTP approval preview.
- TOCTOU handle binding, quarantine, TOTP rate limiting, denial jitter, Job
  Object limits, WFP audit-only policy, port guard, SBOM bundle, fallback
  watchdog, and physical-separation banner.

## Not claimed complete

```text
native WFP filter API (FwpmEngineOpen0 / FwpmFilterAdd0)
full replacement of every legacy audit write with audit_chain
Light real-machine acceptance
formal signed release
```
