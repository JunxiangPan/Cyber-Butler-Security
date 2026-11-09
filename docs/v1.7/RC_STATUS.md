# v1.7.1 Contract RC Status

Status: **FROZEN**

Freeze date: `2026-11-09`

Freeze baseline commit: `6835789`

Tag: `contract-v1.7.1` (contract tag, not a product tag)

Contract file: `docs/v1.7/CONTRACT.md`

Contract SHA256:

```text
209d75b4c900f9a2d1ad8f5c377ac1b8a868cf3e4cd449970e61e3ff380c18f1
```

This hash is frozen. CONTRACT.md was not changed between RC2 and this freeze.
Do not edit CONTRACT.md after this commit.

## Included in this RC2

- F2 blocking set (three structural checks + `gate: "blocking"` rules).
- §5.1 report identity (`package_id` = subject, `producer_id` = producer).
- §5.2 bare 64-character lowercase hashes; `sha256:` prefixes are input errors.
- §5.3 body hash binding uses the CBP 1.2.1 canonical function and CBP-BODY-001.
- `body_hash_scope: "base"`.
- `artifact_repository` object coordinates.
- `schema_version` is string `"1"`; `NOT_UPLOADED` is a valid gate status.
- quality manifest requires `ci_commit_sha`; accepts `ci_run_id` / `generated_at` / `generated_by`.
- CBM/CBC body fragments with `NOT_UPLOADED` + `EVIDENCE_ABSENT`.
- Real JSON Schema validation with `jsonschema`.
- `tests/v17/fixtures/real-cbe-report.json` passes.
- CBE 0.1.0 real report passes RC2 schema (confirmed by CBE).
- CBP 1.2.2 real manifest passes RC2 schema (confirmed by CBP); CBP 1.2.1 is
  retained only as a legacy FAIL fixture.
- CBP 1.2.0 is legacy and fails.
- 92 v1.7 tests passing locally.

## Post-freeze

- CONTRACT.md is immutable.
- The tag `contract-v1.7.1` is immutable.
- Published evidence is immutable.
- CBE-08 remains **DRAFT** until CBE updates its contract guard to this hash.
- No CBE/CBP/CBM/CBC repository edit was made by this freeze.
- No v1.7.0 product tag, signature, or release was created.
