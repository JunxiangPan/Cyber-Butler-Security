# CBP v1.2.0 — Release-evidence gate

Release evidence for v1.2.0.

This release body was generated from the built wheel by
`tools/generate_release_body.py`; the wheel SHA256 is not hand-edited.

## Verification

```text
QUALITY_COUNTS: 9/9
All 9 gates are active.
```

```text
cbp_action-1.2.0-py3-none-any.whl
sha256: 188639bb47e5a8940defbdb5ba3c4270ae89ad68503d283b611cb2a00497da2e
```

https://pypi.org/project/cbp-action/1.2.0/

## Section A: Security regression (blocking)

- main CI: https://github.com/JunxiangPan/cbp-action/actions/runs/4260 PASS
- v1.0.6 verify: https://github.com/JunxiangPan/cbp-action/actions/runs/masked-run PASS
- v1.0.7 verify: https://github.com/JunxiangPan/cbp-action/actions/runs/masked-run PASS
- composite action payload E2E (15 hostile inputs): https://github.com/JunxiangPan/cbp-action/actions/runs/masked-run PASS 15/15
- single build artifact re-verified: https://github.com/JunxiangPan/cbp-action/actions/runs/4260 PASS
- SARIF upload: https://github.com/JunxiangPan/cbp-action/actions/runs/4260 PASS
- Python 3.10: PASS (tested in the OS x Python matrix)
- checkout ref whitelist: PASS
- release body auto-generated: PASS (no manual backfill)
- release.yml permissions: PASS
- release asset inventory: PASS
- security_core: 90%+ floor

## Section B: AI audit gates (audit mode, non-blocking)

- ai-release / ai-test / ai-change run in the main CI `ai-audit` job; that job
  prints `AI_GATE_SUMMARY` with PASS / WARN / SKIP counts: https://github.com/JunxiangPan/cbp-action/actions/runs/4260
- Section B gates are audit-only and do not block publishing.

## Still to acknowledge

- ai-test false-positive rate is not yet measured on external projects.
- composite action payload E2E runs on GitHub Linux; local Windows is not verified.
- ai-release is structured evidence only, not natural-language summarization.
- Section B gates are audit-only and do not block publishing.

