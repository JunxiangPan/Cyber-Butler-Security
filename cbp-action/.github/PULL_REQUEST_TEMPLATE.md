# Pull request

## Problem

What failure mode does this change prevent? Link the issue or disclosure.

## Business fix

What changed in the product code, and why is it the smallest safe fix?

## CBP detection rule

Rule ID:

Registry entry:

- [ ] `rules/registry.json` contains this rule.
- [ ] `RULES-CHANGELOG.md` records component, PR, issue, and rule ID.
- [ ] The rule is not a temporary string match when evidence can be recomputed.

## Tests

Negative test (violating sample must be blocked):

```text
pytest node id:
```

Positive test (compliant sample must be allowed):

```text
pytest node id:
```

- [ ] Both node IDs are registered in `rules/registry.json`.
- [ ] `python -m pytest <negative-node-id>` passes.
- [ ] `python -m pytest <positive-node-id>` passes.
- [ ] `python tools/audit_rule_sources.py --root .` passes.

## Reflection exception

If CBP cannot or should not detect this issue:

```text
Reason:
Human approval:
```

A missing rule without an approved exception is a failing review.
