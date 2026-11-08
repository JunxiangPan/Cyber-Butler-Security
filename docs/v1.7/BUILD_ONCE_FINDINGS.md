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
