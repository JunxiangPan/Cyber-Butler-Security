# CBS v1.7.0 Wave 1 status

Updated: 2026-11-10

This is the canonical Wave 1 status page. A row is not marked DONE because a
design exists; it is DONE only when its evidence is committed.

## P0

| ID | Item | Status | Evidence / gap |
|---|---|---|---|
| P0-1 | Reference agent / QA Broker :3189 | **PASS** | `quality/qa_broker_3189.py`; request/verify/audit evidence in `quality/artifacts/qa-broker-3189` |
| P0-2 | External adapter / conformance | **PASS** | `openai-function-tools` 1.0.0; `sdk/conformance/run_adapter.py`; `sdk/conformance/adapter-run.json` |
| P0-3 | CI completeness | **DONE** | `security-tests.yml`; privacy, conflict, test, quality gates |
| P0-4 | Broker coverage | **DONE** | 85.16% CI / 85.58% local; `quality/coverage_gate.py` is a CI step |
| P0-5 | Installer signing | **DEFERRED** | v1.7.x unsigned waiver; v2.0 Authenticode |
| P0-6 | Docs / status page | **PASS** | this page; README / TEST_MATRIX / INTEGRATION_AUDIT linked |
| P0-7 | QA self-consistency | **PASS** | Q24/Q26 post-package 2 passed; signing fields; BUILD_REPORT addendum |

## A1

| Item | Status | Evidence |
|---|---|---|
| A1 clean-VM acceptance | **A1_PRODUCT_INSTALLED_QA_PARTIAL** | install.wim->Gen2 VHDX; CBS Tier Light INSTALLER_OK; Q05 PASS; Q06/Q07 blocked/failed; Q08-Q17 not run; no 26/26 |

Do not retry the current ISO. Wait for a verified UEFI-bootable ISO or a clean
VHDX. `cbs-acceptance-vm` and `CBS-Test` are not used as clean baselines.

## Deep water

| Item | Status | Design | Implementation |
|---|---|---|---|
| Temporal Replay | PASS (read-only) | `docs/v1.7/DEEP_WATER_DESIGN.md` | `tools/temporal_replay.py`; Broker audit fixture/evidence; hashes unavailable by source |
| Diff Boundary | PASS | `docs/v1.7/DEEP_WATER_DESIGN.md` | `tools/diff_boundary.py` called before write_file/overwrite in `tools/broker.py`; fail-closed tests |
| IPC / Named Pipe + Helper | BLOCKED | `docs/v1.7/DEEP_WATER_DESIGN.md` | pywin32 present; CreateNamedPipe works; no IPC VM because Gen2 UEFI boot failed; no two-account ACL test |
| Optional MXC | OPTIONAL / DEFERRED | `docs/v1.7/DEEP_WATER_DESIGN.md` | owner decision: not part of v1.7.0 blocking scope |

Temporal replay is PASS only for its read-only audit timeline; source audit has no
before/after hashes, so `hashes_available=false` is recorded rather than invented.
IPC is **not** PASS; a codec is not a named-pipe transport.

```text
IPC_DEFER_FOR_V1.7.0
  recommended, pending owner decision
  remove IPC from the v1.7.0 blocking scope only with owner approval
```


## v1.7.0 boundaries

```text
no v1.7.0 product tag
no signature
no publish
CONTRACT.md bytes unchanged: 209d75b4...
contract-v1.7.1 tag unchanged: c2b5e92
CBE/CBP/CBM/CBC repositories not modified
v1.6.6 tag/release/assets untouched
```

v1.7.0 RC is not claimed until the deep-water items required for the release
are either implemented with evidence or explicitly deferred by the owner.
