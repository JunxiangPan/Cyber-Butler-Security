# CBP rule changelog

Every CBP detection rule has one row here. The table is parsed by
`tools/audit_rule_sources.py`; an ID must not be a substring of another rule ID.

| Rule ID | Component | Source PR | Source issue | Failure class | Negative test | Positive test | Status |
|---|---|---|---|---|---|---|---|
| CBP-COV-001 | CBP | stage-b-seed | stage-b-seed | coverage below an enforce threshold | tests/test_rule_seeds.py::test_rule_cov_001_negative | tests/test_rule_seeds.py::test_rule_cov_001_positive | active |
| CBP-DEP-001 | CBP | stage-b-seed | stage-b-seed | unpinned or unhashed dependency lock, or installer without --require-hashes | tests/test_rule_seeds.py::test_rule_dep_001_negative | tests/test_rule_seeds.py::test_rule_dep_001_positive | active |
| CBP-CMT-001 | CBP | stage-b-seed | stage-b-seed | generic boilerplate public docstring | tests/test_rule_seeds.py::test_rule_cmt_001_negative | tests/test_rule_seeds.py::test_rule_cmt_001_positive | active |
| CBP-DOC-001 | CBP | stage-b-seed | stage-b-seed | documented file SHA256 mismatch | tests/test_rule_seeds.py::test_rule_doc_001_negative | tests/test_rule_seeds.py::test_rule_doc_001_positive | active |
| CBP-CLM-001 | CBP | stage-b-seed | stage-b-seed | release-note QUALITY_COUNTS mismatch | tests/test_rule_seeds.py::test_rule_clm_001_negative | tests/test_rule_seeds.py::test_rule_clm_001_positive | active |
