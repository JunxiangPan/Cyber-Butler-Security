# Changelog

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
