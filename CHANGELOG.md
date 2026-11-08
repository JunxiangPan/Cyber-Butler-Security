# Changelog

## v1.6.6 - 2026-11-09

### Added

- Real VM acceptance with live phone TOTP; test TOTP fallback removed.
- Signed GitHub release with four-file signature, `signing-report.json`, `RELEASE_ASSETS.sha256`.
- CBP 1.1.0 pin with scoped encoding allowlist.
- Pester 3.4 under Windows PowerShell 5.1 for installer tests.

### Fixed

- Release artifact staging now includes the 51 MB zip in the uploaded artifact.
- Restored `offline_hash_install.py`, `prebuild_freeze.py`, `signing_report.py`.
- QA report now records coverage substitution explicitly.

### Boundary

- Q05–Q17 were not individually re-executed for v1.6.6; they are covered by the real VM acceptance proof. This is coverage substitution, not a full 26/26 rerun.
- Broker coverage is 46% and remains known v1.6.6 debt; v1.7 restores the hard gate.
- Release: https://github.com/JunxiangPan/Cyber-Butler-Security/releases/tag/v1.6.6

## v1.6.3 - 2026-11-05

### Breaking

- 签名格式升级为四文件签名，旧 `update-manifest.sig` 全部失效。
- `verify_release.py` 默认走新格式；旧格式必须显式使用 `--legacy`。

### Added

- `update-manifest.json` 增加 `signature_version: "2"`，用于客户端区分签名格式。

### Boundary

- CBS contains no third-party Agent runtime and does not own, support, certify, or endorse any specific third-party QQ client or unofficial ecosystem.
- Tests use synthetic external agents, not real third-party applications.

