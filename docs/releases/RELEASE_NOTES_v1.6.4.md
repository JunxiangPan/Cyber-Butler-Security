# Cyber-Butler Security v1.6.4 — Release Notes

Status: **Released and RSA-3072 signed.**

## Release artifacts

```text
public-release-v1.6.4-candidate.zip
sha256: 64F42542D9E509F9010BD123A3AE5E6A8159BE0668E048701C1AA8BE9BB193E9
size:   207,575,660 bytes

update-manifest.json
sha256: ACEE940C54C7D404EA236E8E055ED1A1E3BE68901AD8548A5FE807AB084D2137

update-manifest.sig
sha256: A642B2C3E2F0B5626D96F404C67CCAFE9CDC0270E53213EBCA8DFD85BABCD79F

update_pubkey.pem
sha256: 67D9FD21F894349C8C53CFCB2A98113E5DE4960E08580929C97E6EBA1263EC62

FINAL_QA_REPORT.md
sha256: B5C00A0937584C4C4395581F118ACE7E6D211C4494A596CDF00E339DEA4B3404

ACCEPTANCE_PROOF.md
sha256: DA0169D1F609385EE690052A2D311CD2076F178775AA68BB6632D99C3B256F55
```

## Quality and VM evidence

The signed quality manifest records:

```text
total=26 passed=26 failed=0 blocked=0 skipped_by_design=0
```

The Q05-Q17 chaos evidence was produced on the VM host `HYPERPC` and imported
from the real `chaos-Q*.json` reports. The signed manifest and
`FINAL_QA_REPORT.md` were generated from those evidence files.

Q15 and Q17 use isolated clones/package extractions so they do not destroy the
real install tree. Q16 validates the bundled Python regardless of any host
Python installation.

### Environment-limited disclosures

Two items passed only under explicit environment constraints, recorded verbatim
in their JSON evidence:

- **Q13**: the test ran as Administrator, so Windows privileges bypassed the
  token ACL and returned 200. Strict non-administrator 403 verification requires
  rerunning Q13 as `CyberButlerSvc`.
- **Q14**: `CyberButlerSvc` lacked `SeBatchLogonRight`; the run is marked
  `environment-limited`. Strict verification requires granting that right.

These disclosures are part of the release evidence and are not hidden by the
26/26 manifest count.

## What changed in CBS 1.6.4

- Portable PowerShell 7 and portable Python 3.13 are bundled; the host does not
  need either runtime installed.
- The Broker is registered as a native pywin32 Windows service; the batch/cmd
  service path was removed.
- `port_guard.py` uses pure Python socket probing and no longer shells out to
  `netstat` or PowerShell.
- Runtime ACL hardening targets the portable `python` directory, not the retired
  `webui\.venv`.
- The launcher clears Mark-of-the-Web streams and extracts the bundled
  PowerShell archive before opening the GUI.
- Added the VM chaos harness and isolation fixes for Q15/Q17.

## Verification

Run from the release tree:

```powershell
python tools/verify_release.py `
  --manifest update-manifest.json `
  --signature update-manifest.sig `
  --pubkey update_pubkey.pem `
  --build-report BUILD_REPORT.md `
  --qa-report FINAL_QA_REPORT.md `
  --proof ACCEPTANCE_PROOF.md `
  --quality-manifest quality-manifest.json
```

Expected:

```text
VALID
```

## Known limitations

- `BUILD_REPORT.md` records mypy/pyright/PSSA/vulture as 0/0 with an explicit
  "not executed" note; those static analyzers were not run in the signing pass.
- The CBS `wheelhouse` still pins the **official CBP v0.1.4** wheel.
- CBP v0.1.6 contains the new path-escape and artifact-integrity rules, but only
  as a preview wheel; no official v0.1.6 Release has been published yet.
- The private key is not included in the repository or any release asset.

Community acknowledgement: see `CONTRIBUTORS.md`.
