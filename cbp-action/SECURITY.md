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
