# v1.6.2-beta — 实机验证包（未签名）

> **Beta only.** This is not a formal signed release. Do not publish it as
> v1.6.2 final until the native WFP filter path and Light real-machine gates are
> complete.

## Included in this beta

- TOCTOU handle binding and quarantine for destructive deletes.
- Deterministic approval previews: bounded diff, script warning, redaction.
- TOTP request token bucket and denial jitter.
- Explicit ACL on newly created high-risk files.
- Job Object memory/CPU/process limits (generous defaults; no BREAKAWAY).
- Port 18090 listener check.
- WFP-backed audit-only policy path and firewall-log Tripwire.
- Audit chain sidecar mirror, watchdog fail-closed, physical-separation banner.
- Installer physical-separation checkbox.
- WebUI network allowlist form and `/api/security/network-policy`.

## Known gaps

```text
native WFP filter API (FwpmEngineOpen0 / FwpmFilterAdd0) is NOT complete
audit_chain is a sidecar mirror, not yet a replacement for every legacy write
Light real-machine acceptance is NOT complete
v1.6.2 package is unsigned
```

## Test baseline

```text
pytest: 132 passed, 1 skipped (before this beta packaging)
Pester: 144 passed
privacy scan: OK
```

Use `docs/TEST_MATRIX.md` as the authoritative gap list. High real-machine WFP
testing must be completed before any enforce mode is enabled.
