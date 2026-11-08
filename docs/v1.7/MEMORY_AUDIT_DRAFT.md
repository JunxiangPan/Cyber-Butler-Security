# v1.7 Series Memory Audit — DRAFT, NOT FROZEN

Status: **DRAFT for human review. Do not freeze, tag, or implement from this file yet.**

Sources searched:

- session `4e4350df` seq 145700, 145753, 145762, 145769, 145778, 145834, 145857, 170413, 170421, 170511, 170588, 170618, 171022, 171144, 171229
- session `d19111be` seq 1860, 1935, 1970
- repository docs: `ROADMAP.md`, `CHANGELOG.md`, `release/v1.6.4:docs/v1.7/CONTRACT.md`, `PINS.md`
- project checkouts: `cbe`, `cbp-action-release`, `cbm`, `cbc-event`

## A. Contract and release-train promises

| Promise / requirement | Current evidence | Status |
|---|---|---|
| v1.7.1 contract replay from `release/v1.6.4` to current tip | Current `public-release` tip has no `docs/v1.7` or `schemas/v1.7`; files still only on `release/v1.6.4` | MISSING |
| §5.1 `package_id` = subject, add `producer_id` | CBM B1; CBE boundary B-27/B-29; current contract still has ambiguous `package_id` only | MISSING |
| F2 blocking set amendment | CBE B-29/CBE-08 pending; CBE-08 must stay draft | MISSING |
| §5 minimum fields aligned across CBE/CBP/CBM/CBC | CBE report exists; CBP 1.1.0 legacy manifest lacks new fields; CBM/CBC identity pending | PARTIAL |
| Body CBE/CBC/CBM fragments + exact phrases | Contract F6 has NOT_UPLOADED phrases; CBM B5 says CBS body writes `- none` when CBM absent | PARTIAL / FAIL-SILENT |
| `body_hash_scope: "base"` requirement | CBP 1.1.0 does not implement P0-06; CBM B3, CBC F05 blocked | MISSING in CBP |
| `artifact_repository` unification | CBE/CBP/CBS artifacts in separate repos; CBM B4 | MISSING |
| Build-once profiles `build_command` / `artifact_glob` / `publish_targets` | §11 exists on `release/v1.6.4`; reusable workflow still mock; real build not wired | PARTIAL |
| Real reusable workflow (not mock CLI) | `reusable-v17-release.yml` with mock CBE/CBP; real CBS zip build not wired | PARTIAL |
| Real `--verify-release` / ERRATUM E2E | Unit/mock only; no real release E2E | PARTIAL |
| Weekly verify workflow | Exists with real command contract | DONE |
| PINS: CBE >= 0.1.0, CBP >= 1.0.8, CBS == 1.7.0 | PINS exists on release/v1.6.4 | DONE (not replayed to current tip) |

## B. CBS v1.7.0 deep-water promises

| Promise | Current evidence | Status |
|---|---|---|
| Temporal Replay: read-only timeline, before/after hashes, actor, request id | Design only | NOT STARTED |
| Deterministic replay in sandbox: no network/FS writes, same hashes | Design only | NOT STARTED |
| Quarantine browser: read-only, restore requires new approval + audit | Existing two-stage delete/undo is not a quarantine browser | NOT STARTED |
| Cross-agent correlation by request id, no token/TOTP material | Design only | NOT STARTED |
| Diff Boundary / staging interception before write | Design only; current broker policy is runtime approval, not pre-write diff | NOT STARTED |
| IPC / Named Pipe + user-session Helper; UIPI event | Design only; no helper/named pipe implementation | NOT STARTED |
| Optional MXC backend: export policy, no silent apply, schema round-trip | Backlog items in ROADMAP; no implementation | NOT STARTED |
| Upgrade path | Proposed chain: v1.6.2 -> v1.6.3 -> v1.6.4 -> v1.6.6 -> v1.7.0. v1.6.5 was not released and is not a bridge; do not omit v1.6.6 from public docs. | STALE / NEEDS REVIEW |
| Full A1 QA for v1.7.0 | v1.6.6 used explicit coverage substitution; d19111be says v1.7.0 must do full A1 | MUST DO |
| Whole-repository coverage hard gate (80% / 85% policy) | CBS coverage gate measures only `tools/broker.py` (46% at v1.6.6); v1.7.0 must extend to the whole CBS repository. CBP has a separate coverage gate; do not conflate them. | KNOWN DEBT / CBS-ONLY |
| Seven-round docs audit (structure/dedupe/8 languages/links/limitations/GitHub/UX) | Not performed for v1.7 | NOT STARTED |

## C. Ecosystem promises

| Project | Promise | Current evidence | Status |
|---|---|---|---|
| CBE | Real rule pack + 0.1.0; CBE-08..11 | CBE repo `70faad8`; CLI/provider/SARIF implemented; CBE-08..11 pending v1.7.1 | PARTIAL |
| CBP | 1.2.0: `body_hash_scope` + `artifact_repository` + cbc-event emission | CBP 1.1.0 published; no P0-06; no artifact_repository; no event emission | NOT STARTED |
| CBM | SDK middleware/proxy, rules, streaming restore, events | `cbm` `00d984e`; 84 tests; A–F live E2E not run; B1–B5 blockers | SKELETON |
| CBC | Standalone console, adapters, event viewer, hash chain | `cbc-event` `ae18d0c`; CI green; F05 skip; real E2E blocked | PARTIAL |
| CBR | Early Cyber-Butler-Review concept | Superseded by CBE; no `cbr` checkout and not in the five-project scope | OUT OF SCOPE (v1.8 if revived) |
| CBE/CBP/CBM/CBC | Independent repos, independent CI/release notes | Separate repos exist; CBP/CBC/CBM not integrated; CBR is not a missing fifth project | PARTIAL |
| cbc-event | 0.1.x backward compatibility; unknown fields WARN not FAIL; every component emits from day one | Protocol 0.1.0 recorded; no CBS/CBP emitter; CBE/CBM/CBC emission not wired | PARTIAL |
| CBP governance | CBP must gate every CB component, including CBS and CBP itself, with no exemption | CBS is on CBP 1.1.0; CBE/CBM/CBC are not yet on CBP; CBP self-gate is not complete | PARTIAL |
| Event reporting | Default off, JSONL append-only, optional localhost HTTP, token/HMAC, rate limit | Design only; CBS/CBP `cbc_report_enabled` not implemented | NOT STARTED |
| Event tamper defense | Config ACL, runtime hash check, hash chain, head anchor, CRITICAL alert | Design only; no CBS/CBP emitter | NOT STARTED |
| Multi-project version matrix | Each project own version; CB-2026.11 sync snapshot | ROADMAP still CBS-centric; no CB-2026.11 file | STALE |
| Integration tests | Independent `integration-tests` repo/dir; CBS + CBP + CBE + CBM + CBC together | No integration-tests repo/dir | MISSING |
| Release notes | Each project own notes; sync snapshot notes | CBP/CBC/CBS have notes; CBE/CBM not released; no sync notes | PARTIAL |

## C2. Governance rules that must not be lost

**Five equal projects:** CBS, CBE, CBP, CBM, CBC. There is no CBS “main version”
that absorbs the ecosystem versions. Each project has its own version, CHANGELOG,
test line, and release notes. `CB-2026.11` is a synchronization snapshot/release
note, not a product version.

**CBP supervises all components, including itself:** CBS, CBP, CBE, CBM, CBC,
and `cbc-event` CI must run CBP. No exemption for CBP itself. Current state:
CBS is on CBP 1.1.0; CBE/CBM/CBC are not wired; CBP self-gate is incomplete.

**CBC compatibility from day one:** every component emits `cbc-event` by default;
turning it off must be an explicit configuration. Current state: CBS and CBP have
no emitter; CBE/CBM/CBC emission is not integrated. This is not a v1.8-only add-on.

## D. Process / tooling misses found during v1.6.6

| Miss | Evidence | Action |
|---|---|---|
| QA report hardcoded v1.6.3 | v1.6.6 artifact initially had Version 1.6.3; merge now rewrites | Fix generator to read `VERSION` for v1.7 |
| QA report counts stale after merge | v1.6.6 QA report had Passed 12 / Blocked 14 while rows changed | Fixed in v1.6.6 repack; generator should compute counts |
| Q24/Q26 package checks skipped before package exists | v1.6.6 quality matrix runs before package build | Reorder or seed package in v1.7 |
| Signing report helper missing from tag | `tools/signing_report.py` absent at `v1.6.6`; fixed via `v1.6.6-sign` tooling tag | Include in product tag for v1.7 |
| BUILD_REPORT NOT_FIXED too vague | sign gate rejected three bullets without file/number | Fix pipeline template for v1.7 |
| Release body CBM absent fail-silent | CBM B5; `release_body_v17.py` renders `- none` | Fix CBS body generator |
| VM snapshot/Hyper-V not used for A1 | `Get-VM` permission denied; A2 used | For v1.7 full A1, grant Hyper-V access and use snapshots |
| Test TOTP fallback removed from CBS; test secret rotated | v1.6.6 commit 17bc1ea; TOTP rotated | DONE for v1.6.6; keep removed |

## E. Suggested order (not approved, not frozen)

1. v1.7.1 contract patch + docs/schemas replay.
2. CBP 1.2.0 (`body_hash_scope`, `artifact_repository`, cbc-event emission).
3. CBE real rule pack + 0.1.0; finish CBE-08..11.
4. CBM/CBC real E2E against the v1.7.1 contract.
5. CBS v1.7.0 deep-water + full A1 + five-component integration train.
6. No CBR work in 1.7; if a standalone CBR is revived, treat it as a v1.8 new project.

## Review decisions (not frozen)

These answers were given during human review and still require the final freeze step:

- **CBR:** not in the 1.7 series. CBE replaced it. Any independent CBR is a v1.8
  new-project proposal, not a 1.7 blocker.
- **v1.7.1:** new version, new contract hash, and new tag. A branch-only patch
  would violate the contract change-control rule and invalidate the other
  projects' pins.
- **v1.7.0 A1:** Hyper-V permission is available, snapshot
  `pre-v1.6.6-qa-20261109` exists, and an ISO exists. A clean baseline still
  needs a clone or an ISO-based build.
- **CB-2026.11:** a real synchronization document / release note such as
  `docs/CB-2026.11.md`, not merely a tag.
- **v1.6.6 coverage substitution:** one-time debt for v1.6.6 only. v1.7.0 must
  perform the full A1 QA; A2 coverage substitution must not become the default.
- **CBS coverage ownership:** the 46% gate is a CBS gate over
  `tools/broker.py`; it is not CBP's coverage metric.
- **Five-project equality:** CBS does not own a “main version” that absorbs
  CBE/CBP/CBM/CBC. Each project keeps its own version and release notes.

## Still proposed, not frozen

- Exact v1.7.0 installer minimum: proposed `>= 1.6.6`.
- Whether v1.6.4 may upgrade directly to v1.7.0 after v1.6.6 exists: proposed
  yes only through v1.6.6.
- Integration-test repository layout and CB-2026.11 contents.

