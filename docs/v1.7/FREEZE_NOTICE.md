# CONTRACT v1.7.1 FREEZE NOTICE

Status: **FROZEN — contract only; no product release.**

```text
Contract tag: contract-v1.7.1
Contract SHA256: 209d75b4c900f9a2d1ad8f5c377ac1b8a868cf3e4cd449970e61e3ff380c18f1
Freeze baseline: 6835789
Freeze date: 2026-11-09
```

CONTRACT.md was not changed after RC2. The freeze record only updates
`RC_STATUS.md`, `CHANGELOG.md`, and this notice.

## Consumers

### CBE

- Pin the frozen contract tag/hash.
- Update the CBE-08 contract guard to this hash.
- CBE-08 remains **DRAFT**; do not report PASS.
- CBE 0.1.0 must emit `schema_version: "1"` and support `NOT_UPLOADED`.

### CBP

- Pin the frozen contract tag/hash.
- CBP 1.2.2 must emit the object `artifact_repository`, `ci_commit_sha`, and the
  canonical body hash.
- CBP 1.2.0/1.2.1 remain legacy fixtures; do not rewrite their evidence.

### CBM / CBC

- Consume the frozen schema.
- `NOT_UPLOADED` is valid status but never PASS.
- B1/B2 remain blocked until CBE/CBP emit subject-scoped reports.

## Immutability

```text
Do not edit CONTRACT.md.
Do not move contract-v1.7.1.
Do not rewrite published evidence.
```

No `v1.7.0` product tag, signature, or release was created.
