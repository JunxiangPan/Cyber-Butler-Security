# CBP rule registry

`registry.json` is the source of truth for detection rules. Each entry binds:

- a rule ID;
- the gate that owns it;
- the source component, PR, and issue;
- a negative test that must block a violating sample;
- a positive test that must allow a compliant sample.

Both test fields are full pytest node IDs. CI must collect and execute both
nodes. A missing, uncollected, or failing node blocks the merge.

Rule IDs are append-only. Mark a retired rule `"status": "deprecated"`; do not
delete it. Source fields are immutable except for a documented typo correction in
`RULES-CHANGELOG.md`.

The audit tool that enforces this registry is introduced in stage B after this
registry is reviewed.
