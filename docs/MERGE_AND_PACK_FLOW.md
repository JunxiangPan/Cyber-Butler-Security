# Merge and Pack Flow

```
VM
 │  Run-Final-Acceptance.ps1
 ▼
ACCEPTANCE_PROOF.md
 │  binary transfer (base64 / USB / shared folder)
 ▼
HOST
 │  merge_vm_acceptance.py verify-proof --proof ...
 │  merge_vm_acceptance.py merge --proof ... --nonce A-READY-...
 ▼
FINAL_QA_REPORT.md  BLOCKED -> PASS
FINAL_QA_REPORT.pre-vm-merge  (backup)
BUILD_REPORT.md     unchanged in this step
 │
 │  repack
 ▼
new zip:
  ACCEPTANCE_PROOF.md included
  BUILD_REPORT.md has PROOF_SHA256
  update-manifest.json has signature_version: "2"
  no update-manifest.sig
 │
 │  sign_release.py --build-report ... --qa-report ... --proof ...
 ▼
update-manifest.sig
 │
 │  verify_release.py --build-report ... --qa-report ... --proof ...
 ▼
VALID
 │
 ▼
publish zip + sig + version
```

## 1. VM

Run:

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\Run-Final-Acceptance.ps1 `
  -Challenge A-READY-20261105-0145 `
  -PackageZip .\public-release-v1.6.3.zip
```

This creates `ACCEPTANCE_PROOF.md` in the VM.

## 2. VM to host

Use base64, a USB device, or a shared folder. Do not edit the proof during
transfer.

## 3. Verify proof only

```powershell
python tools/merge_vm_acceptance.py verify-proof --proof .\ACCEPTANCE_PROOF.md
```

Expected:

```text
PROOF_VERIFIED
PROOF_SHA256=<hash>
```

This step does **not** read BUILD_REPORT and does **not** require
PROOF_SHA256. The pre-VM BUILD_REPORT cannot contain it.

## 4. Merge

```powershell
python tools/merge_vm_acceptance.py merge `
  --proof .\ACCEPTANCE_PROOF.md `
  --nonce A-READY-20261105-0145
```

This:

- requires the proof Nonce and the FINAL_QA_REPORT Nonce to match;
- requires Overall `BLOCKED`;
- requires exactly 15 `skipped` rows;
- requires Q02/Q18/Q22 to remain `skipped`;
- changes only the 12 whitelist rows to `passed`;
- writes `FINAL_QA_REPORT.pre-vm-merge`;
- changes Overall to `PASS`;
- leaves BUILD_REPORT unchanged.

## 5. Repack

Run the release pipeline. It must:

1. observe FINAL_QA_REPORT PASS and the proof present;
2. compute the proof SHA-256;
3. write `PROOF_SHA256: <hash>` into the new BUILD_REPORT;
4. include ACCEPTANCE_PROOF.md in the zip;
5. write update-manifest.json with `signature_version: "2"`;
6. not generate `.sig`.

## 6. Sign

```powershell
python tools/sign_release.py `
  --manifest update-manifest.json `
  --key <offline-key> `
  --build-report BUILD_REPORT.md `
  --qa-report FINAL_QA_REPORT.md `
  --proof ACCEPTANCE_PROOF.md `
  --expected-challenge A-READY-20261105-0145
```

The signer checks the report/proof nonce, the proof contents, and that the
actual proof SHA-256 equals the BUILD_REPORT `PROOF_SHA256`.

## 7. Verify

```powershell
python tools/verify_release.py `
  --manifest update-manifest.json `
  --signature update-manifest.sig `
  --pubkey update_pubkey.pem `
  --build-report BUILD_REPORT.md `
  --qa-report FINAL_QA_REPORT.md `
  --proof ACCEPTANCE_PROOF.md
```

Expected:

```text
VALID
```

## 8. Publish

Upload the zip, `.sig`, and public key metadata only after a human reviews the
proof and the signed report.
