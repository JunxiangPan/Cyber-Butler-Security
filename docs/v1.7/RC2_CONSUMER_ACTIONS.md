# RC2 consumer actions

Status: **RC2, not frozen.**

## CBE

- `schema_version` must be the string `"1"`.
- `gate_status` may be `NOT_UPLOADED`; it is never PASS.
- Keep CBE-08 marked **DRAFT** until the human freeze. RC2 only supplies the
  F2 blocking-set definition; it is not a CBE-08 PASS.

## CBP

- `schema_version` must be the string `"1"`.
- `artifact_repository` must be an object: `repository`, `run_id`,
  `artifact_name`. The string form is rejected.
- `ci_commit_sha` is required (40 lowercase hex); `ci_run_id`, `generated_at`,
  `generated_by` are accepted.
- Emit `<!-- CBP-BODY-BASE-END -->`; hash the exact bytes before it.
- `release_body_hash` must equal the actual base hash (CBP-BODY-001).
- **CBP 1.2.1 real output still uses a string `artifact_repository` and fails
  RC2.** A 1.2.2 (or contract-approved migration) is required; do not rewrite
  1.2.0/1.2.1 evidence.

## CBM / CBC

- Consume the RC2 schema; do not modify the CBS repository.
- `NOT_UPLOADED` is valid in report status but is not PASS and does not enter
  the skip denominator.
- B1/B2 remain blocked until CBE/CBP produce subject-scoped reports.

## Evidence fixtures

```text
tests/v17/fixtures/real-cbe-report.json           PASS
tests/v17/fixtures/real-cbp-1.2.1-manifest.json  FAIL (expected, string repo)
tests/v17/fixtures/legacy-cbp-1.2.0-manifest.json FAIL (expected)
```
