# Changelog

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
