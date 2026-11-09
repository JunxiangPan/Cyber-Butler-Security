# v1.6.6 Evaluation Remediation — DRAFT, NOT FROZEN

Status: **DRAFT. Do not freeze, tag, or treat as a release gate until reviewed.**

Source evaluation: `docs/evaluations/CBS-v1.6.6-完整评测.md` (review input, kept outside the repo)
Evaluation date: 2026-11-09

The evaluation does not use literal `P0/P1` labels. The classification below is
a conservative severity mapping from its own findings; it does not change the
evaluation's wording.

## Evaluation factual corrections

Three statements in the source evaluation need correction; they do not change its
overall score:

1. The redline test did not fail because `$tokenReaders` disappeared. The first
   two assertions still matched; the third assertion was stale. The installer now
   authorizes with a SID (`$tokenSids` and `'*' + $tokenSid + ':(R)'`).
2. `CHANGELOG.md` is not stuck at v1.6.3. It was updated to v1.6.6 at commit
   `683913d`.
3. The coverage substitution is **12 items**, not 13: Q05–Q11 and Q13–Q17.

## P0 — must close before the next public release

| ID | Problem | Fix action | Owner | Acceptance |
|---|---|---|---|---|
| P0-1 | Reproducibility: no public host/reference agent; a stranger cannot reach a running system | Publish a minimal reference agent or tiny file-delete demo; one-command Broker + WebUI + TOTP; 3-minute GIF | CBS | A clean Windows user reaches a real approval flow without private AgentRuntime/AuxRuntime |
| P0-2 | Integrability: no SDK, JSON Schema, or framework adapter | Publish `/request`, `/verify`, `/status` JSON Schema + Python/TS clients + conformance corpus; add one external adapter | CBS | External agent sends a request and receives approval through the documented API |
| P0-3 | CI completeness: WebUI/quality tests absent; stale redline | Add `webui/tests` to testpaths and `quality/tests` to the Windows quality job; repair SID assertion | CBS | Both suites run green in CI on every push/PR |
| P0-4 | Coverage: Broker measured 46%, target 80%+; gate only covers `tools/broker.py` | Split broker into core/policy/audit/totp; extend CBS coverage to whole repo; make the floor blocking | CBS | Whole-repo coverage >=80% and CI hard-fails below it |
| P0-5 | Installer `.exe` is Authenticode-unsigned; SmartScreen shows unknown publisher | Sign `START-INSTALLER.exe` and launcher; record certificate chain/timestamp, or explicit waiver | CBS release | `Get-AuthenticodeSignature` returns `Valid`, or a written waiver is in the release notes |
| P0-6 | Documentation version drift | Sync README, CHANGELOG, status JSON, TEST_MATRIX to v1.6.6 | CBS docs | No page claims an older current release; status files point to v1.6.6 |
| P0-7 | QA self-consistency | QA report must carry `covered_count` matching rows; read `VERSION`; run Q24/Q26 after package exists; concrete FIXED/NOT_FIXED; signing-report key/algorithm/tag; signing tools inside product tag | CBS / v1.7.1 contract | Sign gate consumes the report without sed/merge; counters, rows, version, and evidence agree |

## P1 — important, but not a release-stopping defect

| ID | Problem | Fix action | Owner | Acceptance |
|---|---|---|---|---|
| P1-01 | `tools/broker.py` is ~2,958 lines; installer GUI ~1,807 lines | Split broker into core/policy/audit/totp; split installer GUI modules | CBS | Modules have explicit interfaces and existing tests stay green |
| P1-03 | No fuzzing/property-based tests for path/JSON/HTTP parsers | Add Hypothesis or equivalent corpora for parser boundaries | CBS / CBP | Fuzz/property suite runs in CI with reproducible seeds |
| P1-04 | `signing-report.json` lacks key id, algorithm, certificate chain | Extend signing report schema; record key id/algorithm/attestation refs | CBS | `verify-release` validates every field; no self-asserted fields |
| P1-05 | No SLSA/in-toto/GitHub Artifact Attestation | Add attestation/provenance generation and verification | CBS release | Published asset has verifiable provenance; release body links it |
| P1-06 | No formal Broker API reference; only prose `INTEGRATION.md` | Publish API reference generated from the schema | CBS | Third-party can implement a client from docs alone |
| P1-07 | No screenshots, badges, topics, demo, homepage; discovery is poor | Add screenshots/GIF, topics, homepage, 30-second README | CBS docs/community | New visitor understands problem/evidence/limits in 30 seconds |
| P1-08 | Windows-only and AGPL limit adoption | Decide whether cross-platform Broker/SDK is a v2.0 goal; document license intent | CBS strategy | Explicit platform/license decision recorded; no accidental promise |
| P1-09 | 27 releases / 69 tags in 11 days; 2 sign failures create noise | Reduce release cadence; preserve failed-run evidence; document release train | CBS release | One stable release line per train; failures linked from release notes |

## Already fixed and committed

| Item | Change | Verification |
|---|---|---|
| Stale redline assertion | `test_webui_can_read_broker_token_as_desktop_task` now checks `$tokenSids` and `'*' + $tokenSid + ':(R)'` | quality tests pass |
| WebUI tests not in CI | `pytest.ini` includes `tests` and `webui/tests` | local full suite 246 passed / 1 skipped |
| Quality tests not in CI | Windows-only CI step for `quality/tests` | quality tests 66 passed / 13 skipped locally |
| Test isolation failure | Autouse broker gate-state reset in `test_security_redlines.py` | full suite passes |
| Pinned-key test noise | `test_t19_all_four_files_verify` skipped with explicit trust-anchor reason | no fake PASS |
| cryptography missing in CI | Added `cryptography>=42.0` to `requirements-dev.txt` | security-tests 42537971245 green |
| privacy path | Source evaluation path sanitized | privacy scan OK |

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
