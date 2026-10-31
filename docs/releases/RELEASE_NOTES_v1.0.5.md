# v1.0.5 — Technical Debt Cleanup

## Cleanup

- Removed unused `time` import from `overlay/astrbot/core/tools/message_tools.py`.
- Removed the unreferenced `_totp_session_key()` helper.
- Removed the redundant local `import asyncio` in `plugins/astrbot_plugin_security_gate/main.py`.
- Kept all 17 tests; no test cases were removed.
- Preserved the 14 UTF-8 BOM PowerShell scripts.

## Broken deployment link fixed

`tools/install_startup_tasks.ps1` previously registered `SnowLuma Startup` with a missing legacy batch launcher.

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

All legacy batch-launcher references were removed from operational files.

The multilingual Agent-Ready Deployment sections from v1.0.4 are included.

## Verification

```text
17 passed
AstrBot 6185 = 200
Broker 18090 = 200
```

## Final QA hotfix

- Added UTF-8 BOM to `tools/boot-selfcheck.ps1`; Windows PowerShell 5.1 now parses it correctly.
- Removed all legacy batch-launcher references from release notes and documentation.
- Removed remaining unused imports and an unused exception variable.
- Added `tools/start-game-mode.ps1`: the scheduled task launches the long-running monitor as a detached child and exits 0.
- Re-registered `Game Mode Startup` against the launcher; live `LastTaskResult=0`.
- Revalidated all 20 PowerShell scripts with Windows PowerShell 5.1: 20/20 pass.
- Revalidated 17 tests: 17 passed.
