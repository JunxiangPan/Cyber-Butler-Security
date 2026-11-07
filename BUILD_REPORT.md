# BUILD_REPORT

- Release Version: 1.6.4
- Candidate: public-release-v1.6.4-candidate.zip
- Package SHA256: 64F42542D9E509F9010BD123A3AE5E6A8159BE0668E048701C1AA8BE9BB193E9
- Package Size: 207,575,660 bytes
- Package Files: 395
- Launcher SHA256: CBF33369CF8108E54B48E7466FF98B6609D533B9E5B98CBF09C89AFC2603EA13
- Quality Matrix: 26/26 passed (VM evidence directory)
- Quality Manifest SHA256: 011D93BE91A2525DA64C802D12D735D704B3A4D55C873B9338C9B432EAF9FDB5
ChallengeCode: cbs-vm-final-test-2026-v2
PROOF_SHA256: DA0169D1F609385EE690052A2D311CD2076F178775AA68BB6632D99C3B256F55

## FIXED_THIS_ROUND

- Q05-Q17 VM chaos evidence imported from the real HYPERPC run.
- Q13/Q14 environment-limited administrator/SeBatchLogon cases are explicitly marked in their JSON evidence.
- Q15/Q17 are isolated from the real install tree and package extraction.
- Portable PowerShell/Python and native broker service remain bundled.

## NOT_FIXED_THIS_ROUND

- Q13 strict non-administrator ACL test still requires a CyberButlerSvc logon session.
- Q14 strict batch-logon policy test still requires SeBatchLogonRight.
- P1/P2 CBP adapter, Action SHA, and ReDoS work remains deferred.

## Static Analysis Coverage

- mypy: 0/0 (not executed in this signing pass; declared explicitly)
- pyright: 0/0 (not executed in this signing pass; declared explicitly)
- PSSA: 0/0 (not executed in this signing pass; declared explicitly)
- vulture: 0/0 (not executed in this signing pass; declared explicitly)

## Acceptance

- ACCEPTANCE_PROOF.md: Overall PASS
- Evidence host: HYPERPC
- Evidence nonce: cbs-vm-final-test-2026-v2

QUALITY_MANIFEST_SHA256: 011D93BE91A2525DA64C802D12D735D704B3A4D55C873B9338C9B432EAF9FDB5
PROOF_SHA256: DA0169D1F609385EE690052A2D311CD2076F178775AA68BB6632D99C3B256F55
