# v1.7 Release Gate Contract

Status: **v1.7.1 RC — DRAFT, NOT FROZEN**
Owner: CBS repository
Applies to: CBS, CBE, CBP, CBM, CBC, CBG
Candidate date: 2026-11-09
Supersedes: v1.7.0 contract at `4a437df` only after human freeze

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

F2 blocking set:

```text
the three structural checks
  (manifest validation, no-bypass enforcement, provider output missing/invalid)
+ any manifest rule with gate: "blocking"
```

Advisory rules enter the SKIP denominator; blocking rules do not, and may not be
SKIPPED. A blocking rule's `package_types` must equal the manifest's top-level
`package_types`, so a blocking rule can never become non-applicable/SKIPPED.

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
artifact_repository matches the build-once producer coordinates
body_hash_scope == "base"
manifest.release_body_hash == actual base body hash (CBP-BODY-001)
```

`artifact_repository` must identify the same repository/run/artifact that produced
the consumed build-once artifact. A missing or mismatched coordinate is exit `2`.
The body hash is defined by §5.3; a mismatch is a blocking CBP-BODY-001 failure.

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

### 5.1 Report identity

- `package_id` is the **subject** package being verified: `cbs`, `cbe`, `cbp`, `cbm`, `cbc`, or `cbg`.
- `producer_id` is the component that produced the report: `cbe` or `cbp`.
- `version` and `tag` are the subject package's version, not the producer's.
- A consumer checks `package_id` against its own package name; `producer_id` is
  traceability only. A CBE report about CBS is `package_id: "cbs"` and
  `producer_id: "cbe"`.

### CBE report

```json
{
  "schema_version": "1",
  "package_id": "cbs",
  "producer_id": "cbe",
  "version": "vX.Y.Z",
  "tag": "vX.Y.Z",
  "gate_status": "PASS|FAIL|SKIPPED_INFRA|PRECONDITION_FAIL",
  "exit_code": 0,
  "applicable_count": 0,
  "skip_count": 0,
  "skip_ratio": 0.0,
  "blocking_skip": false,
  "warn_count": 0,
  "rules_manifest_hash": "<64 lowercase hex>",
  "sarif_paths": [],
  "evidence_sha256": "<64 lowercase hex>"
}
```

### CBP quality manifest

```json
{
  "schema_version": "1",
  "package_id": "cbs",
  "producer_id": "cbp",
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
  "artifact_repository": {
    "repository": "owner/repo",
    "run_id": "<run-id>",
    "artifact_name": "build-once-artifact"
  },
  "release_body_hash": "<64 lowercase hex>",
  "body_hash_scope": "base",
  "evidence_sha256": "<64 lowercase hex>"
}
```

`body_hash_scope` must be exactly `"base"`. The hash covers the release body
base before CBM/CBC fragments are appended; a producer must not hash a
pre-fragment body and then claim a full-body hash.

`artifact_repository` is required when a build-once artifact is consumed. It
must identify the same repository/run/artifact that produced the coordinates;
a local path or an unqualified artifact name is invalid.

### 5.2 Hash representation

The `sha256:...` forms in older examples were algorithm annotations, not part of
the value. Schema fields (`rules_manifest_hash`, `evidence_sha256`,
`release_body_hash`, `artifact_hashes.*`) are bare 64-character lowercase
hexadecimal strings. An input carrying a `sha256:` prefix is an input error
(exit `2`); a tool must not silently strip the prefix.

### 5.3 Body hash binding

`release_body_hash` is the SHA-256 of the exact bytes from the beginning of the
Release body to immediately before the marker:

```text
<!-- CBP-BODY-BASE-END -->
```

Rules:

- The marker itself is not included.
- If the marker is absent, the entire body is the base.
- No CRLF/LF normalization, no `rstrip`, no BOM removal at hash time. The body
  producer must fix those bytes before hashing.
- `manifest.release_body_hash` must equal the actual base hash; this is blocking
  rule CBP-BODY-001.
- Generate body -> hash -> write manifest -> upload must happen in one job on the
  same bytes.

CBP 1.2.0 is a known legacy mismatch (ERRATUM); do not rewrite its body in place.

### CBM/CBC body fragments

The CBS release body must always contain these sections, even when CBM or CBC
never ran:

```markdown
## CBM

- CBM: NOT_UPLOADED
  - cbm_gate_status: `NOT_UPLOADED`
  - upload_status: `NOT_UPLOADED`
  - reason: `EVIDENCE_ABSENT`
  - declared_attached: `true` | `false`
- Skip accounting: NOT_UPLOADED is not counted in the SKIP ratio (F6).
- Publish impact: CBM NOT_UPLOADED does not block the CBS main package by itself (F6).

## CBC

- CBC: NOT_UPLOADED
  - cbc_gate_status: `NOT_UPLOADED`
  - upload_status: `NOT_UPLOADED`
  - reason: `EVIDENCE_ABSENT`
  - declared_attached: `true` | `false`
- Skip accounting: NOT_UPLOADED is not counted in the SKIP ratio (F6).
```

If the train declares CBM or CBC attached, the body must also contain the exact
phrase:

```text
declared as attached but not uploaded
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

## 11. Build-once Profiles

A package type is built by exactly one `build-once` invocation. The profile is
data, not a hard-coded wheel template.

```yaml
build_command: string
build_shell: bash | pwsh
build_runner: ubuntu-latest | windows-latest
artifact_glob: string
artifact_type: wheel | zip-bundle
publish_targets: github | pypi | both
signing_command: string      # optional; runs in a separate sign-artifact job
signing_runner: ubuntu-latest | windows-latest
```

`RELEASE_ASSETS.sha256` is the only release asset inventory format:

```text
<sha256>  <basename>
<sha256>  <basename>
```

- The manifest lists every published asset except itself.
- The verifier adds the manifest itself to the allowed set but does not
  self-hash it.
- The verifier accepts `--artifact-type wheel` or `--artifact-type zip-bundle`.
  It may infer the type from the file suffix only if the caller omits the flag.

### CBS profile

```text
build_command: pwsh tools/Run-ReleasePipeline.ps1 -Version <v> -Challenge <challenge>
build_shell: pwsh
build_runner: windows-latest
artifact_glob: public-release-v*.zip update-manifest.json update-manifest.sig
artifact_type: zip-bundle
publish_targets: github
signing_command: tools/sign_release.py ...   # separate sign-artifact job
```

The CBS pipeline is Windows-only because it calls `pwsh.exe`,
`Get-NetAdapter`, Pester, and Windows file APIs. It does not sign the manifest:
`-Sign` only prints a reminder. `update-manifest.sig` must be produced by the
separate sign-artifact job before the asset manifest is generated.

### CBE/CBP profile

```text
build_command: python -m build --wheel --sdist --outdir dist
build_shell: bash
build_runner: ubuntu-latest
artifact_glob: dist/*.whl dist/*.tar.gz
artifact_type: wheel
publish_targets: both
signing_command: ""
```

### Signing isolation

- Build job has no private key.
- Sign job runs only after build-once, consumes its artifact, and uses a
  protected environment/secret.
- `RELEASE_ASSETS.sha256` is generated after signing, so it covers the
  signature.
- Publish consumes the signed artifact; it must not rebuild or re-sign.

### CBS two-phase signing protocol

The CBS pipeline has no signing window inside one run: it writes
`update-manifest.json` and `BUILD_REPORT.md`, then immediately requires
`update-manifest.sig`, which it does not create. A two-phase build is mandatory.

#### Phase 1: build-unsigned

- Runs on `windows-latest` with `pwsh`.
- Runs all quality, VM, proof, and packaging gates.
- Skips only the signature-existence and signature-verification steps.
- Writes `Build Mode: unsigned` into `BUILD_REPORT.md`.
- Writes the release ZIP, `update-manifest.json`, `BUILD_REPORT.md`,
  `FINAL_QA_REPORT.md`, `ACCEPTANCE_PROOF.md`.
- Immediately after the build, writes `pre-build-freeze.json`:

```json
{
  "update-manifest.json": "<sha256>",
  "BUILD_REPORT.md": "<sha256>",
  "FINAL_QA_REPORT.md": "<sha256>",
  "ACCEPTANCE_PROOF.md": "<sha256>"
}
```

- Uploads the unsigned artifact including the freeze file.

#### Phase 2: sign-artifact

- Runs on `windows-latest` in `environment: release-signing`.
- Requires manual approval.
- Downloads the unsigned artifact; never rebuilds or regenerates any file.
- Verifies `sha256sum -c pre-build-freeze.json`.
- Refuses if `Build Mode` is not `unsigned`.
- Signs the four-file payload with the protected key; writes
  `update-manifest.sig`.
- Uploads the signed artifact including the freeze file.

#### Phase 3: verify-publish

- Downloads the signed artifact; never rebuilds or re-signs.
- Verifies `sha256sum -c pre-build-freeze.json`.
- Enters `Build Mode: signed` in `BUILD_REPORT.md` (or records the transition
  in a separate signed mode record; the signed artifact must not carry
  `Build Mode: unsigned` as its final state).
- Verifies the RSA signature with `tools/verify_release.py`.
- Generates `RELEASE_ASSETS.sha256` covering ZIP, manifest, sig, and freeze.
- Runs `--verify-release --artifact-type zip-bundle`.
- Publishes only if all checks pass.

`pre-build-freeze.json` is the only freeze anchor between phases. It must not
be recomputed by the signing or publish phase.

### zip-bundle verification

`--verify-release --artifact-type zip-bundle` must verify all of:

1. `RELEASE_ASSETS.sha256` covers ZIP, `update-manifest.json`,
   `update-manifest.sig`, and `pre-build-freeze.json`;
2. the RSA signature is valid;
3. the four signed payload hashes equal `pre-build-freeze.json`;
4. final `BUILD_REPORT.md` has the signed-mode handshake;
5. any mismatch exits `3` and blocks publish.

A check that only compares file hashes is not zip-bundle verification.

### Unsigned build semantics

`Run-ReleasePipeline.ps1 -Unsigned` must:

- run every quality, VM-evidence, proof, and packaging gate; skip only the
  signature-existence check and RSA verification;
- exit `0` with no signature;
- write `Build Mode: unsigned` into `BUILD_REPORT.md`;
- reject an existing `update-manifest.sig` with exit `3`
  (`unsigned mode cannot have existing update-manifest.sig`);
- never modify `BUILD_REPORT.md` after signing.

`signing-report.json` records:

```json
{
  "stage": "signed",
  "signed_at": "...",
  "signed_by": {
    "environment": "release-signing",
    "run_id": "<github run id>",
    "commit": "<40-hex>"
  },
  "payload_sha256": "<JCS(freeze) sha256>"
}
```

The human approver is taken from the GitHub Environment deployment record, not
from this file. `pre-build-freeze.json` and `signing-report.json` must use the
same shared JCS implementation (`tools/jcs.py`).

The VM evidence gate is the external `ACCEPTANCE_PROOF.md`; it does not
provision nested virtualization inside the runner. A Windows runner can run
the pipeline only when that proof is attached.
