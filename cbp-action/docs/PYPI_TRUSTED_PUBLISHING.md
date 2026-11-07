# PyPI Trusted Publishing

CBP does **not** store a PyPI API token in GitHub. Publishing uses OIDC and
Trusted Publishing.

## One-time PyPI configuration

In the PyPI project, add a Trusted Publisher:

```text
Owner:       JunxiangPan
Repository:  cbp-action
Workflow:    pypi-publish.yml
Environment: pypi
```

## GitHub environment

Create the `pypi` environment under:

```text
Settings -> Environments -> pypi
```

Recommended protections:

```text
Required reviewers
Deployment branches: main or v*
```

## Release flow

```text
1. Run the CBP CI workflow on main.
2. Create the vX.Y.Z tag and GitHub Release.
3. The release event runs pypi-publish.yml.
4. The job requests an OIDC token and publishes without a long-lived secret.
```

## Verification

```bash
pipx install cbp-action
cbp --help
```

For a dry run, point the publish step at TestPyPI first, then switch the
Trusted Publisher to the real PyPI project.

## Failure modes

- `id-token: write` missing -> OIDC token cannot be issued.
- Environment name mismatch -> PyPI rejects the publisher.
- Workflow name mismatch -> PyPI rejects the publisher.
- Version already exists on PyPI -> upload is rejected; bump the version.
