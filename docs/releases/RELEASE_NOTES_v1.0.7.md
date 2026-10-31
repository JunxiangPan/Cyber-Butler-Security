# v1.0.7 — Safe Upgrade Pipeline

## Added

- `tools/check_update.ps1`: read-only GitHub latest-release check, no admin required.
- `tools/update.ps1`: administrator-only, explicitly confirmed update with GitHub asset SHA-256, manifest hash validation, code-only replacement, backup, restart, health checks and code rollback.
- `tools/update_core.py`: dependency-free path allowlist, manifest validation and safe zip extraction.
- `tools/build_update_manifest.py`: release manifest generator.
- `tests/test_update_safety.py`: data/config rejection, zip-slip rejection, hash mismatch and user-data preservation.
- README “How to Upgrade Safely” and a SECURITY.md auto-update threat-model section.

## Update contract

- v1.0.6 remains a manual-upgrade package.
- v1.0.7 is the first release carrying `update-manifest.json`.
- Automatic checking + QQ notification is allowed.
- Automatic silent code replacement is forbidden.
- No GPG/minisign publisher signature yet: GitHub asset SHA-256 + manifest hashes only.

## Verification

```text
26 passed
```
