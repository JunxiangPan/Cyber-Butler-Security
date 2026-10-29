# v1.0.8 — Desktop Update GUI

## Added

- `tools/update_gui.ps1`: WPF desktop update window.
- `tools/update_gui.vbs`: no-console launcher through `wscript.exe`.
- `tools/create_update_shortcut.ps1`: creates the desktop shortcut
  `检查苏瑾言更新`.
- Skip-version support in `tools/check_update.ps1` and `tools/skip_version.json`.
- `-StatusFile` phase reporting and `-ConfirmationText` validation in
  `tools/update_merge.ps1`.
- Smooth GUI progress when the status file is unchanged.
- Automatic close after “already latest” and “skipped version” messages.

## Security

- The GUI is only a shell.
- Production updates call `update_merge.ps1`, never `update.ps1`.
- `UPDATE PRODUCTION` is still required; `-Yes` cannot bypass it.
- Protected data/config/token paths reject the whole package.
- Runtime files are rendered from `local-overlay.json`; README/docs/tests keep
  `YOUR_*` placeholders.
- No GPG/minisign publisher signature yet: GitHub asset SHA-256 plus manifest
  hashes only.

## Verification

```text
30 tests passed
25 PowerShell scripts parsed
25 PowerShell scripts have UTF-8 BOM
```
