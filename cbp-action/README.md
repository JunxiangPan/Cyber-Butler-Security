# Cyber Butler Pipeline (CBP)

CBP is a standalone set of repository gates for coverage, hash-locked
dependencies, comment quality, incident-history manifests, release binaries,
and release-note claims.

## Local CLI

```bash
python -m pip install -e .
python -m cbp.cli --root /path/to/repo --config cbp.json
```

`audit` mode prints failures but exits 0; `enforce` returns non-zero on any
failure.

```bash
python -m cbp.cli --root . --mode audit
python -m cbp.cli --root . --mode enforce
```

## GitHub Action

```yaml
- uses: your-org/cbp-action@<pinned-sha>
  with:
    root: .
    coverage-threshold: "80"
    policy-coverage-threshold: "85"
    enable-coverage: "true"
    enable-dependency: "true"
    enable-comments: "true"
    enable-docs: "true"
    enable-binary: "true"
    enable-claims: "false"
    mode: enforce
```

The action writes `result=CBP_RESULT=PASS` or `CBP_RESULT=FAIL` to
`$GITHUB_OUTPUT`.

## Configuration

See `schemas/config.schema.json`. Paths are resolved relative to `root`.
Every gate can be disabled with its `enable-*` field.

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
- comments: public docstrings, argument names, slop comments
- docs: incident manifest hashes
- binary: `.build.json` / `.sbom.json` provenance
- claims: release-note `QUALITY_COUNTS` vs `quality-manifest.json`

## Status

CBP-0 and CBP-1 are implemented. CBS still owns the thin `quality/*.py`
wrappers; the full release pipeline shadow run remains pending.
