# Windows VM Acceptance Runbook

This is the physical acceptance procedure for CBS 1.6.4. Do not replace it with mocks or a local Python-only run.

## Prerequisites

- Windows 10/11 x64, administrator account
- PowerShell 7+ (`pwsh.exe`)
- The signed release package ZIP
- A phone with the CBS TOTP enrollment
- A fresh nonce, at least 16 characters, with at least two character classes

Install PowerShell 7 if needed:

```powershell
winget install --id Microsoft.PowerShell -e
pwsh -NoProfile -Command "$PSVersionTable.PSVersion"
```

CBS does not support Windows PowerShell 5.1 for installation or acceptance.

## Install

1. Extract the release ZIP to a clean directory.
2. Run `START-INSTALLER.exe` as administrator.
3. Complete the GUI installation. The launcher now starts `pwsh.exe`; if PowerShell 7 is missing it shows: `CBS requires PowerShell 7. Please install it from Microsoft.`
4. Confirm the install report and services are healthy.

## Acceptance proof

From an elevated PowerShell 7 session:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\CyberButler\tools\Run-Final-Acceptance.ps1 `
  -InstallRoot C:\CyberButler `
  -PackageZip C:\path\to\public-release-v1.6.4.zip `
  -ProofPath C:\CyberButler\ACCEPTANCE_PROOF.md
```

The script prompts for the nonce and the phone TOTP only when needed. It performs:

- real HTTP calls to the local Broker
- real ACL / process / audit evidence
- a wrong-TOTP negative test that must return 403
- a forged-token negative test
- a positive TOTP request and two-stage trash/undo
- capacity breaker checks unless `-SkipCapacity` is explicitly used

Do not type `-SkipCapacity` unless the runbook owner explicitly approves it.

## Pass criteria

The generated `ACCEPTANCE_PROOF.md` must contain:

```text
Overall: PASS
negative_403=True
negative_path=True
```

Then copy the proof into the release evidence directory, commit it, and run the release pipeline. Never hand-write or patch a proof.
