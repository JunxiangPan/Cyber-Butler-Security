# CBP —Coverage and Build Policy

> **Before publishing:** globally replace `JunxiangPan` with your GitHub username or organization.

A reusable, self-hosted quality gate for repositories that do not want to
trust a green check without evidence.

CBP is intentionally small: Python standard library at runtime, JSON/TOML
configuration, and one CLI used by both GitHub Actions and local CI.

## What it catches

| Gate | What it rejects |
|---|---|
| coverage | measured coverage below the configured floor, or missing allowlist entries |
| dependency | unpinned packages, missing SHA256 hashes, installers without `--require-hashes` |
| comments | public functions/classes without docstrings, missing `Args` names, generic boilerplate, `# Send ...`-style comments |
| docs | files whose SHA256 no longer matches the documentation manifest |
| binary | large binaries without `.build.json`/`.sbom.json`, or provenance hash/size mismatches |
| claims | release notes whose `QUALITY_COUNTS` do not match the generated manifest |
| encoding | tracked text files that are not strict UTF-8 or carry a BOM |

It is designed to make fake tests, fake coverage, dependency substitution,
copy-paste comments, and edited evidence fail closed.

## GitHub Action

```yaml
- uses: JunxiangPan/cbp-action@v0.1.1
  with:
    root: .
    config: .cbp/config.json
    coverage-json: coverage.json
    coverage-allowlist: .cbp/coverage_allowlist.json
    coverage-threshold: "80"
    policy-coverage-threshold: "85"
    dependency-lock: requirements.lock
    install-command: installer/install.ps1
    docs-manifest: .cbp/docs-manifest.json
    binary-artifacts: artifacts
    claims-manifest: quality-manifest.json
    claims-notes: RELEASE_NOTES.md
    enable-coverage: "true"
    enable-dependency: "true"
    enable-comments: "true"
    enable-docs: "true"
    enable-binary: "true"
    enable-claims: "false"
    mode: enforce
```

The output is written to `$GITHUB_OUTPUT` as:

```text
result=CBP_RESULT=PASS
```

or `CBP_RESULT=FAIL`.

### Inputs

| Input | Meaning |
|---|---|
| `root` | Repository root |
| `config` | Optional CBP JSON/TOML config |
| `coverage-json` | coverage.py JSON output |
| `coverage-allowlist` | Allowlist JSON |
| `coverage-threshold` | Legacy single-group threshold |
| `policy-coverage-threshold` | Legacy policy threshold |
| `dependency-lock` | Hash-locked requirements file |
| `install-command` | Installer that enforces `--require-hashes` |
| `docs-manifest` | Document SHA256 manifest |
| `binary-artifacts` | `.build.json` / `.sbom.json` directory |
| `package-zip` | Optional release ZIP |
| `claims-manifest` | Generated `quality-manifest.json` |
| `claims-notes` | Generated release notes |
| `enable-coverage` | Enable coverage gate |
| `enable-encoding` | Enable strict UTF-8 no-BOM gate |
| `enable-dependency` | Enable dependency gate |
| `enable-comments` | Enable comment gate |
| `enable-docs` | Enable docs gate |
| `enable-binary` | Enable binary gate |
| `enable-claims` | Enable claims gate |
| `mode` | `audit`, `warn`, or `enforce` |

### Required path inputs

All path inputs are optional. A path is required only when its gate is enabled;
the gate fails closed with an explicit missing-path error if it is enabled
without the corresponding input.

### Quick start

The canonical, copyable workflow is [`usage.yml`](usage.yml). It runs
coverage and then calls the Action with only the gates it enables.

## Local CLI

```bash
python -m pip install -e ".[test]"
python -m cbp.cli --root /path/to/repo --config .cbp/config.json
```

`audit` mode reports failures but exits zero; `enforce` exits non-zero.

```bash
python -m cbp.cli --root . --mode audit
python -m cbp.cli --root . --mode enforce
```

## Configuration

See [`schemas/config.schema.json`](schemas/config.schema.json).

```json
{
  "coverage_json": "coverage.json",
  "coverage_allowlist": ".cbp/coverage_allowlist.json",
  "target_files": ["src/example.py"],
  "policy_file": "src/example.py",
  "coverage_threshold": 80,
  "policy_threshold": 85,
  "comment_files": ["src/example.py"],
  "enable_claims": false
}
```

All paths are relative to `root`. Every gate can be disabled with its
`enable_*` field or the matching Action input.

### Coverage groups

Coverage is configured as named groups. Each group can be `enforce` (a failure
fails the Action) or `warn` (reported but non-blocking). This supports gradual
adoption without a temporary lower global threshold.

```json
{
  "coverage_json": "coverage.json",
  "coverage_allowlist": "coverage_allowlist.json",
  "coverage_groups": [
    {"name": "core", "files": ["src/core.py"], "threshold": 80, "mode": "enforce"},
    {"name": "auditors", "files": ["src/audit_*.py"], "threshold": 0, "mode": "warn"},
    {"name": "webui", "files": ["webui/**/*.py"], "threshold": 0, "mode": "warn"}
  ]
}
```

Suggested migration:

```text
1. Start every new group with mode "warn" and threshold 0.
2. Add tests and raise the group threshold.
3. When the group is stable, change mode to "enforce".
```

`target_files`, `target_files`, `policy_file`, `coverage_threshold`, and
`policy_threshold` remain supported for single-group configurations.

## Self-test

```bash
cd cbp-action
python -m pip install -e ".[test]"
python -m coverage run --branch --source=src/cbp,tools -m pytest -q tests
python -m coverage json -o coverage.json
python -m cbp.cli --root . --mode enforce
```

The package has no runtime dependencies outside the Python standard library.
`pytest` and `coverage` are optional test dependencies.

CBP is distributed through GitHub Actions and GitHub Releases only. It is not
published to PyPI; the top-level import package is `cbp` for the action runtime.

The manifest is checksum + run-id pinned. It is not an OIDC attestation or a
cryptographic signature.

`security_core` coverage is the coverage of the gate modules, config, CLI,
encoding gate, and rule auditor; it is not a separate binary-security metric.

## Releasing

See [`RELEASING.md`](RELEASING.md) for the commit -> CI -> tag -> release order.

## Status

v0.1.1 is a standalone release candidate. It does not import anything from
the host product's `quality/`, `checks/`, or `tools/` directories.

### Coverage numbers in CI

CI coverage may differ from local by ±0.5% due to platform-specific line
coverage. The gate uses the CI value.

