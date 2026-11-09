# CBE-08 upstream unblock evidence

Status: **CONTRACT RC PROVIDES THE F2 SET; CBE-08 STILL NEEDS A CBE-SIDE IMPLEMENTATION AFTER HUMAN FREEZE.**

Contract candidate:

```text
docs/v1.7/CONTRACT.md
SHA256 c1653cfe1adbc74d2523d2fa12c965ab761fce978061c8e55443eb8b6db3a7e5
```

The candidate contains the F2 blocking set:

```text
three structural checks
  (manifest validation, no-bypass enforcement, provider output missing/invalid)
+ any manifest rule with gate: "blocking"
```

It also requires blocking rules to match the manifest's top-level
`package_types`; blocking rules may not be SKIPPED.

This removes the **contract-side** ambiguity tracked by CBE B-29. It does not
modify CBE and does not make CBE-08 pass: CBE must implement its CBE-08 assertions
against the frozen contract after human approval. The CBE checkout remains
pinned to `4a437df`; that pin was not changed.
