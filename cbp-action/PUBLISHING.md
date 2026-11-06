# Publishing CBP v0.1.1

This guide assumes the CBS repository contains `cbp-action/`. The directory is
self-contained: it has its own `pyproject.toml`, tests, workflows, docs, and
examples.

## 1. Create the standalone repository

Option A —subtree split, preserves history:

```bash
cd /path/to/Cyber-Butler-Security
git subtree split --prefix=cbp-action -b cbp-v0.1.1
git checkout cbp-v0.1.1
git remote add cbp https://github.com/JunxiangPan/cbp-action.git
git push cbp cbp-v0.1.1:main
```

Option B —copy the directory:

```bash
mkdir cbp-action-repo
cp -a cbp-action/. cbp-action-repo/
cd cbp-action-repo
git init
git add .
git commit -m "CBP v0.1.1"
git branch -M main
git remote add origin https://github.com/JunxiangPan/cbp-action.git
git push -u origin main
```

Before the first push, see the exact file list:

```text
action.yml
pyproject.toml
README.md
LICENSE
CHANGELOG.md
SECURITY.md
CONTRIBUTING.md
PUBLISHING.md
usage.yml
schemas/
src/cbp/
tests/
examples/
.github/workflows/ci.yml
.github/workflows/release.yml
.github/ISSUE_TEMPLATE/
```

## 2. Replace the publishing placeholder

```bash
grep -R "JunxiangPan" .
```

Replace every hit with the real owner. Commit the replacement.

## 3. Tag and release

```bash
git tag -a v0.1.1 -m "CBP v0.1.1"
git push origin v0.1.1
```

A tag push does **not** trigger CI or the release workflow. The release is
manual-only: trigger `.github/workflows/release.yml` with the CI run id and the
tag. It downloads that run's manifest artifact, verifies the SHA256, checks the
run id and commit, then publishes:

```text
python -m build
gh release create v0.1.1 dist/* ... --notes-file artifact/docs/RELEASE_NOTES.generated.md
```

Verify the release has:

```text
cbp_action-0.1.1-py3-none-any.whl
cbp_action-0.1.1.tar.gz
```

## 4. Pin the Action by commit SHA

Marketplace and GitHub Actions should use a tag while evaluating, but production
workflows should pin the exact commit:

```yaml
uses: JunxiangPan/cbp-action@<FULL_COMMIT_SHA>
```

Do not trust a moving minor tag for a security gate.

## 5. Marketplace metadata

Create a release, then open Marketplace publishing for the repository.
Recommended metadata:

```text
Name: CBP —Coverage and Build Policy
Category: Security
Description: Fail closed on fake coverage, unpinned dependencies,
             boilerplate comments, tampered docs, and unsigned binaries.
```

The `action.yml` is the Marketplace manifest. Review `README.md`, `LICENSE`,
`SECURITY.md`, and the release assets before publishing.

## 6. Post-publish checks

```bash
# In a fresh consumer repository:
grep -R "JunxiangPan" .
python -m cbp.cli --root . --mode enforce
```

Also verify that `examples/sample-project/.github/workflows/ci.yml` has been
updated from `@v0.1.1` to the released commit SHA.
