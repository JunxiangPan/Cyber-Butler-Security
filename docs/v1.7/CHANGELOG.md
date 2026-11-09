# v1.7 Contract Changelog

## v1.7.1 RC — 2026-11-09

Status: **release candidate; not frozen.**

### Breaking for consumers

- F2 blocking set now includes the three structural checks **plus** any manifest
  rule marked `gate: "blocking"`. Blocking rules are removed from the SKIP
  denominator and may not be SKIPPED.
- `package_id` now means the **subject** package; reports add `producer_id` for
  the component that produced them.
- `body_hash_scope` is required and must be exactly `base`.
- `artifact_repository` is required for build-once consumers.
- Hash fields are bare 64-character lowercase hex; `sha256:` prefixes are
  rejected with exit `2`.
- CBM/CBC body fragments are mandatory even when the component never ran; the
  generator must synthesize `NOT_UPLOADED` + `EVIDENCE_ABSENT`, not `- none`.

### Added

- `§5.1 Report identity`
- `§5.2 Hash representation`
- CBM/CBC body fragment templates and the exact phrase
  `declared as attached but not uploaded`.
- `docs/v1.7/V166_EVALUATION_REMEDIATION.md` as the v1.6.6 input backlog.

### Not included

- No freeze, tag, or release.
- No change to the published v1.6.6 evidence.
