# v1.2.0 — Plugin Ecosystem

## Added

### AstrBot Hub (`tools/plugin_hub.ps1`)

- Plugin list from `GET /api/plugin/get` (authoritative `activated` state),
  with a `metadata.yaml` filesystem fallback when AstrBot is offline.
- Enable / disable through `/api/plugin/on|off`, which reloads only the target
  plugin; no stack restart.
- Delete moves the directory to `backups/deleted_plugins/<dir>-<timestamp>` and
  records the move in `deleted.log`; reserved plugins are refused.
- Restore defaults backs up and removes `<root_dir>_config.json`, then reloads
  so AstrBot regenerates schema defaults.
- New dashboard tab with status, version, author, AstrBot compatibility and a
  details pane.

### Dashboard modules (`tools/dashboard_modules.ps1`)

- Standard module format: `tools/dashboard_plugins/<id>/manifest.json` +
  `ui.xaml` + optional `logic.ps1`.
- Enabled modules become tabs at startup; disabled modules load neither XAML
  nor script. State lives in `%LOCALAPPDATA%\CyberButler\dashboard-modules.json`.
- Isolated script scope with `$moduleContext` (`Root`, `Tab`, `Host`, `State`,
  `Log`, `T`, paths) and an optional `Initialize-DashboardModule($context)`.
- Failure isolation: broken manifest, broken XAML and throwing logic remove the
  module only; `Dispatcher.UnhandledException` catches runtime exceptions from
  module handlers and keeps the dashboard alive.
- Reference module `hello_world` with a live counter.

### Market and security (`tools/plugin_market.ps1`, `plugin_security_scanner.ps1`)

- Search the AstrBot official registry (cached) or GitHub repositories.
- Download HTTPS zips with size, entry-count and zip-slip guards.
- Static review of all `.py` files with high/medium/low findings and
  `file:line` context. High findings turn the review dialog red and require
  typing `INSTALL ANYWAY`.
- AstrBot version compatibility check (`>=4.24,<5`, `>=4.17.0`, …) against the
  local `4.29.3`; mismatches require the same explicit override.
- Install copies into `AstrBot/data/plugins/` without overwriting, then calls
  the reload API. Dashboard modules can be installed from a local package with
  the same installer.

### UI

- Three new tabs: `智能体插件`, `控制台模块`, `插件市场`, keeping the existing
  theme, dynamic background and grey palette.
- Chinese/English strings for the new controls.

## Security notes

- The scanner is static and offline; it does not execute reviewed code.
- A static scan is not a sandbox. Obfuscation, reflection and runtime-downloaded
  code remain residual risks; the dialog says so.
- Deletion is reversible by design; nothing under `data/plugins` is hard-deleted.
- Dashboard modules run as local PowerShell with the user's privileges; only
  enable reviewed modules.
- The LLM-assisted audit is deferred: the DeepSeek key is machine-scoped DPAPI
  with an ACL limited to SYSTEM/Administrators/`AstrBot_User`, so the dashboard
  cannot read it without a privileged broker.

## Verification

```text
pytest: 39 passed
scanner: high-risk fixture -> unsafe (5 high, 1 medium, 1 low)
         clean fixture     -> safe
         missing dir       -> error
version: >=4.24,<5 / >=4.17.0 / * / 4.29.3 -> compatible
         >=5.0 / <4.0 -> incompatible
installer: copy ok, duplicate blocked, zip-slip blocked
module loader: 1 valid + 2 broken -> 1 loaded, 2 failed, dashboard alive
hub write path: enable/disable/restore/recycle-bin verified against AstrBot
                (AstrBot still HTTP 200 afterwards)
```
