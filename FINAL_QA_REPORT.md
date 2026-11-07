# FINAL QA REPORT

- Version: 1.6.4
- Nonce: cbs-vm-final-test-2026-v2
- Profile: release
- Generated: 2026-11-07T16:32:48+00:00
- Matrix: 26 items
- Passed: 24
- Failed: 0
- Blocked: 2
- Skipped by design: 0
- Overall: **BLOCKED**

QUALITY_MANIFEST_SHA256: 10B6F1B9133EADF49EE0B7FC222D0D3AAF12C02A00C8407380D113B9B59C043E

> A blocked item is not a pass. The release signing gate requires 26/26
> passed items and a valid quality-manifest.json.

| ID | Check | Type | Status |
|---|---|---|---|
| Q01 | MAX_PATH / Unicode / emoji path handling | unit | passed |
| Q02 | WebUI XSS / oversized JSON / SQL injection | integration | passed |
| Q03 | TOTP replay and concurrent replay | unit | passed |
| Q04 | Broker config tamper graceful fallback | unit | passed |
| Q05 | Broker killed while Agent waits | chaos | passed |
| Q06 | WFP Guard heartbeat red light within 45s | chaos | passed |
| Q07 | Disk full / 1GB trash capacity breaker | chaos | passed |
| Q08 | CyberButlerSvc workspace ACL loss | chaos | passed |
| Q09 | 1000 approval requests handle leak | soak | passed |
| Q10 | 1 hour memory stability | soak | passed |
| Q11 | Orphan process scan after Job Object close | soak | passed |
| Q12 | TOCTOU target replacement returns 409 | unit | passed |
| Q13 | Two-stage trash ACL read bypass attempt | system | blocked |
| Q14 | CyberButlerSvc privilege escalation attempt | system | blocked |
| Q15 | Clean uninstall leaves no service/file/registry residue | system | passed |
| Q16 | Offline wheelhouse on Python-free clean Windows | system | passed |
| Q17 | Interrupted service creation and resume/repair | system | passed |
| Q18 | No unresolved YOUR_ placeholders in package | static | passed |
| Q19 | WebUI QR otpauth URI matches Broker secret | unit | passed |
| Q20 | VERSION / installer UI / docs version same source | static | passed |
| Q21 | Newline filename cannot inject audit JSONL | unit | passed |
| Q22 | Port conflict 18090/8765 preflight block | unit | passed |
| Q23 | Audit chain detects historical tamper | unit | passed |
| Q24 | No pytest/.venv/tmp/build artefacts in package | static | passed |
| Q25 | Final QA report generated and complete | meta | passed |
| Q26 | Dependency SBOM matches actual package manifests | static | passed |

## Blocked items

- **Q13**: environment-limited: Administrator token bypassed ACL (status=200); rerun Q13 as CyberButlerSvc for a strict 403
- **Q14**: environment-limited: CyberButlerSvc lacks SeBatchLogonRight; grant it and rerun Q14 for a strict test

## Signing gate

`tools/sign_release.py` re-reads quality-manifest.json and accepts blocked items only when this report records their reason.
