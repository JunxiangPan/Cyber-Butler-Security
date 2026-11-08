# v1.6.6 Evaluation Remediation — DRAFT, NOT FROZEN

Status: **DRAFT. Do not freeze, tag, or treat as a release gate until reviewed.**

Source evaluation: `C:\Users\pjx20\Documents\deepseek-harness\default-workspace\CBS-v1.6.6-完整评测.md`
Evaluation date: 2026-11-09

The evaluation does not use literal `P0/P1` labels. The classification below is
a conservative severity mapping from its own findings; it does not change the
evaluation's wording.

## P0 — must close before the next public release

| ID | Problem | Fix action | Owner | Acceptance |
|---|---|---|---|---|
| P0-01 | No public host/reference agent: a stranger cannot reach a running system | Publish a minimal reference host or a tiny file-delete demo; one-command Broker + WebUI + TOTP demo; 3-minute GIF | CBS | A clean Windows user reaches a real approval flow without private AgentRuntime/AuxRuntime |
| P0-02 | No SDK, JSON Schema, or framework adapter; other agents cannot integrate | Publish Broker endpoint JSON Schema + Python/TS clients + conformance corpus; add one external-agent adapter | CBS | External agent sends a request and receives approval through the documented API |
| P0-03 | WebUI 19 tests and quality tests are not in CI; stale redline test | Add `webui/tests` to testpaths and `quality/tests` to the Windows quality job; repair redline assertion | CBS | Both suites run green in CI on every push/PR |
| P0-04 | v1.6.6 QA report says `Covered: 0` while 12 rows are coverage substitution | QA schema must carry `coverage_policy` + `covered_count`; report text and counters must agree | CBS / v1.7.1 contract | Sign gate rejects a report whose coverage counter contradicts its body |
| P0-05 | Installer `.exe` is Authenticode-unsigned; SmartScreen shows unknown publisher | Sign `START-INSTALLER.exe` and launcher; record certificate chain and timestamp | CBS release | `Get-AuthenticodeSignature` returns `Valid` on the published installer |
| P0-06 | README/CHANGELOG/status/TEST_MATRIX are version-drifted | Sync README, CHANGELOG, status JSON, TEST_MATRIX to v1.6.6 | CBS docs | No page claims an older current release; every status file points to v1.6.6 |

## P1 — important, but not a release-stopping defect

| ID | Problem | Fix action | Owner | Acceptance |
|---|---|---|---|---|
| P1-01 | `tools/broker.py` is ~2,958 lines; installer GUI ~1,807 lines | Split broker into core/policy/audit/totp; split installer GUI modules | CBS | Modules have explicit interfaces and existing tests stay green |
| P1-02 | Broker coverage measured 46% against an 80% target; only `tools/broker.py` | Extend CBS coverage gate to whole CBS repo; add tests to clear the floor | CBS | Whole-repo coverage gate >80/85 as chosen; v1.7.0 blocks below floor |
| P1-03 | No fuzzing/property-based tests for path/JSON/HTTP parsers | Add Hypothesis or equivalent corpora for parser boundaries | CBS / CBP | Fuzz/property suite runs in CI with reproducible seeds |
| P1-04 | `signing-report.json` lacks key id, algorithm, certificate chain | Extend signing report schema; record key id/algorithm/attestation refs | CBS | `verify-release` validates every field; no self-asserted fields |
| P1-05 | No SLSA/in-toto/GitHub Artifact Attestation | Add attestation/provenance generation and verification | CBS release | Published asset has verifiable provenance; release body links it |
| P1-06 | No formal Broker API reference; only prose `INTEGRATION.md` | Publish API reference generated from the schema | CBS | Third-party can implement a client from docs alone |
| P1-07 | No screenshots, badges, topics, demo, homepage; discovery is poor | Add screenshots/GIF, topics, homepage, 30-second README | CBS docs/community | New visitor understands problem/evidence/limits in 30 seconds |
| P1-08 | Windows-only and AGPL limit adoption | Decide whether cross-platform Broker/SDK is a v2.0 goal; document license intent | CBS strategy | Explicit platform/license decision recorded; no accidental promise |
| P1-09 | 27 releases / 69 tags in 11 days; 2 sign failures create noise | Reduce release cadence; preserve failed-run evidence; document release train | CBS release | One stable release line per train; failures linked from release notes |

## Already fixed in the working tree (pending commit)

| Item | Change | Test |
|---|---|---|
| Stale redline assertion | `test_webui_can_read_broker_token_as_desktop_task` now checks `$tokenSids` and `'*' + $tokenSid + ':(R)'` | quality tests pass |
| WebUI tests not in CI | `pytest.ini` includes `tests` and `webui/tests` | local full suite passes |
| Quality tests not in CI | Will add a Windows-only CI step for `quality/tests` | quality tests 66 passed / 13 skipped locally |
| Test isolation failure | Autouse broker gate-state reset in `test_security_redlines.py` | full suite 228 passed / 14 skipped locally |
| Pinned-key test noise | `test_t19_all_four_files_verify` skipped with explicit trust-anchor reason | no fake PASS |

## Not in this remediation

- No CONTRACT.md edit.
- No v1.7 tag.
- No v1.7.0 product implementation.
- No claim that the evaluation's P0 items are complete.

## Proposed order

1. Merge this remediation plan after review.
2. Freeze v1.7.1 contract (new version + hash/tag).
3. CBP 1.2.0 / CBE 0.1.0 / CBM / CBC.
4. CBS v1.7.0 deep-water + full A1.
5. Re-evaluate the P0 host/SDK items before any public adoption claim.
