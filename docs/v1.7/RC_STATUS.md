# v1.7.1 Contract RC Status

Status: **RC2 — NOT FROZEN**

Branch: `contract/v1.7.1`

Contract file: `docs/v1.7/CONTRACT.md`

Contract SHA256 (candidate):

```text
029b4ba6964631b38a03da1e569bb6a6d0d56817a588e34afcc2827c0a1f3f81
```

This hash is a review artifact. It is not a frozen contract, not a tag, and not
a release. Do not let CBE/CBP/CBM/CBC pin to it until the human freeze step.

## Included in this RC2

- F2 blocking set (three structural checks + `gate: "blocking"` rules).
- §5.1 report identity (`package_id` = subject, `producer_id` = producer).
- §5.2 bare 64-character lowercase hashes; `sha256:` prefixes are input errors.
- §5.3 body hash binding and CBP-BODY-001.
- `body_hash_scope: "base"`.
- `artifact_repository` object coordinates.
- `schema_version` is string `"1"`; `NOT_UPLOADED` is a valid gate status.
- quality manifest requires `ci_commit_sha`; accepts `ci_run_id` / `generated_at` / `generated_by`.
- CBM/CBC body fragments with `NOT_UPLOADED` + `EVIDENCE_ABSENT`.
- Real JSON Schema validation with `jsonschema`.
- `tests/v17/fixtures/real-cbe-report.json` passes.
- `tests/v17/fixtures/legacy-cbp-1.2.0-manifest.json` is intentionally rejected.
- 92 v1.7 tests passing locally.

## Not done

- No contract freeze.
- No new tag.
- No CBE/CBP/CBM/CBC repository edit.
- No v1.7.0 product implementation.
- **Real CBP 1.2.1 output is not RC2-conformant.** Its real fixture is included
  and fails because `artifact_repository` is still a string. CBP 1.2.2 (or a
  contract-approved migration) is required before real CBP conformance can be
  claimed.
