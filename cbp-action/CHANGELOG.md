# Changelog

## 0.1.8 — 2026-11-07

- Added ambiguous Windows-backslash path detection in .py/.ps1 files.
- Made required_artifacts mandatory whenever package_zip is configured.
- Documented that administrator/VM chaos tests are not proven by CI.
- Kept lcov/cobertura, Action SHA pinning, and ReDoS work deferred to P1/P2.

## 0.1.5 — 2026-11-07

- Added a built-in PowerShell AST syntax gate inside the custom gate.
- Added required-pattern support for CBP custom rules.
- Rejects malformed .ps1 files before deployment.
- Added required-artifact ZIP integrity, naked-subprocess, and Python PYTHONPATH checks.
- Fixed CBS journal status binding by rejecting the invalid warning status.

## 0.1.4 — 2026-11-07

- Added source-hash binding for coverage evidence; `touch` no longer bypasses freshness.
- Added baseline generation and inline suppression for existing findings.
- Fixed dead `enable_custom` / `enable_upgrade` switches and unknown-key fail-open.
- Added `gates_ran` and zero-gate FAIL semantics.
- Reduced comment false positives and made PowerShell 7 the supported runtime.

## 0.1.3 — 2026-11-07

- Removed `shell=True` from the upgrade gate; scripts are parsed with `shlex.split` and shell metacharacters are rejected.
- Rejected upgrade-script execution on `pull_request` and `pull_request_target` events.
- Added GitHub OIDC build provenance with `actions/attest-build-provenance`.
- Bumped the configuration schema to `0.1.3`; old `0.1.x` configs migrate in memory.

## 0.1.2 — 2026-11-06

- Added checked-in `docs/RELEASE_BODY.md`, validated by the claims gate and used by `gh release create`.
- Added SARIF 2.1.0 output via `--sarif-output`.
- Added the eighth `custom` gate for config-driven regex/literal rules (warn by default).
- Added optional `coverage.json.sha256` sidecar verification.
- Release body is included in the documentation hash manifest.

## 0.1.1 — 2026-11-06

- Added a strict UTF-8 no-BOM encoding gate (tracked text files only).
- Release claims now validate prose gate counts, not only `QUALITY_COUNTS`.
- Generated release notes use the actual gate count dynamically.
- Action path inputs are optional and fail closed only when their gate is enabled.
- `security_core` coverage now measures the actual gate modules.
- Documented checksum + run-id pinning instead of cryptographic-signature wording.
- CBP is distributed through GitHub Actions/Releases only; PyPI publication is not used.

## 0.1.0 — 2026-11-06

Initial standalone release candidate.

CBP was created after a release process trusted a green report that was not
backed by reproducible evidence: counts did not reconcile, a signing gate
matched a text marker, and blocked checks still allowed a package to ship.

This release turns those lessons into reusable gates:

- coverage with an explicit allowlist and real threshold
- pinned dependencies with hashes and `--require-hashes`
- public docstring, argument, generic-boilerplate, and slop-comment checks
- manifest-bound documentation history
- binary build/SBOM provenance and binary hash checks
- release-note claims reconciled against machine data
- `audit` and `enforce` modes
- GitHub Action and local CLI entry points
- Linux and Windows self-tests
### Scope

v0.1.5 is a P0/VM-guard release. P1/P2 items are deferred to v0.1.8.
