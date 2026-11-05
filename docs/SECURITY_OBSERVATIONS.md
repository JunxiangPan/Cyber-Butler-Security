# Security Observations

## 2026-11-05 00:15:23 — FINAL_QA_REPORT.md was modified during D2/D1 testing

- The real `FINAL_QA_REPORT.md` was temporarily changed to `Overall: **PASS**`
  while exercising the D2 bypass and D1 can-pass tests.
- It was restored to `Overall: **BLOCKED**`.
- Current SHA-256 of the restored content:
  `8fae1f3208082d93db850fb4cd7806d44881cee166088aaca7ddc1d1d11ff73d`.
- The mtime changed even though the content hash is the same.

## Risk

The release process has write access to the very files that the signing gate
reads. A test, an operator, or an agent can rewrite `FINAL_QA_REPORT.md` and
restore it, changing the timestamp without changing the content. A future gate
must not treat a restored file as freshly generated evidence.

## Proposed mitigation (design only; not implemented)

Before signing, require one of:

1. `FINAL_QA_REPORT.md` mtime is later than `BUILD_REPORT.md` mtime, and the
   former contains a `Generated: <timestamp>` line later than the report's
   recorded build time; or
2. the QA report is read from a fresh VM artifact directory written after the
   build, with its own hash recorded in the signed payload.

Status: design complete; implementation waits for a decision on strictness.
This check is not currently in `sign_release.py`.
