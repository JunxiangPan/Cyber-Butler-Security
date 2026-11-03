> **Historical / superseded.** This file is retained for history only. The current release is `docs/releases/RELEASE_NOTES_v1.6.2.md` (SCM service release). Do not use this preview as current installation guidance.

# v1.6.2-rc — Release Candidate (unsigned)

> **RC only.** Not a formal signed release. Native WFP filter and full audit
> chain replacement remain blockers; see below.

## Included

- TOCTOU handle-bound approvals and quarantine for destructive deletes.
- Deterministic approval preview: bounded diff, script warning, redaction.
- TOTP token bucket and denial jitter.
- Explicit ACL for new high-risk files; quarantine ACL is SYSTEM/Administrators.
- Job Object memory/CPU/process limits with generous defaults; no BREAKAWAY.
- Port 18090 listener ownership check.
- WFP-backed audit-only firewall policy, tripwire log parser, status file.
- Audit chain sidecar mirror with process lock.
- Watchdog fail-closed and physical-separation banner.
- Installer physical-separation checkbox; WebUI network allowlist form.
- Atomic `network-policy.json` writes with CSRF protection.

## Blocking gaps

```text
native WFP filter (FwpmEngineOpen0 / FwpmFilterAdd0) not implemented
audit chain is a sidecar mirror, not a full replacement of every legacy write
Light real-machine acceptance not run
RC is unsigned
```

## Test baseline

```text
pytest: 132 passed, 1 skipped
Pester: 144 passed (run separately)
privacy scan: OK
```
