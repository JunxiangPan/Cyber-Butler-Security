# Security Policy

## Reporting a vulnerability

Please use GitHub Security Advisories:

`https://github.com/JunxiangPan/cbp-action/security/advisories/new`

Do not open a public issue for an unfixed vulnerability.

Include the affected version, a minimal reproduction, and the impact. Do not
include real credentials or customer data.

## Scope

CBP is a CI quality gate. It does not execute untrusted project code beyond the
commands the caller configures, and it does not fetch remote resources at
runtime.

## Supported versions

Security fixes target the latest v0.1.x release. The release workflow publishes
wheels from tagged commits only.

## Build provenance

Release wheels are built in GitHub Actions and attested with
`actions/attest-build-provenance` using the workflow's OIDC identity. Verify an
artifact with:

```bash
gh attestation verify cbp_action-0.1.4-py3-none-any.whl --repo JunxiangPan/cbp-action
gh attestation verify quality-manifest.json --repo JunxiangPan/cbp-action
gh attestation verify quality-manifest.json.sha256 --repo JunxiangPan/cbp-action
```

The SHA256 checksum and run-id are still published, but they are not a
replacement for the OIDC attestation.
