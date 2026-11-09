# v1.7.0 Integration Audit — 2026-11-09

Status: **integration branch ready for continued work; contract NOT frozen, no tag, no signature, no publish.**

## Refs

```text
branch: v1.7.0-integration
head: f46786829323a8173474dcc549a8c431dc82c601
merge: 1211dfd (contract/v1.7.1 -> v1.7.0-integration)
contract branch: contract/v1.7.1 @ 3de93ae
v1.6.6 tag: 29a57d9 (unchanged)
```

## Contract RC hash self-consistency

```text
sha256sum docs/v1.7/CONTRACT.md
c1653cfe1adbc74d2523d2fa12c965ab761fce978061c8e55443eb8b6db3a7e5

RC_STATUS.md
c1653cfe1adbc74d2523d2fa12c965ab761fce978061c8e55443eb8b6db3a7e5
```

`.gitattributes` forces LF checkout for the contract, so Windows and Linux hash
the same bytes. The contract is still **NOT FROZEN**.

## CI

```text
contract/v1.7.1 security-tests: success (run id masked)
v1.7.0-integration security-tests: success (run id masked)
v1.7.0-dev security-tests: success (run id masked)
```

Local:

```text
python -m pytest -q                 252 passed, 1 skipped
python -m pytest -q tests/v17         84 passed
conflict marker guard                OK files=565
privacy scan                         OK
vm-proof.yml YAML                    OK; inputs tag/challenge/totp
```

## B5 upstream blocker

`CBM tools/check_b5.py --check-upstream` against the integration checkout:

```text
STATUS=B5_MAYBE_FIXED
B5_MAYBE_FIXED
CBS no longer hides a missing CBM.
```

Evidence: `docs/v1.7/AUDIT_B5.md`. CBM was not modified.

## CBE-08 upstream blocker

`docs/v1.7/AUDIT_CBE08.md` records the candidate F2 blocking set and the
contract hash. CBE-08 is **not claimed as passing**: CBE must implement it after
the human freeze; CBE's pin remains `4a437df`.

## P0 status

```text
P0-1 reference agent/demo      PARTIAL — examples/reference_agent exists; one-command demo not accepted
P0-2 SDK/schema/conformance    PARTIAL — Python/TS clients + 3 schemas + local conformance tests
P0-3 CI completeness           DONE — webui/quality CI, redline, conflict guard
P0-4 coverage                  BLOCKED — BROKER_COVERAGE=47.00%, target >80%
P0-5 installer signature       DEFERRED — v1.7.x unsigned waiver; v2.0 Authenticode gate
P0-6 docs sync                 PARTIAL — README/TEST_MATRIX updated; full status page pending
P0-7 QA self-consistency       PARTIAL — report/body/sign tooling landed in contract RC
```

## Not started / blocked

```text
- Temporal Replay
- Diff Boundary
- IPC / Named Pipe + Helper
- optional MXC
- A1 26/26 (Hyper-V snapshot + clean baseline + real TOTP)
```

These are not claimed complete. They require the human gates and the remaining
schedule; no deep-water code was added.

## A1 automation status

Added:

```text
quality/a1/provision_clean_vm.ps1
quality/a1/run_a1.ps1
quality/a1/teardown.ps1
quality/a1/autounattend.xml
quality/a1/Register-A1Task.ps1
quality/a1/Run-A1Elevated.ps1
quality/a1/adapters/Q05.ps1 ... Q17.ps1
quality/a1/README.md
```

The adapters are guarded scaffolds: they exit `3` with
`ADAPTER_SCAFFOLD_ONLY` rather than fake a pass. The elevated task is
**registered only by a human** from an elevated host PowerShell; DSH must not
and did not register it.

`Get-VM` on the host lists `cbs-acceptance-vm` and `CBS-Test`; the approved ISO
exists at the documented path.

Provisioning was attempted and **blocked before creating a VM**:

```text
reason: ELEVATION_REQUIRED: run from an elevated host PowerShell
evidence: quality/a1/artifacts/provision-blocked.json
```

The current DSH PowerShell is not elevated. No clean VM, no `a1-clean-base`
snapshot, and no Q05–Q17 adapter exists. A1 is therefore **blocked**, not
26/26 and not a pass.

## Human gates

1. Approve/freeze v1.7.1 contract.
2. Provide Authenticode certificate or approve the explicit waiver.
3. Provide Hyper-V/clean VM access and run A1 26/26.
4. Final signature and publish approval.
