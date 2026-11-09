# CBS Build-once Findings

Facts verified against `tools/Run-ReleasePipeline.ps1`:

- It requires Windows: `pwsh.exe`, `Get-NetAdapter`, Pester, `Get-FileHash`,
  and a default `C:\CyberButler` install root.
- It refuses a dirty working tree and requires `HEAD == origin/release/v<VERSION>`.
- It requires a non-empty human challenge and `ACCEPTANCE_PROOF.md` with
  `Overall: PASS`, `negative_403=True`, and `negative_path=True`.
- It builds `public-release-v<VERSION>.zip` via `tools/package_release.py` and
  checks `update-manifest.sig` exists and verifies.
- `-Sign` does **not** create a signature; it only prints a reminder. The
  signature must be produced by a separate step and must be present before the
  pipeline's RSA verification passes.
- Therefore CBS build-once must be `build_runner: windows-latest`,
  `build_shell: pwsh`, and signing must be a separate `sign-artifact` job.

## Confirmed ordering and circular dependency

The current one-shot pipeline cannot produce a new signed release in a single
run without an ordering fix.

Observed order in `tools/Run-ReleasePipeline.ps1`:

1. gates run;
2. `tools/package_release.py` builds the ZIP;
3. `package_release.py` writes `update-manifest.json` before writing the ZIP,
   and embeds the manifest in the ZIP;
4. the pipeline writes `BUILD_REPORT.md`;
5. only then it checks that `update-manifest.sig` exists and verifies it.

`tools/sign_release.py` signs a four-file payload:

```text
sha256(update-manifest.json)
sha256(BUILD_REPORT.md)
sha256(FINAL_QA_REPORT.md)
sha256(ACCEPTANCE_PROOF.md)
```

`-Sign` does not sign; it only prints a reminder. The signature must already
exist when step 5 runs.

Therefore the sign step cannot simply be placed before or after one full
pipeline run:

- before the pipeline: `update-manifest.json` and the final `BUILD_REPORT.md`
  do not exist yet;
- after the pipeline: the pipeline has already failed its signature gate;
- rerunning the pipeline changes `BUILD_REPORT.md` (build time/challenge), so a
  signature created after run 1 will not verify in run 2.

The pipeline must be split into two explicit phases:

```text
build-unsigned:
  run gates and package_release; write update-manifest.json, BUILD_REPORT.md,
  FINAL_QA_REPORT.md, ACCEPTANCE_PROOF.md, and the ZIP; do NOT require sig.

sign-artifact:
  download build-unsigned artifact;
  sign the four-file payload with the release key;
  produce update-manifest.sig;
  upload signed-artifact.

verify-publish:
  download signed-artifact;
  verify RSA signature;
  generate RELEASE_ASSETS.sha256 including zip, manifest, sig;
  publish.
```

The signature is a separate release asset; it must not be embedded inside the
ZIP (the current packaging excludes `update-manifest.sig`).
