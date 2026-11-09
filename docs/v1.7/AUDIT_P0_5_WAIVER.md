# P0-5 Installer Authenticode waiver

Status: **OPEN — explicit waiver, not a signature.**

The v1.6.6 and current v1.7.0 integration installers are **not Authenticode
signed**. The build machine has no code-signing certificate. This is a visible
release limitation, not a claim that signing happened.

Waiver for the pre-release integration only:

```text
- Component: START-INSTALLER.exe / launcher
- Signature: none
- Reason: no Authenticode certificate available in the build environment
- User impact: SmartScreen may show "Unknown publisher"
- Required before public release: sign with an organization-validated
  certificate and timestamp, or publish this waiver in the Release notes
- Owner: human release owner
```

`Get-AuthenticodeSignature` must return `NotSigned` until a real certificate is
provided. Do not write "signed" in any artifact or release body.
