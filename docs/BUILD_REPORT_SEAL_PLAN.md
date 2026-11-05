# BUILD_REPORT Seal Plan

Status: design only. Not implemented.

## a. Is a separate seal still needed under A?

A signs the four-file payload, including `sha256(BUILD_REPORT)`. The report is
therefore integrity-protected against edits after signing. A separate seal is
not required for the basic A flow.

## b. Does PROOF_SHA256 form a closed loop?

Only partially. `BUILD_REPORT` contains `PROOF_SHA256`, and the four-file
signature covers both files. An attacker who changes both the proof and the
report must also produce a new signature over both hashes. That is the intended
boundary.

The A payload does **not** include the signature file or the public key in a
trusted root. If an attacker can replace the public key used by the verifier,
the check still fails open. Keep the public key pinned and outside the mutable
release directory.

## c. If the project rolls back to C (manifest-only)

C does not protect `BUILD_REPORT` or `ACCEPTANCE_PROOF`. A separate seal would
need to store both hashes in the signed manifest and verify them before
accepting the manifest. This is a stronger change and should not be introduced
silently.

## d. Redundant BUILD_REPORT hash in update-manifest.json?

Possible, but redundant under A: the report is already a direct member of the
signed payload. It adds complexity and a second source of truth. If added, the
manifest must be built after the report and the signed payload must define
whether the report hash includes the manifest reference (circularity).

Recommendation: keep A as the single signed payload; do not add a redundant
hash until there is a concrete verifier that needs it.
