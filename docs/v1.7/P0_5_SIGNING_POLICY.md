# P0-5 signing policy — Authenticode gate

Status: **external dependency; deferred to v2.0 public-stable.**

## Decision

```text
v1.7.x: unsigned installer is allowed only with this explicit waiver in the
        Release body.
v2.0 public-stable: Authenticode signing is mandatory before publication.
```

No self-signed certificate is acceptable as a substitute. A self-signed
certificate does not remove the SmartScreen unknown-publisher warning and would
be a false claim of trust.

## Parallel applications

```text
- Certum Open Source Code Signing (OSS)
- SignPath Foundation
```

Track both as external dependencies. Until one is granted:

```text
Get-AuthenticodeSignature START-INSTALLER.exe -> NotSigned
```

Release notes must say unsigned + waiver; never "signed".

## v2.0 acceptance

- Organization-validated Authenticode certificate
- RFC 3161 timestamp
- `Get-AuthenticodeSignature` returns `Valid`
- Certificate chain and timestamp recorded in the release evidence
- No self-signed fallback
