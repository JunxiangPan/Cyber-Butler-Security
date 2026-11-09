# P0-5 Installer Authenticode waiver

Status: **v1.7.x waiver; v2.0 public-stable requires a real Authenticode signature.**

Policy: [P0_5_SIGNING_POLICY.md](P0_5_SIGNING_POLICY.md)

The v1.6.6 and current v1.7.x installers are **not Authenticode signed**. The
build machine has no code-signing certificate. This is a visible release
limitation, not a claim that signing happened.

Waiver for v1.7.x only:

```text
- Component: START-INSTALLER.exe / launcher
- Signature: none
- Reason: no Authenticode certificate available in the build environment
- User impact: SmartScreen may show "Unknown publisher"
- Required before v2.0 public-stable: sign with an organization-validated
  certificate and RFC 3161 timestamp
- v1.7.x: this waiver must appear in the Release body
- Owner: human release owner
```

`Get-AuthenticodeSignature` must return `NotSigned` until a real certificate is
provided. Do not write "signed" in any artifact or release body.
