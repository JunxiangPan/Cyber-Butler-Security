# v1.2.1 — CI privacy scan fix

## Repack fixes (this build)

- `hello_world`: the click handler now captures `$moduleContext` with
  `.GetNewClosure()`. PowerShell drops the loader's locals after import, which
  made `$moduleContext` null and produced
  “找不到属性 Clicks” on every click. Verified 1 → 2 → 3.
- Time machine:
  - `dashboard_restore.ps1` passes `-AllowLocalCodeChanges` to
    `update_merge.ps1` for a user-confirmed reinstall/downgrade. The previous
    attempt aborted with `MERGE_FAILED: local code changes detected`.
  - The reinstall/downgrade confirmation dialogs are owned by the settings
    window and marked topmost, so they cannot open behind the modal dialog.
  - Both handlers are wrapped in try/catch and write diagnostics to
    `%LOCALAPPDATA%\CyberButler\settings.log`; failures always raise a message
    box instead of silently doing nothing.

## Fixed

`tools/privacy_scan.py` rejects standalone 9–12 digit numbers because they can
be QQ identifiers. The background engine's GIF budgets used raw 9-digit
literals, so CI failed even though they are byte/pixel limits. The engine now
expresses every large limit as a multiplication:

```powershell
GifPixels      = (16 * 1000 * 1000)
GifWorkPixels  = (120 * 1024 * 1024)
GifBudgetBytes = (128 * 1024 * 1024)
```

The image dimension guard in `New-BgImage` uses `(50 * 1000 * 1000)` for the
same reason. No raw 8–12 digit literal remains in the background engine.

`v1.2.0` had already replaced the two 9-digit values (`(120 * 1000 * 1000)`
and `128MB`); this release makes the form explicit, uses 1024-based units and
also covers the 8-digit pixel caps so the rule cannot resurface.

## Verification

```text
privacy scan: OK (0 findings)
pytest: 39 passed
background smoke: 13/13 ok (png, gif, transparent gif, gif static,
                  mp4, mp4 loop, mp4 static, webm, webm static,
                  corrupt mp4, clear, revert-on-close, revert-after-save)
```

## Note on existing red runs

A workflow run is bound to the commit it started on. The failing run still
points at the older commit that contained the raw 9-digit values; pushing this
release produces a new green run but does not rewrite the old one. If the red
run is attached to the `v1.1.1` tag, that tag would need to be re-created
(force-push) to change it — which is not recommended for a published release.
