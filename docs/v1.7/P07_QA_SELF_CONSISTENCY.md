# P0-7 QA self-consistency evidence

Date: 2026-11-10

## Q24/Q26 after package generation

Package used:

```text
..\public-release-v1.6.6.zip
bytes: 51359667
```

Commands run after the package existed:

```powershell
python -m pytest -q `
  quality/tests/test_quality_matrix.py::test_q24_package_has_no_dev_artifacts `
  quality/tests/test_quality_matrix.py::test_q26_sbom_matches_actual_package
```

Output:

```text
2 passed in 0.02s
```

Q24 checks the ZIP for `.venv/`, `tmp-*`, placeholders, `pytest.ini` and
`__pycache__`. Q26 recomputes the SBOM entry hashes against the actual ZIP
bytes and compares each requirements list.

## BUILD_REPORT

`BUILD_REPORT.md` is a historical v1.6.3 build record. A v1.7 addendum was
appended with concrete FIXED / NOT_FIXED inventory instead of rewriting
historical output.

## Signing report

`tools/signing_report.py` now writes and verifies:

```text
stage
signed_at
signed_by.environment / run_id / commit
payload_sha256
key_id
algorithm
tag
```

Defaults are `local-release-key`, `RS256`, and `unsigned-qa`.
`tests/v17/test_signing_report.py` includes a round-trip test for these fields.

## Covered count

`quality/run_quality_matrix.py` emits:

```text
Passed
Failed
Covered
Blocked
```

with `blocked = total - passed - failed - covered`. The 26-item matrix currently
has no `covered` rows; the count is therefore 0 and is visible in the report
rather than inferred.

## Remaining not fixed

```text
http_server / auth / approval / executor extraction: 4 modules
handler 400/409/500 edge paths: partial
email_watch residual branches: partial
```

These are recorded as NOT_FIXED, not converted to PASS.
