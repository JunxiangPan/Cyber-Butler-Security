# v1.5.3 - Fail-Closed Router / Owner-Only Ops Bridge / Web UI Exposure Warning

## Description / 描述

v1.5.3 hardens the router's failure semantics, adds an owner-only read-only
`/dsh` bridge for status, health and logs, and documents the Web UI's
`0.0.0.0` exposure boundary.

v1.5.3 收紧 router 的失败语义，新增只给 owner 使用的只读 `/dsh` 状态桥，
并记录 Web UI 绑定 `0.0.0.0` 的暴露边界。

## Features / 功能

### Router fail-closed / 断路器 fail-closed

- `gate` exceptions are logged at error level and call
  `_send_route_unavailable(reason="gate_exception")`; the event is stopped.
- A circuit-store read failure returns `UNKNOWN`. The gate rejects
  `UNKNOWN` instead of treating it as `CLOSED`.
- `legacy_provider_patch` is tri-state:
  - explicit `true` = legacy rollback;
  - explicit `false` = router active;
  - read failure = unavailable, fail-closed.
- When the local probe/circuit is unavailable and the API circuit is
  `OPEN`/`UNKNOWN`, the turn is rejected explicitly.
- Authorized cloud fallback remains possible only while the API circuit is
  neither `OPEN` nor `UNKNOWN`.
- 新增 fail-closed 语义：gate 异常记录 error 并发送不可用提示、停止事件。
- circuit 读取失败返回 `UNKNOWN`，gate 直接拒绝，不再假装 `CLOSED`。
- `legacy_provider_patch` 三态处理：显式 true 回滚、显式 false 启用、
  读取失败拒绝。
- 本地探测/circuit 不可用且 API circuit 为 `OPEN`/`UNKNOWN` 时明确拒绝。
- 仅当 API circuit 非 `OPEN`/`UNKNOWN` 时允许已授权的 cloud fallback。

### Owner-only `/dsh` read-only bridge / 只读运维桥

New plugin: `astrbot_plugin_dsh_bridge`.

- Owner private chat only; group messages and non-owner senders are denied
  without revealing whether the command exists.
- Exact commands only:
  - `/dsh status`
  - `/dsh health`
  - `/dsh logs <n>` (`1 <= n <= 200`)
- No restart/reload, no natural-language parsing, no LLM call, no shell.
- `status` reads `context.provider_manager.inst_map` in-process and the
  `router_state` row; it exposes only `id`, `type`, `enabled` and `model`.
- `health` probes loopback ports `6185`, `18090`, `8765`, `8766` with TCP
  connect only; a down port returns `degraded`, not a command failure.
- `logs` reads only `console-final.err.log`, tail-capped, redacted and
  length-limited.
- All three commands are read-only and deliberately do **not** require the
  DSH 3188 ingress. A future write command must add its own fail-closed
  precheck before acting.
- Every command appends one JSONL record to
  `C:\ProgramData\CyberButler\audit\ops.jsonl` with only
  `ts`, `command`, `result`.
- 新增 `astrbot_plugin_dsh_bridge`：只允许 owner 私聊，固定三条只读命令；
  不重启、不重载、不调 LLM、不执行 shell。
- `status` 进程内读取 provider 与 `router_state`，只输出
  `id / type / enabled / model`。
- `health` 只做 6185 / 18090 / 8765 / 8766 的 TCP 探测，单端口失败返回
  `degraded`。
- `logs` 只读 `console-final.err.log`，脱敏、截断、限制行数。
- 三条命令都是只读查询，不再依赖 DSH 3188；未来新增写操作时必须自行补
  fail-closed 预检。
- 审计固定为三字段 JSONL，不记录 prompt 全文、owner ID 或日志正文。

### Web UI exposure / Web UI 暴露面

- The Web UI still binds `0.0.0.0` for LAN + Tailscale direct access.
- The LAN firewall rule is `Profile=Private`; it must stay that way.
- README and DEPLOYMENT carry a bilingual warning: security relies
  entirely on Windows Firewall, and a disabled rule or misclassified network
  can expose the UI.
- Web UI 为 LAN + Tailscale 直连继续绑定 `0.0.0.0`。
- LAN 防火墙规则为 `Private`，必须保持。
- README 与 DEPLOYMENT 增加中英双语警告：安全性完全依赖 Windows 防火墙，
  规则关闭或网络误判可能导致暴露。

### Data repair / 数据修复

- Memory 20/21 `source_json` was backfilled from messages 391-412:
  22 messages, 6551 characters each.
- The stale expression index `idx_doc_create_time` was rebuilt; the live
  `livingmemory.db` now returns `PRAGMA integrity_check = ok`.
- 已将 Memory 20/21 的 `source_json` 按消息 391-412 回填：各 22 条、
  6551 字符。
- 已重建陈旧的表达式索引 `idx_doc_create_time`；当前 `livingmemory.db`
  的 `integrity_check` 返回 `ok`。

## ✅ Verification / 验证

```text
astrbot_plugin_dsh_bridge tests             24 passed
AstrBot router tests                        47 passed
Cyber-Butler root tests                     47 passed, 4 skipped
public-release tests                        51 passed
Web UI tests                                23 passed
```

Manual checks:

```text
/dsh status -> audit {"command":"status","result":"ok"}
/dsh health -> 6185, 18090, 8765, 8766 all up
/dsh logs 5 -> console-final.err.log tail returned and redacted
```

Firewall verification (read-only):

```powershell
Get-NetFirewallRule -DisplayName 'Cyber-Butler Web UI (LAN)' |
  Select-Object DisplayName,Enabled,Profile,Direction,Action
# Profile: Private
```

## ⚠️ Known limitations / 已知限制

- Web UI still binds `0.0.0.0`; a firewall failure or misclassified network
  profile can expose port 8765.
- `0.0.0.0` is required for simultaneous LAN and Tailscale direct access;
  binding only `127.0.0.1` would require Tailscale Serve and would remove LAN
  direct access.
- The `/dsh` bridge is read-only. It intentionally has no restart/reload or
  write path; a future write command must add its own fail-closed precheck.
- Web UI 仍绑定 `0.0.0.0`；防火墙失效或网络 Profile 误判可能暴露 8765。
- 若同时保留 LAN 与 Tailscale 直连，需要 `0.0.0.0`；只绑
  `127.0.0.1` 必须改用 Tailscale Serve 并放弃 LAN 直连。
- `/dsh` 桥只读，不提供 restart/reload 或写操作；未来新增写命令必须自行
  补 fail-closed 预检。
