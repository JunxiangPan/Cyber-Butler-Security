# Plugin ecosystem (v1.2.0)

## Contents

- [Module 1 — AgentRuntime plugin hub](#module-1-agentruntime-plugin-hub)
- [Module 2 — Dashboard modules](#module-2-dashboard-modules)
- [Module 3 — Market and security review](#module-3-market-and-security-review)
- [Tests](#tests)
- [Module 4 — DSH / Cordis bridge (v1.6.1)](#module-4-dsh-cordis-bridge-v161)

> **v1.6.1 status**: completed, incomplete, and non-guaranteed work is in archived v1.6.1 status (removed). This document is about the plugin ecosystem, not a security guarantee.


Three surfaces, one trust boundary: the dashboard can list and toggle AgentRuntime
plugins, load local console modules, and install marketplace plugins **only
after** a static security review and a compatibility check.

```text
tools/
├── plugin_hub.ps1              AgentRuntime plugin list / enable / disable / recycle bin
├── plugin_market.ps1           official + GitHub search, download, extract, install
├── plugin_security_scanner.ps1 static .py review + version compatibility
├── dashboard_modules.ps1       console module loader and isolation
├── plugin_review_dialog.ps1    red-flag review dialog before install
└── dashboard_plugins/
    └── hello_world/            reference module (manifest.json + ui.xaml + logic.ps1)
```

## Module 1 — AgentRuntime plugin hub

### Read path

1. `GET http://127.0.0.1:6185/api/plugin/get` with the dashboard token from
   `.agentruntime_token`. This is the authoritative list and includes `activated`,
   `reserved`, `root_dir_name`, `agentruntime_version` and `installed_at`.
2. If AgentRuntime is offline, the list falls back to parsing
   `AgentRuntime/data/plugins/*/metadata.yaml`; the UI marks the state as unknown.

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

AgentRuntime persists the disabled set in `data/shared_preferences.json`
(`inactivated_plugins`) and terminates the plugin instance, so no full restart
is required.

Deletion is intentionally **softer than AgentRuntime's uninstall**:

```text
AgentRuntime/data/plugins/<dir>
        ↓
backups/deleted_plugins/<dir>-<yyyyMMdd-HHmmss>
```

A `deleted.log` records the move. Restoring is a directory move back plus a
reload. Reserved plugins (`reserved: true`, for example AgentRuntime built-ins) are
refused.

`恢复默认配置` means: copy the plugin config to
`backups/plugin-config-defaults/`, delete it so AgentRuntime regenerates schema
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
- **Event handlers must capture the context themselves.** PowerShell does not
  keep the loader's local variables after the module finishes loading; a plain
  `Add_Click({ $moduleContext... })` gets `$null`. End the handler with
  `.GetNewClosure()`:

  ```powershell
  $button.Add_Click({
      $moduleContext.State.Clicks = 1 + [int]$moduleContext.State.Clicks
      $counter.Text = '点击次数：' + $moduleContext.State.Clicks
  }.GetNewClosure())
  ```

  The closure copies the variables it references, so `$moduleContext`, the
  counter `TextBlock` and any other captured object stay valid. It also means
  the handler cannot call module-level functions (closures get a fresh module
  scope); call scriptblocks stored on `$moduleContext` such as `.Log` instead.
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
v1.2.0 installs AgentRuntime plugins only; dashboard modules are installed manually
into `tools/dashboard_plugins/`.

## Module 3 — Market and security review

### Sources

| Source | Endpoint | Notes |
| --- | --- | --- |
| AgentRuntime official | `https://api.soulter.top/agentruntime/plugins` | 2 MB registry, cached 1 hour in `%LOCALAPPDATA%\CyberButler\market-cache.json` |
| Fallback | `AgentRuntimeDevs/AgentRuntime_Plugins_Collection` `plugin_cache_original.json` | used when the S3 API fails |
| GitHub | `GET /search/repositories?q=<terms> agentruntime_plugin in:name,description` | unauthenticated rate limit applies |

Each result carries `name`, `display_name`, `version`, `author`, `desc`,
`repo`, `download_url`, `agentruntime_version`, `stars`, `download_count`.
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

`metadata.yaml` → `agentruntime_version` (for example `>=4.24,<5`). The local version
comes from `AgentRuntime/agentruntime/__init__.py`. Supported operators: `>= > <= < == !=`
and comma-separated clauses. A mismatch is shown as `版本不兼容` and requires the
same explicit override. Missing `agentruntime_version` is treated as compatible but
noted.

### Install

After approval:

```text
temp package → AgentRuntime/data/plugins/<metadata.name>   (agent plugins)
             → tools/dashboard_plugins/<manifest.id> (dashboard modules)
```

Existing targets are never overwritten. A failed install removes nothing from
disk. After a copy, the dashboard calls `POST /api/plugin/reload` (`{}`) to load
the new plugin without restarting AgentRuntime; a reload failure is reported without
rolling back the files.

### LLM audit — deliberately deferred

The configured DeepSeek key is a **machine-scoped DPAPI blob whose ACL grants
only SYSTEM, Administrators and `AgentRuntime_User`**. The dashboard runs as the
interactive user and cannot decrypt it without a privileged broker, and sending
third-party source code to an external model has privacy implications that
deserve an explicit opt-in design. v1.2.0 therefore ships the deterministic
static scanner as the only gate; an LLM-assisted audit is planned for a later
version with a key broker and a per-install consent prompt.

## Tests

```text
Project test suite: 72 passed (including broker policy, scoped-token,
approval-only, UIPI, scanner/version, and security-gate tests).
scanner fixtures: tests/fixtures/plugins/high_risk, tests/fixtures/plugins/clean
dashboard module smoke: -SmokeModules
UI smoke screenshots: -SmokeUi
```


## Module 4 — DSH / Cordis bridge (v1.6.1)

`dsh-cbs-gate` is a separate TypeScript/Cordis bundle, not an AgentRuntime plugin and
not bundled into the CBS installer. It is the bridge for DSH-style agents.

### Contract

- Registers a `tools/pre-execute` waterfall listener.
- Read-only tools pass through unchanged.
- `write` maps to Broker `write_file`; `delete_file` maps to `delete`.
- `edit`, `execute_shell`, `ops_bash`, and `pwsh` are refused because the Broker
  does not yet have a safe edit/shell contract.
- Calls `POST /api/request_approval` with `approval_only: true` and
  `X-Broker-Token`.
- Handles `allowed`, `requires_totp`, and `denied`.
- On `requires_totp`, polls `GET /api/request_approval/status?id=...` about once
  per second and allows the original DSH tool only after `approved`.
- Clears a cached scoped token on `scoped_invalid`; fails closed if the Broker is
  unreachable, the status is unknown, or the poll times out.

### Why approval-only

The Broker must not execute a file action that DSH will also execute. In
approval-only mode the Broker changes only its approval state; DSH runs the
original tool after it observes `approved`. This prevents double writes and
double deletes.

### Scoped token handoff

`/api/request_approval/status` returns the scoped token only when the state is
`approved` and only to a broker-token-authenticated caller. The DSH executor
caches it in memory and sends it as `scoped_token` on the next request. The
token remains constrained by the Broker's directory/action/TTL rules; the plugin
cannot widen that scope.

### Operational status

- Separate package: `dsh-cbs-gate`.
- Requires the DSH profile to have read access to the Broker token file.
- `ops_bash` / `pwsh` are intentionally blocked while the gate is enabled;
  manage services from an external shell.
- It is not code-signed in this build and is not covered by a third-party audit.
- Full status: archived v1.6.1 status (removed).
