# B Plan: self-hosted VM proof and unsigned build

Every step is marked `[DSH-AUTO]` (repository change, no host mutation) or
`[HUMAN-REQUIRED]` (VM, GitHub admin, runner registration).

## Phase 1 — repository wiring [DSH-AUTO]

1. Commit `vm-proof.yml`, `runner-health.yml`, `Run-Final-Acceptance.ps1`
   commit-sha output, runner scripts with `-WhatIf`, and the build-unsigned
   consumer.
2. Run local mock tests only; do not claim dynamic proof.

## Phase 2 — host preparation [HUMAN-REQUIRED]

1. Create VM 1 (runner) and VM 2 (acceptance target) on the Hyper-V host.
2. Install GitHub Actions runner on VM 1 and assign labels:
   ```text
   self-hosted, windows, x64, cbs-vm-proof
   ```
3. Verify on VM 1:
   ```powershell
   pwsh -NoLogo -NoProfile -Command '$PSVersionTable.PSVersion'
   Get-Command Invoke-Pester
   Test-Path C:\CyberButler
   ```
4. Configure GitHub Environment `release-signing` with required reviewers.
5. Configure a workflow-dispatch or Environment secret for the challenge.
6. Snapshot VM 1 and VM 2 before the first real run.

## Phase 3 — generate proof [HUMAN-REQUIRED]

```text
workflow_dispatch vm-proof.yml
  tag: v1.7.0
  challenge: <random>
  totp: <current phone TOTP>
```

The job must produce `ACCEPTANCE_PROOF.md` with:
- `Commit SHA: <40hex>`
- `Overall: PASS`
- `negative_403=True`
- `negative_path=True`
- `Nonce: <challenge>`

Artifact: `vm-proof-<run_id>`.

## Phase 4 — unsigned build [HUMAN-REQUIRED, then DSH-AUTO]

`build-unsigned` must:
- download `vm-proof-<run_id>`;
- verify `Commit SHA` equals the build commit;
- pass `-ProofPath` and `-ProofSource vm-proof-job/<run_id>`;
- run `Run-ReleasePipeline.ps1 -Unsigned`;
- assert `BUILD_REPORT.md` has `Build Mode: unsigned`, no sig,
  `proof_source`, and a valid `pre-build-freeze.json`.

## Failure diagnostics

| Symptom | Action |
| --- | --- |
| runner offline | `runner-health.yml`, check service on VM 1 |
| `pwsh` missing | install PowerShell 7.2+; runner service account PATH |
| `Pester` missing | `Install-Module Pester -Scope AllUsers` |
| `C:\CyberButler` missing | create install root on VM 1/VM 2 per DEPLOYMENT.md |
| proof commit mismatch | rerun vm-proof from the exact tag; do not edit proof |
| dirty tree | commit and push release branch; pipeline refuses dirty |
| `HEAD != origin/release/vX` | push the tag/branch first |
| answer challenge mismatch | regenerate proof with the same challenge |
| freeze mismatch | do not delete; investigate which file changed |

## Rollback

1. Stop the workflow run.
2. Restore VM 1/VM 2 snapshot.
3. Delete the failed workflow artifacts and any partial `ACCEPTANCE_PROOF.md`.
4. Do not force-update a published tag; add ERRATUM and use a new version.

## Confirmed execution boundaries

### Cross-run proof

`build-unsigned-v17.yml` is a separate workflow_dispatch. It requires:

```text
vm_proof_run_id
```

and downloads:

```text
vm-proof-<vm_proof_run_id>
```

`ProofSource` is `vm-proof-job/<vm_proof_run_id>`, not the build run id.

### Self-hosted checkout hygiene

Both `vm-proof.yml` and `build-unsigned-v17.yml` use:

```yaml
clean: true
persist-credentials: false
fetch-depth: 0
```

and run `git status --porcelain` before the pipeline. A dirty runner working
tree stops the job.

### Challenge handling

The challenge is masked in logs:

```powershell
Write-Host "::add-mask::$env:CBS_CHALLENGE"
```

Current `Run-Final-Acceptance.ps1` writes `- Nonce: <challenge>` into
`ACCEPTANCE_PROOF.md`; the signature gate requires that nonce. Therefore the
challenge must be treated as a **non-secret build nonce** until proof redaction
is implemented. Do not supply a reusable secret as `-Challenge`.

### VM topology

`Run-Final-Acceptance.ps1` operates on local `C:\CyberButler`, the local
broker and the local phone TOTP. It must run **inside the acceptance VM
(VM 2)**, not on VM 1.

Therefore the self-hosted runner with labels
`[self-hosted, windows, x64, cbs-vm-proof]` must be registered inside VM 2,
or VM 1 must use WinRM/Invoke-Command to execute the script inside VM 2.

`vm-snapshot-rollback.ps1` runs on the Hyper-V host (or a host-side runner),
not inside the VM being snapshotted. It must run before and after
`Run-Final-Acceptance.ps1`; VM 2 cannot snapshot itself.

## VM snapshot coordination (v1.7.0 decision: option A)

The v1.7.0 minimum uses human-driven snapshots on the Hyper-V host. It does
not add a host runner or a WinRM path. B/C are v1.7.1+ optimizations.

```text
[HUMAN-REQUIRED] before vm-proof:
  pwsh tools/vm-snapshot-rollback.ps1 -VMName cbs-acceptance-vm -Restore

[DSH-AUTO] vm-proof.yml runs Run-Final-Acceptance.ps1 inside VM 2 and uploads
           ACCEPTANCE_PROOF.md

[HUMAN-REQUIRED] after vm-proof, whether PASS or FAIL:
  pwsh tools/vm-snapshot-rollback.ps1 -VMName cbs-acceptance-vm -Rollback
```

The rollback is mandatory even when acceptance fails. Otherwise the next run
starts from a drifted VM and is not reproducible.

## Challenge / Nonce security boundary

The raw nonce is present in the public `ACCEPTANCE_PROOF.md`, because
`sign_release.py` binds the challenge into the signature payload. Therefore:

1. Generate a fresh nonce for every release; never reuse one.
2. The nonce must be a random string only; it must not encode a PAT, signing
   key, password, or any secret prefix.
3. It must not be a long-lived secret or derived from one in a reversible way.
4. It is public data once the proof is uploaded.
5. If a challenge-generation HMAC key is used, the key stays in the GitHub
   Environment; only the resulting one-time nonce enters the proof.
6. The nonce appears in the proof; masking logs with `::add-mask::` is
   necessary but not sufficient to make it secret.

## Rollback trigger and baseline semantics

The rollback step is not conditional on the job succeeding:

- `success` -> rollback.
- `failure` / `cancelled` -> rollback.
- `in_progress` longer than 120 minutes -> treat as failure, cancel the run,
  then roll back on the Hyper-V host.
- If the operator is absent, VM 2 may remain dirty; the next run must start
  with `-Restore` against the fixed baseline.

`-Restore` restores the fixed baseline snapshot:

```text
cbs-acceptance-baseline
```

It does **not** restore "the state before the previous run". Updating the
baseline is a separate maintenance operation outside the vm-proof flow.

Passing both `-Restore` and `-Rollback` is invalid and exits `2`.
