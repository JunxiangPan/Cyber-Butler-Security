# FINAL QA REPORT

- Version: 1.6.4
- Nonce: A-READY-CBP-SYNC-001
- Profile: ci
- Generated: 2026-11-06T04:20:03+00:00
- Matrix: 26 items
- Passed: 12
- Failed: 0
- Blocked: 0
- Skipped by design: 14
- Overall: **PASS**

QUALITY_MANIFEST_SHA256: 57241E1028258ABC38D4F3FBFA77F2E59BD31D7CE203DED7D6F5DC25994A1324

> A blocked item is not a pass. The release signing gate requires 26/26
> passed items and a valid quality-manifest.json.

| ID | Check | Type | Status |
|---|---|---|---|
| Q01 | MAX_PATH / Unicode / emoji path handling | unit | passed |
| Q02 | WebUI XSS / oversized JSON / SQL injection | integration | passed |
| Q03 | TOTP replay and concurrent replay | unit | passed |
| Q04 | Broker config tamper graceful fallback | unit | passed |
| Q05 | Broker killed while Agent waits | chaos | skipped-by-design |
| Q06 | WFP Guard heartbeat red light within 45s | chaos | skipped-by-design |
| Q07 | Disk full / 1GB trash capacity breaker | chaos | skipped-by-design |
| Q08 | CyberButlerSvc workspace ACL loss | chaos | skipped-by-design |
| Q09 | 1000 approval requests handle leak | soak | skipped-by-design |
| Q10 | 1 hour memory stability | soak | skipped-by-design |
| Q11 | Orphan process scan after Job Object close | soak | skipped-by-design |
| Q12 | TOCTOU target replacement returns 409 | unit | passed |
| Q13 | Two-stage trash ACL read bypass attempt | system | skipped-by-design |
| Q14 | CyberButlerSvc privilege escalation attempt | system | skipped-by-design |
| Q15 | Clean uninstall leaves no service/file/registry residue | system | skipped-by-design |
| Q16 | Offline wheelhouse on Python-free clean Windows | system | skipped-by-design |
| Q17 | Interrupted service creation and resume/repair | system | skipped-by-design |
| Q18 | No unresolved YOUR_ placeholders in package | static | passed |
| Q19 | WebUI QR otpauth URI matches Broker secret | unit | passed |
| Q20 | VERSION / installer UI / docs version same source | static | passed |
| Q21 | Newline filename cannot inject audit JSONL | unit | passed |
| Q22 | Port conflict 18090/8765 preflight block | unit | passed |
| Q23 | Audit chain detects historical tamper | unit | passed |
| Q24 | No pytest/.venv/tmp/build artefacts in package | static | skipped-by-design |
| Q25 | Final QA report generated and complete | meta | passed |
| Q26 | Dependency SBOM matches actual package manifests | static | skipped-by-design |

## Signing gate

`tools/sign_release.py` re-reads quality-manifest.json and refuses blocked/failed items.
