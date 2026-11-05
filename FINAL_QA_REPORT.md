# FINAL QA REPORT

- Version: 1.6.3
- Nonce: test
- Generated: 2026-11-05T12:44:47+00:00
- Matrix: 25 items
- Passed: 10
- Failed: 0
- Blocked: 15
- Overall: **BLOCKED**

> A skipped/blocked item is not a pass. The signing gate requires every
> row below to be PASS.

| ID | Check | Type | Status |
|---|---|---|---|
| Q01 | MAX_PATH / Unicode / emoji path handling | unit | passed |
| Q02 | WebUI XSS / oversized JSON / SQL injection | integration | skipped |
| Q03 | TOTP replay and concurrent replay | unit | passed |
| Q04 | Broker config tamper graceful fallback | unit | passed |
| Q05 | Broker killed while Agent waits | chaos | skipped |
| Q06 | WFP Guard heartbeat red light within 45s | chaos | skipped |
| Q07 | Disk full / 1GB trash capacity breaker | chaos | skipped |
| Q08 | CyberButlerSvc workspace ACL loss | chaos | skipped |
| Q09 | 1000 approval requests handle leak | soak | skipped |
| Q10 | 1 hour memory stability | soak | skipped |
| Q11 | Orphan process scan after Job Object close | soak | skipped |
| Q12 | TOCTOU target replacement returns 409 | unit | passed |
| Q13 | Two-stage trash ACL read bypass attempt | system | skipped |
| Q14 | CyberButlerSvc privilege escalation attempt | system | skipped |
| Q15 | Clean uninstall leaves no service/file/registry residue | system | skipped |
| Q16 | Offline wheelhouse on Python-free clean Windows | system | skipped |
| Q17 | Interrupted service creation and resume/repair | system | skipped |
| Q18 | No unresolved YOUR_ placeholders in package | static | skipped |
| Q19 | WebUI QR otpauth URI matches Broker secret | unit | passed |
| Q20 | VERSION / installer UI / docs version same source | static | passed |
| Q21 | Newline filename cannot inject audit JSONL | unit | passed |
| Q22 | Port conflict 18090/8765 preflight block | unit | skipped |
| Q23 | Audit chain detects historical tamper | unit | passed |
| Q24 | No pytest/.venv/tmp/build artefacts in package | static | passed |
| Q25 | Final QA report generated and complete | meta | passed |

## Signing gate

`tools/sign_release.py` refuses to sign unless this report is PASS.
