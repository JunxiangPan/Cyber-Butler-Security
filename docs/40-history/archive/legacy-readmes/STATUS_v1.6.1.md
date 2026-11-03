[ARCHIVED - 已废弃] This document is retained for history only; see the current docs index.

﻿# CBS v1.6.1 — Status, Incomplete Work, and Non-Guarantees

## 故障排查

安装/重启后的常见故障与手工修复步骤见 [TROUBLESHOOTING.md](TROUBLESHOOTING.md)。

测试覆盖与安全承诺对照见 [TEST_MATRIX.md](TEST_MATRIX.md)。


> This document is the single source of truth for what v1.6.1 actually ships,
> what is still incomplete, and what CBS does **not** guarantee.
> If another document disagrees, this page wins for v1.6.1.

## 测试覆盖 / Test Coverage

✅ **High**：已完成完整实机端到端测试（安装、服务拉起、TOTP、SCOPED、卸载）。

⚠️ **Medium**：已完成多次局部测试，大概率可用，未做全流程实机验收。

❌ **Light**：尚无完整实机测试，请自行评估风险。

✅ High: full real-machine end-to-end acceptance (install, service startup, TOTP, SCOPED, uninstall).

⚠️ Medium: multiple partial tests; likely usable, but no full real-machine acceptance.

❌ Light: no complete real-machine test yet; assess the risk yourself.

## 1. Completed in v1.6.1

### Installer and launch path

- One WPF installer for High, Medium, and Light tiers.
- Native `START-INSTALLER.exe` launcher; no `.vbs`, `wscript.exe`, or `.cmd`
  launch chain.
- Installer validates the dashboard PowerShell syntax before finishing.
- Dashboard and official dashboard-module files are excluded from `YOUR_*`
  placeholder rewriting, preserving official module hashes.
- Installer report, rollback journal, service assertions, and sanitized
  diagnostics are written outside the install root where appropriate.

### OS and process boundary

- High tier creates and uses the low-privilege AstrBot service identity.
- ACL split for `AstrBot\data`: cache/tmp/temp/logs/plugin_data writable by the
  runtime; memory/config/knowledge_base/site-packages/plugins and
  `cmd_config.json` explicitly reduced where required.
- Broad `Authenticated Users` write access is removed.
- Broker runs as `SYSTEM`; runtime source `tools/` and `AstrBot/.venv` are
  protected by a fail-closed ACL check.
- Broker creates a Windows Job Object with
  `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` and joins it before spawning children.
  Broker children and grandchildren are killed when the last job handle closes.
  Verified on Windows with a child `sleep(60)` test.

### Approval and file policy

- Loopback-only Broker with `X-Broker-Token`.
- One-pending-request model, TOTP/recovery approval, replay cache, failed-attempt
  backoff, and a five-minute challenge timeout.
- `/request` and `/verify`; `write_file`, `send`, `send_file`, delete, overwrite.
- `approval_only: true`: TOTP changes state only; the Broker does not execute the
  file action. DSH executes the original tool.
- `/api/request_approval` returns `allowed`, `requires_totp` + `challenge_id`, or
  `denied`.
- `/api/request_approval/status` returns `pending`, `approved`, `denied`, or
  `expired`; on `approved` it can return the scoped token to an authenticated
  broker-token holder.
- 30-second action-scoped bypass for repeat prompts in the same action/directory.
- 30-minute Scoped Token bound to the canonical target directory; limited to
  `delete`, `overwrite`, `write_file`; shared scratch and tmp trees only.
- Scoped token is memory-only, expires automatically, and is never valid for
  memory/config, the TOTP vault, `send`, or a sibling directory.
- Scoped approval writes:
  `Scoped via 30-minute Directory Token` and `auto_executed: false`.
- Shared new-file creation is auto-allowed; overwriting/deleting existing files
  requires approval; memory/config requires TOTP; vault is denied.
- Scoped token invalid/expired requests return `scoped_invalid: true`.

### DSH / Cordis bridge

- Separate `dsh-cbs-gate` TypeScript bundle; not automatically installed by the
  CBS installer.
- Intercepts `tools/pre-execute`; read tools pass through.
- `write` maps to `write_file`; `delete_file` maps to `delete`.
- `edit`, `execute_shell`, `ops_bash`, and `pwsh` are refused because no safe
  mapping exists yet.
- Approval-only flow, status polling, broker-token header, fail-closed behavior.
- Caches the scoped token in the executor instance and sends it on the next
  approval request; clears the cache on `scoped_invalid`.

### Audit and observability

- Audit JSONL for TOTP, failures, bypass, scoped use, and approval-only outcomes.
- Scoped tokens are never written to audit logs.
- UIPI defensive hook: `UIPI_BLOCKED_GUI_INTERACTION`.
- Dashboard service/GPU/provider status and installer diagnostics.

## 2. Incomplete / still being worked on

- **AstrBot's own children are outside the Broker Job.** AstrBot is a separate
  scheduled task. A launcher-level Job Object or explicit process adoption is
  still needed for full AstrBot subtree coverage.
- **No AppContainer, restricted-token, or syscall sandbox.** Job Object is
  process-tree containment and ACL is filesystem/OS authorization; neither is a
  general runtime sandbox.
- **DSH shell/edit mediation.** Shell and edit are blocked, not approved. The
  Broker has no safe shell/edit contract yet.
- **Scoped token scope is deliberately narrow.** It works only in shared scratch
  and tmp trees; memory/config and the vault cannot use it. It also covers a
  directory for 30 minutes, so it is not per-file.
- **UIPI is a logging hook, not a detector.** There is no GUI bridge in the
  current Broker/AstrBot overlay, so no real UIPI event is produced today.
- **Interactive desktop dependency.** AstrBot and Web UI are scheduled tasks tied
  to the desktop session; logging off can stop them. Unattended use still needs
  auto-logon or a true service model.
- **Media/egress coverage.** Images, voice, and video do not have equivalent TOTP
  mediation.
- **No physical confirmation dialog.**
- **No third-party audit or formal verification.**
- **Release signing status:** see the release notes and `update-manifest.sig`;
  SmartScreen/Defender reputation is not guaranteed by a manifest signature.
- **High-tier real-machine acceptance is complete for v1.6.1.** Medium has only
  partial tests; Light has no complete real-machine test. Every future release
  still needs a fresh clean-VM acceptance; unit and mock tests do not replace it.

## 3. What CBS does NOT guarantee

CBS does **not** guarantee:

- that it cannot be bypassed;
- that every tool call, plugin, shell, Python path, GUI action, or egress path is
  mediated;
- that an autonomous agent cannot cause data loss or account loss;
- that a compromised owner phone, QQ account, desktop session, administrator
  account, or supply chain is contained;
- that Defender, Huorong, 360, SmartScreen, or any antivirus will not flag the
  installer, launcher, or services;
- that a 30-second bypass or 30-minute scoped token is safe for a broad or
  production directory;
- availability, compatibility with future AstrBot/QQ/DSH versions, or recovery
  of data after deletion;
- legal compliance, QQ account safety, or fitness for any particular purpose.

It is a defense-in-depth control plane for self-hosted agents, not a complete
security product and not a warranty.

## 4. Reading guide

- Product summary and quick start: [README.md](../README.md)
- Threat model and security boundaries: [SECURITY.md](../SECURITY.md)
- Installer flow: [README-INSTALL.md](../README-INSTALL.md)
- Deployment/troubleshooting: [DEPLOYMENT.md](../DEPLOYMENT.md)
- Chinese deployment guide: [docs/使用说明.md](使用说明.md)
- DSH/Cordis bridge: [docs/PLUGIN_ECOSYSTEM.md](PLUGIN_ECOSYSTEM.md)
