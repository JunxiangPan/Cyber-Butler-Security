# CBP roadmap

## Development Principles

CBP is governed by the CB ecosystem principles:

1. **Governance first**: configure CBP before feature code. Coverage, dependency
   hashes, comments, documentation locks, release claims, and SARIF are part of
   the definition of done.
2. **Zero deviation**: fake mocks, coverage games, deleted assertions, and
   hand-written evidence are defects. Do not lower the gate to match the code.
3. **Evidence over narrative**: every release claim must map to reproducible
   machine-readable evidence.
4. **Smooth upgrades**: minor releases never break existing configuration or CI;
   new checks are opt-in or safe by default; deprecations last at least two
   minor releases.
5. **CBS v1.6.4 is the first sample**: it becomes the template only after real
   CBP evidence, not after a narrative claim.

## Versioning law

CBP follows one rule above feature pressure:

> A minor upgrade must be safe enough that the user only changes the version
> number.

### Minor releases

- No breaking changes.
- Every new gate, rule, input, or config field is opt-in or has a safe default.
- Old configurations are accepted, or migrated in memory with a warning.
- Existing CI must keep working without a rewrite.

### Major releases

A major release is reserved for architecture changes that cannot be made
compatible, such as replacing the entire gate engine. Even then:

- the previous major line remains maintained;
- a migration guide is mandatory;
- an automated converter is provided when the mapping is mechanical;
- users choose when to move.

## Deprecation policy

```text
v0.1.x: document + DeprecationWarning, old behavior works
v0.2.x: old behavior works, warning becomes mandatory
v0.3.x or later: removal is allowed only after a migration path exists
```

No configuration item is removed in the same release that deprecates it.

## Current direction (v0.1.6)

- 80% language-neutral core: encoding, documentation locks, release claims,
  dependency policy, and provenance.
- 20% project-specific behavior: `custom_rules` plus configurable
  `evidence_readers`.
- Future CB projects can add rules for their language without changing CBP
  core source.

## Future candidates

- More evidence readers (JavaScript/TypeScript, Go, Rust).
- Signed release-body verification as a reusable Action.
- Richer SARIF locations for every gate.
- Migration tooling for major-version config changes.

These are candidates, not commitments. None may violate the minor-release
compatibility promise.
## v0.1.6 release boundary

v0.1.6 contains P0 fixes and the VM-driven guards only: source-hash coverage,
baseline/suppression, no-raw-interpreter, PowerShell AST parsing, required
artifact integrity, naked-subprocess rejection, and Python environment-path
checks. It deliberately does NOT include coverage-adapter rewrites, Action SHA
pinning, ReDoS limits, or architecture changes.

## v0.1.6 — P1/P2 engineering debt

- Add lcov and cobertura coverage readers/adapters without changing existing
  Python/hash behavior.
- Pin every GitHub Action to a commit SHA and add a policy check for floating
  tags (`@v4`, `@v5`).
- Add explicit ReDoS limits (pattern length, input size, timeout) to custom and
  built-in regex gates.
- Extend baseline/suppression to every gate and add a baseline expiry policy.
- Prebuild/install the CBP runtime instead of resolving it during install.
- Make `required_artifacts` a first-class, always-on input after the wheel is
  published and the CBS config can safely require v0.1.6.
- Add independent `cbp-verify` release verification and broader evidence
  readers.
