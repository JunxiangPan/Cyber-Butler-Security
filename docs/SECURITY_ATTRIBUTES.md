# Security Attributes (Draft)

This is a review checklist, not a certificate. Each item must be confirmed by a
human on a clean VM; automated tests cover only the stated portion.

| Attribute | Current evidence | Automated coverage | Gap |
|---|---|---|---|
| SYSTEM-only trash isolation | `quarantine.py` intends SYSTEM-only ACL; local fixture skips ACL | Logic only | Real ACL denial and bypass attempt must be checked in VM |
| Two-phase undo TOCTOU | `TargetSnapshot` handle binding and `assert_unchanged` tests | Unit + fixture logic | Race under real service load not measured |
| WFP default-deny | WFP status is documented as audit-only | No local enforcement test | Must verify default policy and failure mode in VM |
| DPAPI decrypt surface | DPAPI blob is ACL-scoped, not a secrecy boundary by itself | No local DPAPI test | Test from a second local account in VM |
| Service account privileges | Installer has ACL/task checks | Partial | Audit actual token privileges and SeDebugPrivilege denial |
| TOTP secret storage | Vault ACL + DPAPI in installed mode | TOTP algorithm tested; DPAPI only in VM | Leak/exfiltration surface needs human review |
