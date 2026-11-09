# B5 upstream probe evidence

Status: **B5_MAYBE_FIXED** — recorded from the CBS integration branch, 2026-11-09.

Command (run from the CBM checkout; CBM repository was not modified):

```bash
CBS_REPO=<cbs-integration-checkout> \
  python tools/check_b5.py --check-upstream
```

Observed:

```text
STATUS=B5_MAYBE_FIXED
SOURCE=<cbs-integration-checkout>/tools/release_body_v17.py
B5_MAYBE_FIXED
CBS no longer hides a missing CBM.
```

Result: exit `0`.

What changed in CBS:

- `tools/release_body_v17.py` now emits `CBM: NOT_UPLOADED` and
  `EVIDENCE_ABSENT` for a missing CBM.
- It no longer emits `- none` for empty infrastructure or component lists.
- The exact phrase `declared as attached but not uploaded` is emitted when the
  train declares CBM attached.

CBM's canary is intentionally left unchanged; CBM must flip its own
`tests/test_known_fail_silent.py` and remove the `known_fail_silent` marker in
its own repository. CBS did not edit CBM.
