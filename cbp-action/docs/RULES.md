# CBP Rule Index

| Rule ID | Gate | Meaning |
|---|---|---|
| CBP-CMT-001 | comments | Public API docstring and boilerplate-comment checks |
| CBP-COV-001 | coverage | Per-group statement coverage and source-hash freshness |
| CBP-CST-001 | custom | Configured regex/literal rules, path escapes, artifact integrity |
| CBP-DEP-001 | dependency | Hash-pinned dependency lock verification |
| CBP-DOC-001 | docs | Documentation history hash verification |
| CBP-BIN-001 | binary | Binary provenance and size policy |
| CBP-CLM-001 | claims | Release-note counts and manifest reconciliation |
| CBP-UPG-001 | upgrade | Upgrade fixture and schema migration checks |
| CBP-PS1-001 | custom | PowerShell AST syntax parsing |

Inline suppression:

```text
# cbp: ignore=CBP-CMT-001
```

Baseline generation:

```bash
python -m cbp.cli --root . --generate-baseline cbp-baseline.json
```
