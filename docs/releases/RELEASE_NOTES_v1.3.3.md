# v1.3.3 — Approval-channel switch and start-ollama log fix

## Added

- The Settings dialog now has a **Security** section with an
  **Approval channel** selector:
  - `QQ (quick mode, MITM risk)`
  - `Email (out-of-band, maximum safety)`
- The current `tools/broker_config.json` value is loaded and selected when the
  dialog opens.
- Saving writes `approval_channel` through the existing UAC action helper
  (`SetBrokerChannel`); the interactive user does not need write access to
  `tools/`.
- Before switching to `email`, the UI checks
  `C:\ProgramData\CyberButler\email_secret.json`. If it is missing, the save is
  blocked with “⚠️ Configure the mailbox first!”.
- After a channel change the UI asks whether to restart the Broker now
  (`Yes/No`), and a separate **Restart Broker** button is available in the
  same section.
- All new strings are in the eight-language `dashboard_i18n.json`
  (`zh/en/ja/ko/es/fr/de/ru`).

## Fixed

- `tools/start-ollama.ps1` no longer writes logs or Ollama stdout/stderr into
  the read-only `tools/` directory. Runtime logs go to
  `%LOCALAPPDATA%\CyberButler\logs` (ProgramData/TEMP fallback for SYSTEM).
  Log failures never abort the script.
- The Web UI Phase 1 source (`webui/`) is intentionally kept out of the
  v1.3.3 package; it will ship with v1.4.0.

## Verified

```text
pytest (release suite)     43 passed
webui auth tests           5 passed (separate webui/.venv)
Settings dialog XAML       SETTINGS_DIALOG_OK
Settings load/save smoke   DASHBOARD_SETTINGS_OK
Broker channel             email (local install)
Broker /health             200
```
