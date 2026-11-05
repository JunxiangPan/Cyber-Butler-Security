# Changelog

## v1.6.3 - 2026-11-05

### Breaking

- 签名格式升级为四文件签名，旧 `update-manifest.sig` 全部失效。
- `verify_release.py` 默认走新格式；旧格式必须显式使用 `--legacy`。

### Added

- `update-manifest.json` 增加 `signature_version: "2"`，用于客户端区分签名格式。

### Boundary

- CBS contains no third-party Agent runtime and does not own, support, certify, or endorse any specific third-party QQ client or unofficial ecosystem.
- Tests use synthetic external agents, not real third-party applications.

