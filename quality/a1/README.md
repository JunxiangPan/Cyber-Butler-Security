# A1 clean-VM automation

Status: **framework only; no 26/26 claim.**

## Scripts

- `provision_clean_vm.ps1` — ISO + autounattend ISO + Gen2 VM + heartbeat + `a1-clean-base`
- `run_a1.ps1` — restore base snapshot, run one adapter per Q item, write
  `result.json` + log + SHA256; missing adapters are `blocked`
- `teardown.ps1` — remove the VM only when requested; evidence is retained

## Provision

Run from an elevated host PowerShell:

```powershell
.\quality\a1\provision_clean_vm.ps1 `
  -IsoPath 'D:\iso\Windows11_Client_x64_zh-cn_26300_9457.iso' `
  -VMName 'cbs-a1-clean' `
  -VhdDirectory 'D:\HyperV\qa-clones'
```

The script writes a random local-admin password to
`D:\HyperV\qa-clones\<vm>-admin.txt`. It is not written to the repository.

If the install fails, `artifacts/provision-blocked.json` records the reason.
Do not substitute an already-installed CBS VM.

## Run

Each Q05–Q17 item needs:

```text
quality/a1/adapters/<Qxx>.ps1
```

The adapter receives `-ArtifactZip`, `-Nonce`, and `-TimeoutMinutes`, and must
exit `0` only for a real pass. No adapter means `blocked: NO_ADAPTER`; this is
deliberate and is not a fake PASS.

```powershell
.\quality\a1\run_a1.ps1 -VMName cbs-a1-clean -BaseSnapshot a1-clean-base
```

The base is restored before each disruptive item. Q16 must use a fresh clone;
Q15/Q17 use snapshot -> test -> restore.

## TOTP

A1-local QA may use a QA-only secret inside the QA VM only. It must not enter
the release artifact or this repository. The final v1.7.0 proof must use a real
phone TOTP supplied by the human.

## Current status

No clean VM was provisioned in this turn. No Q05–Q17 adapter exists yet, so
the result is a `blocked` list, not 26/26. The scripts are the automation
surface; adapters must be added and executed before A1 can be claimed.
