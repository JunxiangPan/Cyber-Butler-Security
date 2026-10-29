# v1.2.3 — LibreHardwareMonitor watchdog

## Added

- `tools/lhm-watchdog.ps1`: checks `http://127.0.0.1:18085/data.json`.
  When the endpoint is down it stops an unresponsive process, restarts
  LibreHardwareMonitor (through its scheduled task, with a direct executable
  fallback), waits up to 30 seconds for recovery and records the result in
  `%ProgramData%\CyberButler\lhm-watchdog-state.json` and
  `lhm-watchdog.log`.
- `tools/lhm-watchdog.vbs`: hidden launcher (`wscript //B` +
  `powershell -WindowStyle Hidden`), so the task never opens a console window.
- `tools/install_lhm_watchdog.ps1`: registers the
  **LibreHardwareMonitor Watchdog** task as `SYSTEM` / highest privileges,
  running at startup and every 5 minutes. It also copies the files into the
  install root and performs a stop/restart recovery self-test.

## Why

The read-only temperature tool depends on LibreHardwareMonitor. Its task only
starts at logon and has no restart policy, so a crash, a manual close or a game
session could leave the sensor endpoint dead until the next reboot. The
watchdog restores it within five minutes without user interaction.

## Verification

```text
task: principal SYSTEM / Highest
triggers: AtStartup + every 5 minutes
self-test: before=true, stopped=true, watchdog_exit=0, recovered=true,
           process_running=true
last task result: 0
temperature endpoint after recovery: HTTP 200
pytest: 39 passed
privacy scan: OK
```

## Notes

- The task is intentionally invisible to the interactive user's Task Scheduler
  view (SYSTEM task ACL); verify it from an elevated shell or by watching the
  state file's `checked_at` timestamp.
- The watchdog never sends data anywhere; it only probes the local endpoint and
  restarts the local monitoring process.
