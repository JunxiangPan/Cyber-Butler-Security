# v1.3.0 — Commercial polish: i18n, error viewer, persona manager, service links

## Module 1 — Bilingual sweep

- All v1.3.0 surfaces are translated through `dashboard_i18n.json`: the new
  persona buttons, the System Log tab, service tooltips, DataGrid headers,
  plugin state/compatibility values, module statuses, market source labels and
  every new dialog/status line.
- `Apply-Language` now translates `DataGridColumn.Header` values (they are not
  part of the logical tree) and immediately re-renders the plugin list, module
  list, persona list and error counter, so switching to English updates
  dynamic status text without reopening the window.
- Plugin enable/disable/delete/reset and market install failures now use `T()`
  in both the dialog and the status line.

## Module 2 — Error viewer

- New **System Log** tab with a read-only stack-trace view, a live record
  counter, **Copy Error Log**, **Clear** and **Refresh**.
- `Write-UiError` records every caught exception to
  `%LOCALAPPDATA%\CyberButler\ui-errors.log` and the tab. `Show-Message`
  automatically files error-looking dialogs, module-load failures and module
  dispatcher exceptions are recorded explicitly, and the time-machine
  failure/timeout paths write their exit code and message.
- Copy uses `Set-Clipboard` with a WPF clipboard fallback (verified).

## Module 3 — Persona manager

- The Persona & Memory tab now lists every AstrBot persona, marks the active
  one and shows its prompt.
- **Switch Persona** updates `agent_runner.config.persona.persona_id` through
  `PUT /api/v1/system-config`; AstrBot reloads the pipeline scheduler after the
  save, so no manual restart is required.
- **New Blank Persona**, **Copy Persona** and **Delete Persona** use the local
  AstrBot API (`/api/persona/*`), so the dashboard never writes the ACL-guarded
  `AstrBot/data` directory as the interactive user. Delete blocks `default`,
  requires typing `DELETE PERSONA` and writes a JSON backup to
  `backups/personas/` before deleting.

## Module 4 — Service shortcuts

- Clicking **AstrBot** opens `http://127.0.0.1:6185`; clicking **SnowLuma**
  opens `http://127.0.0.1:5099` in the default browser.
- Clicking **Broker** shows the headless-service notice instead of opening a
  non-existent web UI.

## Verification

```text
pytest: 39 passed
persona API self-test: list 3 -> create -> copy -> delete (both backed up)
active persona read/switch: 苏瑾言, PUT system-config ok
error log: captured stack, copied to clipboard, cleared
English screenshots: Persona & Memory / System Log / Agent Plugins / Market
packaged tree: Hello World 1 -> 2 -> 3
privacy scan: OK
```

## Module 5 — Official dashboard plugins

- **sys_monitor** (`tools/dashboard_plugins/sys_monitor`): a dedicated Live
  Monitor tab. A 3-second DispatcherTimer reads
  `http://127.0.0.1:18085/data.json`, filters sensors by the `°C` unit (so clock
  and voltage values cannot masquerade as temperatures) and renders CPU, GPU
  and VRAM progress bars. Verified at 61.5 °C / 44.0 °C / 5,603 of 24,564 MB.
- **quick_cmd** (`tools/dashboard_plugins/quick_cmd`): a dedicated Quick
  Command tab with a text box, Send, and one-click Morning / Local Model /
  Check Temps buttons. Sends through the AstrBot Open API
  (`/api/v1/im/messages`) to the owner's QQ chat; no shell is executed.

## Module 6 — Trust boundary and privacy

- The Console Modules tab now shows a yellow warning whenever a module id is
  not one of the three official plugins:
  “⚠️ 注意：控制台插件运行在当前用户的最高权限下，请仅安装你信任的插件！”
  (English translation included.)
- **Copy Error Log** now runs `Protect-UiErrorText` before touching the
  clipboard: `sk-…` keys become `[REDACTED_API_KEY]`, `key=…`/`token=…` values
  become `[REDACTED]`, and Windows absolute paths become `[LOCAL_PATH]`.

## Time machine English confirmation

- The Restore / Reinstall / Downgrade confirmation titles and long warning
  bodies are translated through `T()`; in English mode the custom confirmation
  window, its OK button and all warning text are English. The Chinese and
  English long texts are also listed in `dashboard_i18n.json`.
