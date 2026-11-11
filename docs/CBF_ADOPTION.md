# CBF Adoption — CBS

Status: **PENDING_CBF_0.1.0**

CBF 0.1.0 has not been released. This project is **not CBF-integrated** and has
**no CBF PASS**. This document is Phase 0 preparation only; it does not claim
compatibility or a completed gate.

| Field | Value |
|---|---|
| Project | CBS — CBS release repository |
| Status | `PENDING_CBF_0.1.0` |
| Surfaces | `git`, `api`, `local-ai` |
| Planned gate | `cbf gate --surface git` |
| Planned CI job | `cbf-privacy-gate` (reserved, **not active** in Phase 0) |
| Evidence format | `cbf-evidence/v1` |

## Current state

- CBF is **not installed** by this project and is not a runtime dependency.
- No `cbf.policy.json` is pinned yet; Phase 1 adds it after CBF 0.1.0rc1.
- No pre-push hook runs CBF yet.
- The CI job name `cbf-privacy-gate` is reserved but intentionally absent from
  active CI until Phase 1. It is not an `if: false` or `continue-on-error`
  placeholder.
- Historical releases/tags made before CBF 0.1.0 must not be described as CBF
  PASS.

## Planned integration

1. Add `cbf.policy.json` pinned to the CBF policy version/hash.
2. Add the `cbf-privacy-gate` CI job; failures block.
3. Install a local pre-push hook invoking `cbf gate --surface git`.
4. Require CBF PASS before git push / GitHub Release / PyPI.
5. Store `cbf-evidence/v1` evidence; never synthesize a PASS.
6. Phase 2: make `cbf-privacy-gate` a required check and include CBF evidence
   in releases/uploads.

## Project-specific boundary

- CBF scans the CBS repository/package/release assets only; it does not enter the CBS runtime.
- A1 26/26 acceptance is unchanged by CBF.
- GitHub push / Release / zip assets must pass CBF before publication once Phase 1 is active.
- CBF is not a CBS runtime dependency.

CBF remains an independent project: CLI + JSON + CI integration, not code
coupling. This project can build and test without CBF installed, but upload and
release are not CBF-certified until the gate actually runs.
