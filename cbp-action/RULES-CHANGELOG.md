# CBP rule changelog

Every CBP detection rule has one entry here. The entry records where the rule
came from and which tests prove both directions.

## Format

```text
## <RULE-ID> — <date>
- Component: CBS | CBP | CBR | CBM | CBC
- Source PR: <url or number>
- Source issue: <url or number>
- Failure class: <short description>
- Negative test: <pytest node id>
- Positive test: <pytest node id>
- Registry status: active | deprecated
```

## Rules

### CBP-COV-001 — 2026-11-06

- Component: CBP
- Source PR: stage-b-seed
- Source issue: stage-b-seed
- Failure class: coverage below an enforce threshold
- Negative test: `tests/test_rule_seeds.py::test_rule_cov_001_negative`
- Positive test: `tests/test_rule_seeds.py::test_rule_cov_001_positive`
- Registry status: active

### CBP-DEP-001 — 2026-11-06

- Component: CBP
- Source PR: stage-b-seed
- Source issue: stage-b-seed
- Failure class: unpinned or unhashed dependency lock, or installer without `--require-hashes`
- Negative test: `tests/test_rule_seeds.py::test_rule_dep_001_negative`
- Positive test: `tests/test_rule_seeds.py::test_rule_dep_001_positive`
- Registry status: active

### CBP-CMT-001 — 2026-11-06

- Component: CBP
- Source PR: stage-b-seed
- Source issue: stage-b-seed
- Failure class: generic boilerplate public docstring
- Negative test: `tests/test_rule_seeds.py::test_rule_cmt_001_negative`
- Positive test: `tests/test_rule_seeds.py::test_rule_cmt_001_positive`
- Registry status: active

### CBP-DOC-001 — 2026-11-06

- Component: CBP
- Source PR: stage-b-seed
- Source issue: stage-b-seed
- Failure class: documented file SHA256 mismatch
- Negative test: `tests/test_rule_seeds.py::test_rule_doc_001_negative`
- Positive test: `tests/test_rule_seeds.py::test_rule_doc_001_positive`
- Registry status: active

### CBP-CLM-001 — 2026-11-06

- Component: CBP
- Source PR: stage-b-seed
- Source issue: stage-b-seed
- Failure class: release-note QUALITY_COUNTS mismatch
- Negative test: `tests/test_rule_seeds.py::test_rule_clm_001_negative`
- Positive test: `tests/test_rule_seeds.py::test_rule_clm_001_positive`
- Registry status: active
