# CBP roadmap

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

## Current direction (v0.1.2)

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
