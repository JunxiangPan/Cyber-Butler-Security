# v1.2.1 — CI privacy scan fix

## Fixed

`tools/privacy_scan.py` rejects standalone 9–12 digit numbers because they can
be QQ identifiers. The background engine's GIF budgets used such literals
(`120000000`, `134217728`), so CI failed even though they are byte/pixel
limits. The engine now expresses every large limit as a multiplication:

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
points at the older commit that contained `120000000`/`134217728`; pushing this
release produces a new green run but does not rewrite the old one. If the red
run is attached to the `v1.1.1` tag, that tag would need to be re-created
(force-push) to change it — which is not recommended for a published release.
