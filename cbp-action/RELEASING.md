# Releasing CBP

## Order matters

The release artifact is tied to one CI run and one commit. Do not tag first and
then look for a run.

1. Commit and push the release candidate to `main`.
2. Wait for CI to finish. `ci.yml` runs on `push` to `main` and on pull
   requests; a tag push does **not** trigger a second CI run.
3. Confirm the dogfood job produced `quality-manifest-<run_id>`.
4. Record the exact commit SHA and the CI run id.
5. Create the annotated tag on that same commit:

   ```bash
   git tag -a v0.1.6 -m "CBP v0.1.6"
   git push origin v0.1.6
   ```

6. Push the tag. Tag pushes do not trigger CI and do not trigger the
   release automatically; `release` is manual-only. Use the CI run id that
   belongs to the tagged commit.
7. Trigger `release` manually with:

   ```text
   ci_run_id   = the dogfood run id
   release_tag = v0.1.6
   ```

8. The release workflow downloads only that run's artifact, verifies its
   SHA256, checks `ci_run_id` and `ci_commit_sha`, and uses the artifact's
   `RELEASE_NOTES.generated.md`.

If the tag points at a newer commit than the CI run, verification fails by
design. Re-run CI on the tag commit, then retry the release with the new run id.

## Local final check

Run these in order:

1. If any tracked documentation changed, update `docs/history-manifest.json`
   first. Otherwise the docs gate fails before manifest generation.
2. Generate a local-only manifest:
   ```bash
   GITHUB_ACTIONS=false python tools/dogfood_manifest.py --root .
   ```
3. Run the full gate against that local manifest:
   ```bash
   python -m cbp.cli --root . --mode enforce
   ```
4. Do not commit the generated `quality-manifest.json`,
   `quality-manifest.json.sha256`, or `docs/RELEASE_NOTES.generated.md`.
   They are local-only and ignored by `.gitignore`.

Expected order:

```text
docs hash updated -> dogfood manifest -> cbp.cli PASS
```

The generated `quality-manifest.json` and `docs/RELEASE_NOTES.generated.md`
are local-only and ignored by git.

## Local manifest debugging

Do not set `GITHUB_ACTIONS=true` for local debugging. Set it to `false` or leave
it unset, then run the generator with local placeholder metadata:

```bash
GITHUB_ACTIONS=false python tools/dogfood_manifest.py --root .
```

A local manifest has empty `ci_run_id`/`ci_commit_sha`; it is for local
verification only and must never be uploaded as a release artifact. The
generator does not require a numeric run id, but `validate_manifest(actions=true)`
requires non-empty metadata.

## Branch protection

Before publishing, configure the `main` branch:

- require a pull request review before merging;
- require the `cbp-ci` status checks to pass;
- require branches to be up to date before merging;
- restrict who can push to `main`.

## Failure recovery

### Tag is wrong, release not created

```bash
git tag -d v0.1.6
git push origin :refs/tags/v0.1.6
# fix the commit, rerun CI, retag the exact CI commit
git tag -a v0.1.6 -m "CBP v0.1.6"
git push origin v0.1.6
```

### Release exists with wrong assets

```bash
gh release delete v0.1.6 --yes
# fix, rerun CI, and create the tag only after CI passes
```

Do not move an existing tag to a different commit. Delete and recreate it only
while the release is still being corrected.

### Marketplace release is wrong

GitHub Marketplace does not provide a true unpublish button. Publish a new
patch release (`v0.1.6`) with corrected assets and notes. Validate the Action
from `examples/sample-project` before publishing.

## Placeholders

`allow_placeholders` is for local debugging only. In GitHub Actions it fails
closed. Replace `JunxiangPan` in README.md, SECURITY.md, and usage.yml
before releasing.

## Preconditions

- `v0.1.6` tag exists on the CI commit.
- CI artifact exists for the exact run id.
- `quality-manifest.json.sha256` matches.
- The artifact contains `docs/RELEASE_NOTES.generated.md`.
- Marketplace metadata is complete.
