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
