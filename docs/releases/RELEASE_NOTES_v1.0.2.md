# v1.0.2 — Manifest-Bound TOTP and Runtime Hardening

**Release date:** 2026-10-29  
**License:** AGPL-3.0  
**Scope:** emergency security release for the public-release branch

> [!WARNING]
> **This project still depends on unofficial QQ protocol clients such as SnowLuma.** Use a test account only. Account restriction, suspension, or permanent bans remain possible. The project is for personal study, research, and local security-technical exchange; commercial, illegal-profit, black-market, or malicious use is prohibited. See [SECURITY.md](SECURITY.md) and [README.md](README.md) for the full disclaimer.

## Why This Release Exists

A white-box review found four gaps that documentation alone could not close:

1. A TOTP approval was bound to one file path, not to the complete set of files being sent.
2. The ACL verifier did not explicitly deny write access for the AstrBot service account.
3. The live Broker process was still running an older 351-line build.
4. Code-execution tools remained available to the QQ private agent, allowing a plain-text/code path around TOTP.

V1.0.2 closes these gaps in code, tests, and runtime configuration.

## P0 Fixes

### 1. Complete manifest binding

AstrBot now builds a manifest for **every file** in the send operation:

```json
{
  "kind": "file",
  "path": "...",
  "size": 12345,
  "sha256": "..."
}
```

The manifest is sent with `POST /request` and is stored with the pending challenge.

- The Broker displays every path, size, and SHA-256 in the TOTP challenge.
- The Broker rehashes all files before the challenge and again at `/verify`.
- A changed size/hash returns `409`, clears the pending request, and writes an audit record.
- AstrBot rehashes the manifest immediately before `send_message`; any mismatch cancels the send.
- A `send` request without a manifest is rejected.

This prevents a “approve file A, replace it with file B” gap.

### 2. ACL verifier now includes the service account

`tools/verify_broker_acl.ps1` now takes a `-ServiceUser` parameter and adds that principal to the write-ACE denylist, in addition to:

- `Users`
- `Everyone`
- `Authenticated Users`
- the desktop user

If `tools/` or `AstrBot/.venv` grants write/modify/full-control to the service account, `tools/broker.py` refuses to start.

### 3. Live runtime synchronized

The deployment was updated in this order:

1. New `broker.py`, `message_tools.py`, Security Gate, and ACL scripts copied into the live tree while the old process was still running.
2. `tools/` and `AstrBot/.venv` ownership moved to `Administrators`; inherited broad write access removed.
3. `tools/verify_broker_acl.ps1` returned `Broker runtime ACL: OK`.
4. The old Broker process was stopped by the restart script and the latest Broker started.
5. AstrBot was restarted to load the manifest guard and tool denylist.
6. Health checks: AstrBot `200`, Broker `200`.

The live runtime is no longer the old 351-line Broker.

## P1 Fixes

### Code-execution tools removed from QQ private requests

The Security Gate now registers an `on_llm_request` hook that removes, for QQ private requests:

```text
astrbot_execute_python
astrbot_execute_ipython
astrbot_execute_shell
astrbot_shell_session
```

This closes the direct QQ-private tool path. It is not a complete plain-text mediation layer: a different agent path, a plugin that re-adds the tools, or a plain-text exfiltration route can still bypass TOTP.

### Case and hard-link bypasses

- Owner strings are casefolded on both sides.
- `st_nlink > 1` forces TOTP.
- Unknown `umo` platforms fail closed and are logged.

### ACL test honesty

`tests/test_acl_model.py` explicitly states:

> This is a logic model — not a real Windows kernel ACL test.

The real Windows ACL acceptance checklist remains in SECURITY.md.

## Tests

```text
11 passed in 0.38s
```

Included:

- ACL deny logic → `PermissionError`
- wrong TOTP → `403`
- five failures → `429`, pending cleared, 300-second lockout
- TOTP and recovery-code replay rejection
- prompt injection blocked
- owner exemption
- benign text allowed
- unknown platform fails closed
- QQ private tool denylist removes code-execution tools

## Runtime Requirements

- Windows 10/11
- AstrBot v4.29.x
- SnowLuma (unofficial; test account only)
- Python 3.10+
- Optional Ollama for local models

## Upgrade Notes

- Run `tools/harden_broker_runtime.ps1` from an elevated shell after copying the new files.
- Run `tools/verify_broker_acl.ps1`; it must print `Broker runtime ACL: OK`.
- Restart the Broker **after** the ACL check passes.
- Restart AstrBot to load the manifest guard and tool denylist.
- If you use the optional `/lockapi` state file under `tools/`, account for the fact that `tools/` is now read-only to the desktop user; move writable state or grant explicit file-level access.

## Known Limitations

- TOTP cannot verify the human identity behind a compromised phone/authenticator.
- Manifest rehashing reduces, but does not eliminate, a final TOCTOU window.
- Plain text is not fully mediated; removing code tools is not a complete sandbox.
- Media/voice/video and Shell execution lack equivalent TOTP.
- Unofficial QQ protocol account-ban risk remains.

## License

AGPL-3.0. See [LICENSE](LICENSE) and [SECURITY.md](SECURITY.md).

## Game-Mode Runtime Path Fix

With `tools/` now read-only to the desktop account, game-mode runtime state was moved out of `tools/`:

```text
Desktop\大肥鱼专用文件夹\game-mode.log
Desktop\大肥鱼专用文件夹\game-list.auto.txt
Desktop\大肥鱼专用文件夹\game-library.auto.txt
```

The old `tools/game-mode.log` is migrated on upgrade. The desktop account is granted read/execute on `tools/` and `AstrBot/.venv` (not write), so game-mode and weekly self-heal can still load their scripts.

## Game-Mode Exit Recovery

- The monitor writes a shared state file on `GAME MODE ON` and clears it on `GAME MODE OFF`.
- A `Game Mode Watchdog` task runs every minute. If the monitor process disappears, state is still active, and no game is running, it runs `-RestoreOnly`, reloads the model, and switches back to `local_qwen36`.
- Model unload now uses only the Ollama HTTP API; the synchronous `ollama stop` child was removed because the monitor was found terminated with `0xC000013A` after `GAME MODE ON`.

## Silent Watchdog (No Console Flash)

- The scheduled task now launches `wscript.exe` with `game-mode-watchdog.vbs` instead of calling `powershell.exe` directly.
- The VBS uses `WScript.Shell.Run(..., 0, True)`: window style 0, hidden, and waits for the PowerShell watchdog to finish so Task Scheduler does not kill the recovery child.
- The task is registered with `Hidden=True`.
- Verified: the scheduled task runs, recovery starts and finishes, state returns to `active=false`, and the model/provider are restored.
