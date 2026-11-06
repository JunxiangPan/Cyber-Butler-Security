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

## Current direction (v0.1.4)

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
