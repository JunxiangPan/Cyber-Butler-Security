# Cyber Butler Pipeline (CBP)

CBP is a standalone set of repository gates for coverage, hash-locked
dependencies, comment quality, incident-history manifests, release binaries,
and release-note claims.

There are **no CBS paths baked into the Action**. Every path input is empty by
default and must be supplied by the calling project.

## GitHub Action

```yaml
- uses: your-org/cbp-action@<pinned-sha>
  with:
    root: .
    coverage-json: coverage.json
    coverage-allowlist: coverage_allowlist.json
    coverage-threshold: "80"
    policy-coverage-threshold: "85"
    dependency-lock: requirements-runtime.lock
    installer-core: installer/lib/Installer.Core.ps1
    docs-manifest: docs/history-manifest.json
    binary-artifacts: artifacts
    claims-manifest: quality-manifest.json
    claims-notes: docs/releases/RELEASE_NOTES.md
    enable-coverage: "true"
    enable-dependency: "true"
    enable-comments: "true"
    enable-docs: "true"
    enable-binary: "true"
    enable-claims: "true"
    mode: enforce
```

The action writes `result=CBP_RESULT=PASS` or `CBP_RESULT=FAIL` to
`$GITHUB_OUTPUT`.

## Local CLI

```bash
python -m pip install -e .
python -m cbp.cli --root /path/to/repo --config .cbp/config.json
```

`audit` mode prints failures but exits zero; `enforce` exits non-zero.

```bash
python -m cbp.cli --root . --mode audit
python -m cbp.cli --root . --mode enforce
```

## Configuration

See `schemas/config.schema.json`. All paths are resolved relative to `root`.
Every gate can be disabled with its own `enable-*` flag.

```json
{
  "coverage_json": "coverage.json",
  "coverage_allowlist": "coverage_allowlist.json",
  "broker_files": ["src/broker.py"],
  "policy_file": "src/broker.py",
  "coverage_threshold": 80,
  "policy_threshold": 85,
  "comment_files": ["src/broker.py"],
  "enable_claims": false
}
```

## Gates

- coverage: policy and allowlisted broker coverage
- dependency: pinned packages, SHA256 hashes, `--require-hashes`
- comments: public docstrings, argument names, generic boilerplate, and slop comments
- docs: incident manifest hashes
- binary: `.build.json` / `.sbom.json` provenance and SBOM binary hash
- claims: release-note `QUALITY_COUNTS` vs `quality-manifest.json`

## Status

CBP-0 and CBP-1 are implemented. CBS owns thin `quality/*.py` wrappers; CBP does
not import `quality/`, `checks/`, or `tools/` from CBS.
