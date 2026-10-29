# v1.0.5 — Technical Debt Cleanup

## Cleanup

- Removed unused `time` import from `overlay/astrbot/core/tools/message_tools.py`.
- Removed the unreferenced `_totp_session_key()` helper.
- Removed the redundant local `import asyncio` in `plugins/astrbot_plugin_security_gate/main.py`.
- Kept all 17 tests; no test cases were removed.
- Preserved the 14 UTF-8 BOM PowerShell scripts.

## Broken deployment link fixed

`tools/install_startup_tasks.ps1` previously registered `SnowLuma Startup` with the missing `start-bot.bat`.

It now launches the existing:

```text
tools/start-snowluma.ps1
```

using `powershell.exe -File`.

## Documentation

`docs/使用说明.md` now describes the current scheduled-task architecture:

- `SnowLuma Startup` → `tools/start-snowluma.ps1`
- `Ollama Startup` → `tools/start-ollama.ps1`
- `Game Mode Startup` → `tools/game-mode.ps1`
- `AstrBot Service` → AstrBot service task

All `start-bot.bat` / `stop-bot.bat` references were removed.

The multilingual Agent-Ready Deployment sections from v1.0.4 are included.

## Verification

```text
17 passed
AstrBot 6185 = 200
Broker 18090 = 200
```
