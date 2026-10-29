# v1.2.2 — Unified install tree

## Changed

- `create_dashboard_shortcut.ps1` now always targets
  `<ProjectRoot>\tools\cyber_butler_dashboard.vbs`, even when it is executed
  from the release tree. The desktop shortcut, the running dashboard code, the
  `VERSION` file and the updater now all live under the same install root.
- The install root's `tools/` directory is synced with this release:
  dashboard, background engine, settings/theme resources, plugin ecosystem
  (hub, market, scanner, module loader, review dialog), restore helper and
  updater are identical to the packaged files.
- `VERSION` is `1.2.2` in both the install root and the release tree, so the
  version label, the time machine and the running code can no longer disagree.

## Why

The previous shortcut pointed at `public-release\tools\`, while the updater
modified `D:\qq苏瑾言大肥鱼`. A successful reinstall/downgrade changed the root
version label but not the interface that was actually running. The shortcut now
starts the root launcher, so an update changes the code that opens next time.

## Verification

```text
root dashboard: DASHBOARD_XAML_OK / DASHBOARD_SETTINGS_OK / LOADED hello_world
root hello_world: click 1 -> 2 -> 3
packaged tests: 39 passed
privacy scan: OK
```

## Note

Moving the install root's ACL-guarded `tools/` needed one elevated copy
(UAC). Future updates replace those files through `update_merge.ps1` as usual.
