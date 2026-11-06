# Releasing CBP

## Order matters

The release artifact is tied to one CI run and one commit. Do not tag first and
then look for a run.

1. Commit and push the release candidate.
2. Wait for CI to finish.
3. Confirm the dogfood job produced `quality-manifest-<run_id>`.
4. Record the exact commit SHA and the CI run id.
5. Create the annotated tag on that same commit:

   ```bash
   git tag -a v0.1.0 -m "CBP v0.1.0"
   git push origin v0.1.0
   ```

6. Trigger `release` manually with:

   ```text
   ci_run_id   = the dogfood run id
   release_tag = v0.1.0
   ```

7. The release workflow downloads only that run's artifact, verifies its
   SHA256, checks `ci_run_id` and `ci_commit_sha`, and uses the artifact's
   `RELEASE_NOTES.generated.md`.

If the tag points at a newer commit than the CI run, verification fails by
design. Re-run CI on the tag commit, then retry the release with the new run id.

## Placeholders

`allow_placeholders` is for local debugging only. In GitHub Actions it fails
closed. Replace `<YOUR_GITHUB_USER>` in README.md, SECURITY.md, and usage.yml
before releasing.

## Preconditions

- `v0.1.0` tag exists on the CI commit.
- CI artifact exists for the exact run id.
- `quality-manifest.json.sha256` matches.
- The artifact contains `docs/RELEASE_NOTES.generated.md`.
- Marketplace metadata is complete.
