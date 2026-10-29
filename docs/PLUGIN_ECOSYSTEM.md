# Plugin ecosystem (v1.2.0)

Three surfaces, one trust boundary: the dashboard can list and toggle AstrBot
plugins, load local console modules, and install marketplace plugins **only
after** a static security review and a compatibility check.

```text
tools/
├── plugin_hub.ps1              AstrBot plugin list / enable / disable / recycle bin
├── plugin_market.ps1           official + GitHub search, download, extract, install
├── plugin_security_scanner.ps1 static .py review + version compatibility
├── dashboard_modules.ps1       console module loader and isolation
├── plugin_review_dialog.ps1    red-flag review dialog before install
└── dashboard_plugins/
    └── hello_world/            reference module (manifest.json + ui.xaml + logic.ps1)
```

## Module 1 — AstrBot plugin hub

### Read path

1. `GET http://127.0.0.1:6185/api/plugin/get` with the dashboard token from
   `.astrbot_token`. This is the authoritative list and includes `activated`,
   `reserved`, `root_dir_name`, `astrbot_version` and `installed_at`.
2. If AstrBot is offline, the list falls back to parsing
   `AstrBot/data/plugins/*/metadata.yaml`; the UI marks the state as unknown.

The dashboard token is a JWT issued for the local dashboard user. Responses are
decoded as UTF-8 explicitly because PowerShell 5.1 mis-reads UTF-8 JSON when the
server omits a charset parameter (this corrupted Chinese display names).

### Write path

| Action | Implementation |
| --- | --- |
| Enable | `POST /api/plugin/on` `{"name": "<plugin>"}` |
| Disable | `POST /api/plugin/off` `{"name": "<plugin>"}` |
| Reload all | `POST /api/plugin/reload` `{}` |
| Delete | disable → move directory → `reload` |
| Restore defaults | backup + delete `<root_dir>_config.json` → enable/reload |

AstrBot persists the disabled set in `data/shared_preferences.json`
(`inactivated_plugins`) and terminates the plugin instance, so no full restart
is required.

Deletion is intentionally **softer than AstrBot's uninstall**:

```text
AstrBot/data/plugins/<dir>
        ↓
backups/deleted_plugins/<dir>-<yyyyMMdd-HHmmss>
```

A `deleted.log` records the move. Restoring is a directory move back plus a
reload. Reserved plugins (`reserved: true`, for example AstrBot built-ins) are
refused.

`恢复默认配置` means: copy the plugin config to
`backups/plugin-config-defaults/`, delete it so AstrBot regenerates schema
defaults on reload, then enable the plugin. It never touches plugin data.

## Module 2 — Dashboard modules

### Directory contract

```text
tools/dashboard_plugins/<id>/
├── manifest.json    required
├── ui.xaml          required, root element is inserted into a TabItem
└── logic.ps1        optional, runs in its own scope
```

```json
{
  "id": "hello_world",
  "name": "Hello World",
  "version": "1.0.0",
  "author": "Cyber-Butler",
  "description": "reference module",
  "ui": "ui.xaml",
  "logic": "logic.ps1",
  "requires_dashboard": ">=1.2.0",
  "default_enabled": true
}
```

`id` must match `^[A-Za-z0-9_\-]{2,64}$`. Missing files or invalid JSON are
reported as a module problem and the module is not loaded.

### Loader

- Every enabled module becomes a `TabItem` in the main `TabControl`; its
  `ui.xaml` is parsed with `XamlReader` and its `logic.ps1` is dot-sourced in an
  isolated script scope with a `$moduleContext` hashtable:

| Key | Meaning |
| --- | --- |
| `Id`, `Name`, `Version`, `Author` | manifest identity |
| `Module` | full manifest record (paths included) |
| `Root` | root element of `ui.xaml`; use `$moduleContext.Root.FindName(...)` |
| `Tab` | the created `TabItem` |
| `Host` | the main window |
| `ToolsRoot`, `ProjectRoot` | resolved paths |
| `State` | per-load hashtable for counters and caches |
| `Log` | `& $moduleContext.Log 'message'` → `%LOCALAPPDATA%\CyberButler\dashboard-modules.log` |
| `T` | `& $moduleContext.T '中文' 'English'` |

- If the script defines `Initialize-DashboardModule($context)`, it is called
  after the XAML is parsed.
- Enabled/disabled state lives in
  `%LOCALAPPDATA%\CyberButler\dashboard-modules.json` (`disabled: [ids]`).
  Disabled modules load neither XAML nor script.
- `重新加载` unloads every module tab and runs the loader again, so module edits
  do not require restarting the dashboard.

### Failure isolation

1. Manifest/XAML parse errors → the tab is never added; the module manager
   lists the exact error.
2. A `logic.ps1` exception → the tab is removed and the error is recorded.
3. An unhandled exception **inside a module event handler** is caught by
   `Dispatcher.UnhandledException`; the host logs it, shows
   `控制台模块运行出错，已被拦截，主控台继续运行`, sets `Handled = $true` and keeps
   running.
4. Startup reports failed modules once and skips them.

The reference module `hello_world` exercises all of this and is a template for
third-party modules.

**Trust warning:** console modules are local PowerShell with the dashboard
user's privileges. Only enable modules you have reviewed. The marketplace in
v1.2.0 installs AstrBot plugins only; dashboard modules are installed manually
into `tools/dashboard_plugins/`.

## Module 3 — Market and security review

### Sources

| Source | Endpoint | Notes |
| --- | --- | --- |
| AstrBot official | `https://api.soulter.top/astrbot/plugins` | 2 MB registry, cached 1 hour in `%LOCALAPPDATA%\CyberButler\market-cache.json` |
| Fallback | `AstrBotDevs/AstrBot_Plugins_Collection` `plugin_cache_original.json` | used when the S3 API fails |
| GitHub | `GET /search/repositories?q=<terms> astrbot_plugin in:name,description` | unauthenticated rate limit applies |

Each result carries `name`, `display_name`, `version`, `author`, `desc`,
`repo`, `download_url`, `astrbot_version`, `stars`, `download_count`.
GitHub downloads use `https://codeload.github.com/<repo>/zip/refs/heads/<branch>`.

### Download and extraction guards

- HTTPS only.
- Archive ≤ 64 MB, expanded ≤ 256 MB, ≤ 5000 entries.
- Every entry is resolved with `GetFullPath` and must stay inside the temp
  directory, which blocks `../` zip-slip entries.
- Extraction happens in `%TEMP%\cb-plugin-<guid>`, removed in `finally`.

### Static scanner

`Invoke-PluginSecurityScan` walks `.py` files (skips `__pycache__`, `.git`,
`.venv`, `node_modules`; ≤ 800 files, ≤ 2 MB each) and reports
`file:line + rule + severity`.

| Severity | Examples |
| --- | --- |
| high | `eval`, `exec`, `os.system`, `os.popen`, `subprocess(..., shell=True)`, `ctypes`, base64→exec in one file |
| medium | `winreg`, `shutil.rmtree`, `os.remove/unlink/rename`, absolute system paths, `pickle.loads`, `yaml.load`, `subprocess`, `__import__` |
| low | base64 decode, outbound `requests.post/put`, raw sockets |

The review dialog shows a **red banner** when there is any high finding or a
version mismatch, lists every finding, and requires the user to type
`INSTALL ANYWAY`. Otherwise `确认安装` installs directly.

A static scanner is not a sandbox: it cannot see obfuscation, reflection, or
code downloaded at runtime. This is stated in the dialog and remains a residual
risk.

### Version compatibility

`metadata.yaml` → `astrbot_version` (for example `>=4.24,<5`). The local version
comes from `AstrBot/astrbot/__init__.py`. Supported operators: `>= > <= < == !=`
and comma-separated clauses. A mismatch is shown as `版本不兼容` and requires the
same explicit override. Missing `astrbot_version` is treated as compatible but
noted.

### Install

After approval:

```text
temp package → AstrBot/data/plugins/<metadata.name>   (agent plugins)
             → tools/dashboard_plugins/<manifest.id> (dashboard modules)
```

Existing targets are never overwritten. A failed install removes nothing from
disk. After a copy, the dashboard calls `POST /api/plugin/reload` (`{}`) to load
the new plugin without restarting AstrBot; a reload failure is reported without
rolling back the files.

### LLM audit — deliberately deferred

The configured DeepSeek key is a **machine-scoped DPAPI blob whose ACL grants
only SYSTEM, Administrators and `AstrBot_User`**. The dashboard runs as the
interactive user and cannot decrypt it without a privileged broker, and sending
third-party source code to an external model has privacy implications that
deserve an explicit opt-in design. v1.2.0 therefore ships the deterministic
static scanner as the only gate; an LLM-assisted audit is planned for a later
version with a key broker and a per-install consent prompt.

## Tests

```text
pytest: 39 passed (30 existing + 9 scanner/version tests)
scanner fixtures: tests/fixtures/plugins/high_risk, tests/fixtures/plugins/clean
dashboard module smoke: -SmokeModules
UI smoke screenshots: -SmokeUi
```
