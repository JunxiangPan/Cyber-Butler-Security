# CBP sample project

A minimal Python project that shows the expected config layout and workflow.

```text
sample-project/
├── .cbp/
│   ├── config.json
│   └── coverage_allowlist.json
├── .github/workflows/ci.yml
├── pyproject.toml
├── src/sample_project/__init__.py
└── tests/test_sample.py
```

Run locally:

```bash
python -m pip install coverage pytest
python -m coverage run --branch -m pytest -q
python -m coverage json -o coverage.json
cbp --root . --config .cbp/config.json
```

The workflow shows the same project calling the Action from GitHub Actions.
