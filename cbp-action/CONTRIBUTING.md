# Contributing

## Rules

- Tests must exercise real behavior. Do not add a test that only asserts a
  constant that the test itself set.
- Coverage must not decrease. If a line is untestable, document why and add the
  smallest possible testable exception.
- Do not use `# pragma: no cover` to hide logic. Do not exempt a whole module.
- Do not add a gate that fails closed only when a magic string is present;
  recompute the evidence.
- Keep runtime dependencies at zero unless a gate truly requires a library.
- Every public function or class needs a docstring and accurate parameter names.

## Local checks

```bash
python -m pip install -e ".[test]"
python -m coverage run --branch -m pytest -q tests
python -m coverage json -o coverage.json
python -m cbp.cli --root . --mode enforce
```

## Pull requests

Describe the failure mode the change prevents. Include the test that would fail
without the change and the command output showing it now passes.

## CB governance checks

CBP is the calibrator, not an exception. Every CBP change must pass the six
gates:

```bash
python -m pip install -e ".[test]"
python -m coverage run --branch -m pytest -q tests
python -m coverage json -o coverage.json
python -m cbp.cli --root . --mode enforce
python tools/audit_rule_sources.py --root .
```

New gate types or rule categories must update the registry and the schema.

## Problem reflection mechanism

When any CB component (CBS, CBR, CBM, CBC, or CBP) discovers a new failure class,
the fix pull request must contain three parts:

1. the business-code fix;
2. the CBP detection rule;
3. a negative test that constructs a violating sample and asserts CBP blocks it,
   plus a positive test that constructs a compliant sample and asserts CBP allows
   it.

Register both tests by full pytest node ID in `rules/registry.json`. CI collects
each node and executes it; a missing or failing node blocks the merge. A rule
without a negative test and a positive test is not mergeable.

Record the source in `RULES-CHANGELOG.md`: component, PR, issue, rule ID, and both
node IDs. If CBP cannot detect the issue, or should not, the pull request must
state the reason and a human must approve the exception.

`rules/registry.json` is append-only for rule IDs. An existing rule may be marked
`deprecated`, never deleted. Source fields may only be corrected for a documented
typo recorded in `RULES-CHANGELOG.md`.
