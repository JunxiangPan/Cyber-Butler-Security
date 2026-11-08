# v1.7 Release Gate Contract

Status: **FROZEN**
Owner: CBS repository
Applies to: CBS, CBE, CBP, CBM, CBC, CBG
Last frozen: 2026-11-08

This is the only source of truth for cross-project release evidence. CBE,
CBP, CBM, and CBC repositories must consume this file and must not define
private variants of these rules.

## 1. Exit Codes

| Code | Meaning | Gate status |
| --- | --- | --- |
| 0 | PASS | `PASS` |
| 2 | Input or format error | `FAIL` or `PRECONDITION_FAIL` |
| 3 | Gate failure | `FAIL` or `SKIPPED_INFRA` |
| 4 | SKIP ratio above threshold | `FAIL` |

Exit code `3` always requires a valid `gate_status`. If a report exits `3`
but omits or misspells `gate_status`, the parser treats it as an input error
and exits `2`. It must not be accepted as a normal gate failure.

Infrastructure failures (runner 504, network timeout, provider outage):

```text
exit_code = 3
gate_status = SKIPPED_INFRA
publish = blocked
```

`SKIPPED_INFRA` is not a PASS, is not a normal SKIP, and is not counted in the
20% SKIP ratio. It must appear in its own Release body section.

Preconditions (main CI red, tag invalid, missing `--baseline` when required):

```text
exit_code = 2 or 3 as defined below
gate_status = PRECONDITION_FAIL
publish = blocked
```

`PRECONDITION_FAIL` is a gate-status value, not a new exit code. The exit-code
table above does not change.

## 2. Frozen Rules (F1–F6)

### F1 — Exit-code and report parsing

- Implement exactly the exit-code table in section 1.
- A report parser must read structured JSON, never grep logs.
- Exit `3` without a valid `gate_status` is an input error: exit `2`.
- `SKIPPED_INFRA` and `PRECONDITION_FAIL` are explicit gate statuses.
- All reports must include the minimum fields in section 5.

### F2 — CBE SKIP denominator

```text
applicable_count =
  count of non-blocking checks that are enabled and applicable
  for the current package_type
```

- Blocking checks (manifest validation, no-bypass enforcement, provider output)
  are never in the denominator and may not be SKIPPED.
- A non-applicable rule is emitted as `SKIPPED` with a reason, but is not in
  the denominator.
- `skip_ratio = skip_count / applicable_count`, with `applicable_count > 0`.
- A SKIP over 20% exits `4`.

### F3 — CBP SKIP denominator

Same structure as F2.

```text
applicable_gate_count =
  forced gates for the current package_type
  + adapted gates that are forced after adaptation
```

- `claims`, `binary`, `encoding`, `docs`, and `custom` may **not** SKIP.
- A SKIP of any of those gates exits `3`.
- Non-applicable gates may be `SKIPPED` but are not counted.
- `skip_ratio > 0.20` exits `4`.
- `SKIPPED_INFRA` is not counted in the ratio and still blocks publish.

### F4 — Previous stable version and ERRATUM

The previous stable baseline is:

```text
latest non-prerelease vX.Y.Z tag that:
  - has no ERRATUM marker
  - passed its release gates
  - is not the version currently being built
```

ERRATUM recognition is machine-readable only. A version is excluded only when
its GitHub Release body starts, after optional leading whitespace, with either:

```text
ERRATUM:
```

or has the release label:

```text
erratum
```

No other prose, comment, or human statement makes a release an ERRATUM.

If no eligible stable version exists and no explicit `--baseline` is supplied:

```text
exit_code = 3
gate_status = PRECONDITION_FAIL
```

There is no silent fallback to an arbitrary older version, `main`, or a
pre-release tag.

### F5 — Infrastructure SKIPPED

- `gate_status = SKIPPED_INFRA`
- `exit_code = 3`
- Not counted in the 20% SKIP ratio
- Blocks publish unconditionally
- Must be shown in a dedicated Release body section
- Must never appear under a PASS section

### F6 — CBM/CBC NOT_UPLOADED

If CBM or CBC is not uploaded:

```text
gate_status = NOT_UPLOADED
```

- Does not block the CBS main package by itself.
- Must not be written as PASS.
- Not counted in the SKIP ratio.
- Must be visible in the Release body.
- If the release train claims CBM/CBC is attached but the status is
  `NOT_UPLOADED`, the body must state: “declared as attached but not uploaded”.
  Missing that statement makes P2-04 fail.

## 3. Gate Status Enum

```text
PASS
FAIL
SKIPPED
SKIPPED_INFRA
PRECONDITION_FAIL
NOT_UPLOADED
```

`SKIPPED` is only valid for a non-blocking, applicable check, or an explicitly
non-applicable rule with a reason. It is never a substitute for PASS.

## 4. Build Once and Publish Gate

### Build-once

- Exactly one `build-once` job runs the build command.
- The artifact contains the package, `WHEEL_SHA256`, `RELEASE_ASSETS.sha256`,
  and `RELEASE_BODY.md`.
- CBE gate, CBP gate, dogfood, release, PyPI, and clean verification must consume
  the same artifact.
- No publish, PyPI, dogfood, or clean-verify job may rebuild the package.
- Manual asset upload and manual hash backfill are audit failures.

### Publish preconditions

`publish` is reachable only when all are true:

```text
main_ci_conclusion == success
precondition_status == PASS
cbe_gate_status == PASS
cbp_gate_status == PASS
skip_ok == true
artifact hashes match WHEEL_SHA256 / RELEASE_ASSETS.sha256
tag commit == manifest.ci_commit_sha
```

`skip_ok` means:

```text
skip_ratio <= 0.20
and blocking_skip == false
and no SKIPPED_INFRA
```

`publish` must not use `always()`. `SKIPPED_INFRA` and
`PRECONDITION_FAIL` never satisfy publish conditions.

Tag creation:

- The tag must point to the exact commit verified by the main CI run.
- Force-updating a tag after CI verification is forbidden; a new version and
  ERRATUM are required instead.

## 5. Report Minimum Fields

### CBE report

```json
{
  "schema_version": "1",
  "package_id": "cbe",
  "version": "vX.Y.Z",
  "tag": "vX.Y.Z",
  "gate_status": "PASS|FAIL|SKIPPED_INFRA|PRECONDITION_FAIL",
  "exit_code": 0,
  "applicable_count": 0,
  "skip_count": 0,
  "skip_ratio": 0.0,
  "blocking_skip": false,
  "warn_count": 0,
  "rules_manifest_hash": "sha256:...",
  "sarif_paths": [],
  "evidence_sha256": "sha256:..."
}
```

### CBP quality manifest

```json
{
  "schema_version": "1",
  "package_id": "cbp",
  "version": "vX.Y.Z",
  "gate_status": "PASS|FAIL|SKIPPED_INFRA|PRECONDITION_FAIL",
  "applicable_gate_count": 0,
  "skip_count": 0,
  "skip_ratio": 0.0,
  "blocking_skip": false,
  "gates": [
    {"name": "encoding", "status": "PASS|FAIL|SKIPPED", "reason": ""}
  ],
  "artifact_hashes": {},
  "release_body_hash": "sha256:...",
  "evidence_sha256": "sha256:..."
}
```

Missing required fields: exit `2`, status `FAIL`.

## 6. SARIF Namespaces

| Namespace | Owner |
| --- | --- |
| `CBE-*` | CBE rules and providers |
| `CBP-*` | CBP gates and claims |
| `CBG-*` | reserved for CBG; no cross-use |

A tool must not emit another namespace's rule IDs. All SARIF must be
SARIF 2.1.0 and suitable for GitHub Code Scanning ingestion.

## 7. Workflow Interface

Reusable workflow inputs:

```yaml
package_id: string
version: string          # vX.Y.Z
tag: string
package_type: string     # cbs/cbe/cbp/cbm/cbc/cbg
rules_manifest: string
cbe_ref: string          # default previous stable per F4
cbp_ref: string          # default previous stable per F4
cbp_rules_path: string
main_ci_conclusion: string
publish_targets: string
```

Job order:

```text
preflight -> cbe-gate -> build-once -> cbp-gate -> publish -> verify-release
```

The `publish` job's `if` must explicitly check the section 4 conditions.
`build-once` is impossible to skip when CBE fails.

## 8. Required E2E Expectations

### CBE

- CBE-01..CBE-11 as defined in the v1.7 execution contract.
- CBE self-check uses previous stable CBE and must return `0` for a compatible
  current manifest. A `2`, `3`, or `4` from self-check is an E2E failure.
- Provider empty output exits `3`.
- Blocking SKIP exits `3`.
- SKIP over 20% exits `4`.

### CBP

- CBP-01..CBP-15 as defined in the v1.7 execution contract.
- Missing asset manifest, release body, or wheel exits `2`.
- Missing/extra/wrong asset exits `3`.
- Forced gate SKIP exits `3`.
- Infra failure exits `3`, status `SKIPPED_INFRA`, publish blocked.
- CBP self-check uses previous stable CBP and must return `0`; any `2/3/4` is
  an E2E failure.

### Orchestration

- ORCH-01 main CI red -> publish unreachable, `PRECONDITION_FAIL`, exit `2`.
- ORCH-02 all PASS and skip within threshold -> publish reachable.
- ORCH-03 CBE FAIL -> build-once not reached.
- ORCH-04 CBP FAIL -> publish unreachable.
- ORCH-05 force-update tag -> rejected; new version + ERRATUM required.
- ORCH-06 rebuild during publish -> audit FAIL.
- ORCH-07 manual upload/backfill -> audit FAIL.
- ORCH-08 verify-release hash mismatch -> failure + ERRATUM.
- ORCH-09 no stable baseline and no `--baseline` -> `PRECONDITION_FAIL`, exit `3`.
- ORCH-10 self-check returns `2` -> E2E failure, not PASS.

## 9. Honesty Boundaries

- CBE verifies rule framework, manifest, provider execution, and evidence
  presence; it does not prove code security.
- CBP verifies evidence coherence and release claims; it does not prove code
  security.
- NOT_UPLOADED is not PASS.
- SKIPPED_INFRA is not PASS.
- A green CI run is not a substitute for real VM acceptance.
- Any exception to this contract requires a new version and a machine-readable
  ERRATUM; it must not be silently patched into an existing tag.

## 10. Change Control

This file is frozen for v1.7. Changes require:

1. a new version of the contract,
2. an entry in `docs/v1.7/CHANGELOG.md`,
3. updates to all affected E2E matrices,
4. no retroactive change to already published evidence.
