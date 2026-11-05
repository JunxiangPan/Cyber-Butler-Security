# Cyber-Butler v1.6.2 QA Follow-ups

## Contents

- [P0 — release/security blockers](#p0-releasesecurity-blockers)
- [P1 — installer/UX and security integration](#p1-installerux-and-security-integration)
- [P2 — coverage/documentation](#p2-coveragedocumentation)
- [Fixed already (for reference)](#fixed-already-for-reference)
- [Release rule after this batch](#release-rule-after-this-batch)

> Status: encountered issues to fix as one batch before the next package/sign.
> The signed v1.6.2 assets have NOT been uploaded. Any source change requires
> rebuild + re-sign, and invalidates the current signature.

## P0 — release/security blockers

### 1. Native WFP filter is not implemented

- Current: Windows Firewall per-user rules (`New-NetFirewallRule`) plus a
  firewall-log Tripwire.
- Missing: `FwpmEngineOpen0` / `FwpmFilterAdd0` / filter removal and a real
  audit-only event source.
- File: `tools/wfp_guard.py`, `tools/wfp_policy.py`,
  `installer/lib/Installer.Services.ps1`.
- Required: implement native filter or explicitly rename/downgrade the claim in
  every doc and UI surface; run audit-only on a real machine before enforce.

### 2. Audit chain is not a full replacement

- Current: legacy `AUDIT` JSONL plus a background mirror into
  `AUDIT.chain.jsonl`.
- Remaining: `tools/broker.py` still has multiple direct `AUDIT.open("a")` calls
  (approval, scoped, bypass, execute, etc.).
- Required: route every event through `audit_chain.append_event()`, keep the
  process lock, and prove success/failure/denial coverage.

### 3. Real-machine and Light acceptance

- v1.6.1 High was accepted on a real machine/VM; Medium/Light were not complete.
- v1.6.2 has no clean-VM full install + uninstall acceptance.
- Required: clean VM and physical-machine runs; Light is a mandatory gate from
  v1.6.3 onward; record results in `docs/TEST_MATRIX.md`.

### 3a. Upgrade can fail on locked `node.exe`

- Observed on host upgrade 2026-11-03:
  `Copy-Item` overwrote/backed up `AuxRuntime
ode.exe` while the running
  AuxRuntime node process held it:
  `The process cannot access the file because it is being used by another process`.
- Rollback then also failed (`rollback_failed`) because the same file was still
  locked.
- Root cause: Core deployment runs before the installer stops existing
  AgentRuntime/AuxRuntime/WebUI/Broker processes.
- Source fix added: before Core on an existing install, stop named tasks and
  processes owning ports `6185/18090/8765/8766/6199/5099/3000/3001`, wait 3s.
- This fix is in the worktree but NOT in the signed v1.6.2 package; current host
  retry must stop processes manually or use a rebuilt package.

### 3c. AgentRuntime import fails with Deprecated 3.0.0 on Python 3.10

- Observed after Core pip install:
  `SyntaxError: invalid syntax` at
  `deprecated/classic.py: type WarningAction = Literal[...]`.
- `type` statement syntax requires Python 3.12/3.13; the host uses bundled
  `.python` 3.10.8 and `.venv` Python 3.10.
- AgentRuntime requirements only say `deprecated>=1.2.18`; pip installed
  `Deprecated 3.0.0`, which is incompatible with 3.10.
- Impact: Core `import agentruntime.core` fails, rollback runs, and the installer
  reports a truncated `Traceback (most recent call last):`.
- Required: pin `deprecated<3` in installer/AgentRuntime requirements or force
  Python 3.13; add an import-smoke regression test.
- Source fix added: installer appends `deprecated<3` to the extracted AgentRuntime
  requirements before pip; this is NOT in the signed v1.6.2 package.

### 3c-2. greenlet native extension missing on Python 3.10

- After pinning Deprecated, import failed with
  `ModuleNotFoundError: No module named 'greenlet._greenlet'`.
- The venv contains `greenlet 3.5.6` source files but no compiled `_greenlet`
  extension; the host has Python 3.10 and no usable build toolchain.
- AgentRuntime requirements only say `sqlalchemy[asyncio]>=2.0.41`; pip selected a
  greenlet build that did not provide the binary wheel.
- Required: install a wheel-backed greenlet compatible with 3.10 (e.g. `greenlet<3.2`
  with `--only-binary=:all:`) or use Python 3.13; pin this in the installer and
  add an import-smoke regression test.

### 3e. Installer log path text is still mojibake in GUI

- Observed during the High install while waiting for approval:
  `d:\qq锟斤拷锟斤拷源...AgentRuntime\.venv...`.
- The log is written as UTF-8 (pip/Python output), but several GUI reads use
  `Get-Content` without `-Encoding UTF8`, so paths are decoded as ANSI/GBK.
- Affected: status `last 12 log lines`, progress tail, and possibly log viewer.
- Required: pass `-Encoding UTF8` to every `Get-Content` that reads
  `installer.out.log` / `installer.err.log`, and set `PYTHONIOENCODING=utf-8`
  for the child process.
- Note: this affects display only; it does not change the install result.

### 3d. GUI status can show stale failed report and false TOTP state

- Observed after a new run: GUI showed `报告状态: failed` from the previous
  report and `TOTP material ready`, while the current run was still copying or
  had already failed.
- The signal directory contained no `totp-ready.json`; TOTP was not actually
  ready.
- Root cause: status/completion timers parse the shared report path without
  checking its run id/timestamp, and TOTP status is inferred from progress
  percentage instead of signal files.
- Required: clear/rotate the report at run start; compare generated_at/run_id
  with the current GUI run; derive TOTP state only from `totp-ready.json`; stop
  the timer and disable TOTP controls on a failed report.
- Source fix added: rotate the previous report at startup. Remaining UI work:
  stop TOTP/status timers on a current-run failure and ignore stale report IDs.

### 3b. Localized PowerShell errors were mojibake in report/manual recovery

- Observed report/manual-recovery text:
  `ʹ�á�3�����������á�Copy��...`
- The underlying error was the locked `node.exe`; the text was a localized
  .NET exception decoded/rendered incorrectly.
- Source fix added: set PowerShell console/output encoding to UTF-8 no BOM;
  Core catches locked-file errors and emits a stable English message plus the
  exact path, instead of the mojibake exception.
- Needs report/manual-recovery validation on an actual failed run.

### 0. GUI has no explicit Upgrade / Repair / Keep Data choice

- Observed on the host upgrade: the GUI never showed
  “升级 / 修复 / 保留数据”; it auto-detected `existing=Legacy` and proceeded.
- This is unsafe UX: a user cannot explicitly choose preservation versus a fresh
  install, and cannot confirm the existing version/path before Core runs.
- Required GUI behavior:
  - detect existing install and show the detected version/path;
  - default to **Upgrade / Repair (preserve data)**;
  - require an explicit destructive confirmation for a fresh install;
  - show what will be preserved (`AgentRuntime\data`, `AuxRuntime\config/data/logs`,
    `webui\data`, TOTP vault, broker config);
  - offer Cancel;
  - pass the selected mode to the child (`Upgrade`/`Repair`/`Fresh`) rather than
    relying only on auto-detection.

## P1 — installer/UX and security integration

### 4. Defender exclusion is hardcoded to C:\CyberButler

- Encountered on the host install:
  `D:\qqlocal agentshared`.
- Files: `installer/lib/Add-DefenderExclusion.ps1`,
  `installer/CyberButler.Installer.GUI.ps1`.
- Current behavior: any non-default path + checked exclusion fails with:
  `Refusing to add a Defender exclusion outside C:\CyberButler`.
- It is optional and does not block install when unchecked, but the UI is
  misleading.
- Required: dynamic label with the selected path; either allow only the exact
  install root with safety checks (no drive root, no Windows/Program Files/Users)
  or show a manual command and continue; never silently exclude a parent folder.

### 5. Credential Proxy is not installer-integrated

- File: `tools/credential_proxy.py`,
  `tools/credential_proxy.example.json`.
- Current: loopback reverse proxy; fake bearer token -> real key from
  `CBS_CREDENTIAL_PROXY_REAL_KEY`; only `/v1/` on one upstream.
- Missing: installer task/service and ACL, AgentRuntime provider base-URL setup,
  streaming/SSE pass-through, key ingestion from the existing DPAPI secret.
- Required: decide whether the proxy is a supported service; if yes, install and
  ACL it separately from the agent; if not, keep it clearly experimental.

### 6. External-read / indirect-injection warning is manual

- Files: `tools/injection_audit.py`, `tools/broker.py`.
- Current: agent/plugin must POST `/external-read`; the preview warning appears
  only when a recent event exists.
- Missing: automatic hook from web/file tools, cross-process lock, UI/report
  surface.
- Required: document the limitation and add the hook where supported; never
  claim this detects or blocks prompt injection.

### 7. High test-file ACL needs real validation

- Files: `installer/lib/Installer.Acl.ps1`,
  `installer/Install-CyberButler.ps1`.
- Current: High applies `icacls /deny <service-account>:(W,D)` to
  `pytest.ini`, `tests/conftest.py`, `tools/Test-WfpTripwire.ps1`,
  `installer/tests`.
- Missing: real-machine ACL verification, rollback/journal coverage, and a test
  that proves the agent account cannot write/delete while it can still read.

### 8. Uninstall anti-rebound needs a real running-agent test

- Current: stop tasks -> remove WFP rules -> kill processes -> delete; writes
  `CBS_IS_UNINSTALLING=1` and `uninstalling.marker`; Broker returns 503.
- Missing: test with an actively retrying Agent, verify no hang/popup, and verify
  the plugin/marker path behavior end to end.

### 9. Job Object limits need Windows integration evidence

- Current: unit tests for constants/flags and generous defaults.
- Missing: observe actual process/job memory, CPU, active-process limits and
  confirm no `BREAKAWAY_OK`; ensure normal model inference is not OOM-killed.

## P2 — coverage/documentation

### 10. SBOM does not cover downloaded AgentRuntime/AuxRuntime requirements

- Current: `dependencies.sbom.json` covers repo `requirements-dev.txt` and
  `webui/requirements.txt`.
- Missing: hashes for requirements inside downloaded archives or an upstream
  SBOM; installer currently verifies the local bundle only.

### 11. Tripwire test script has a synthetic fallback

- File: `tools/Test-WfpTripwire.ps1`.
- If the Windows Firewall log is absent, it writes a synthetic record. That can
  prove parsing, not real firewall capture. Need a real-log run and a clear
  distinction in the report.

### 12. UI best-effort catches remain

- File: `installer/lib/Installer.GuiRun.ps1` and GUI log helpers.
- Some `catch { }` remain around clipboard, status refresh, credential display,
  and cleanup retries. They are mostly non-security UI paths, but the uninstall
  retry and version-read paths must never silently claim success.

## Fixed already (for reference)

- `broker_config.json` first-run creation from a missing file; preserve existing
  keys; add `admin_email`/`approval_channel` without overwriting.
- Defender exclusion failure no longer blocks install when unchecked.
- WebUI WFP Guard health is server-side checked (45s heartbeat).
- `network-policy.json` atomic write + CSRF.
- Quarantine ACL (SYSTEM/Administrators) and snapshot close on failure.
- Audit process lock and WFP status atomic write.
- Magic-byte approval warning (Shebang/PE/ELF).
- Intent mismatch warning and critical-integrity hard deny.
- High test-file ACL protection code added.

## Release rule after this batch

1. Fix the reviewed items.
2. Run full pytest + full Pester + privacy scan.
3. Build the package.
4. Sign `update-manifest.json`.
5. Verify `VALID` and zip/manifest `MATCH`.
6. Do not modify any file after signing; if changed, rebuild and re-sign.
