# v1.5.1 - Router Skeleton / Telemetry / Overlay Packaging

## Description / 描述

v1.5.1 completes provider telemetry for plugin calls, keeps the router
skeleton dormant behind `legacy=true`, unifies cloud-fallback to owner
automatic fallback, and packages the affected core and plugin files through
single-file overlays with backup and rollback.

v1.5.1 补齐插件调用的 provider telemetry，将 router skeleton 保持在
`legacy=true` 后休眠，统一 cloud-fallback 为 owner 自动 fallback，并通过
单文件 overlay 交付相关 core 与 plugin 文件，支持备份与回滚。

## Features / 功能

### Block 1: provider_stats / 调用统计

- `agent_type` now distinguishes `main`, `plugin`, `internal` and
  `cloud_override`; calls no longer fall into `unknown`.
- `Context.llm_generate` defaults to `agent_type=plugin`; `tool_loop_agent`
  keeps `internal`.
- Plugin calls without an explicit trace get `{main_trace}:plugin:{uuid4}`,
  so they do not collide with main or internal traces.
- Main and subagent traces are recorded distinctly; cloud override relabels an
  existing trace instead of creating a second row.
- `provider_stats` now records UMO, conversation_id and trace_id for plugin
  calls.
- `agent_type` 区分为 `main`、`plugin`、`internal`、`cloud_override`，
  不再落入 `unknown`。
- `Context.llm_generate` 默认 `agent_type=plugin`；`tool_loop_agent` 保持
  `internal`。
- 未显式传 trace 的 plugin 调用使用 `{main_trace}:plugin:{uuid4}`，避免与
  main/internal trace 冲突。
- 主链与子代理 trace 分别落行；cloud override 在原 trace 上改标签，不再
  产生第二行。
- plugin 调用的 UMO、conversation_id、trace_id 写入 `provider_stats`。

### Block 2: router skeleton / router 骨架

- Circuit breaker, explicit override, VRAM debounce and `game_mode` routing
  are implemented.
- `game_mode` is persisted in `router_state`; `game_start` / `game_end`
  update it, and an explicit `/cloud` override wins over game mode.
- A game mode older than 8 hours logs a WARN without auto-clearing.
- **Router routing remains dormant:** v1.5.1 keeps `legacy=true`, so circuit,
  override, debounce and game-mode routing do not affect production provider
  selection.
- circuit、显式 override、VRAM 防抖与 `game_mode` 路由已实现。
- `game_mode` 持久化到 `router_state`；`game_start` / `game_end` 更新状态，
  显式 `/cloud` 优先于 game mode。
- game mode 超过 8 小时只记录 WARN，不自动清除。
- **router 路由仍休眠：** v1.5.1 保持 `legacy=true`，circuit、override、
  防抖与 game-mode 路由不会影响生产 provider 选择。

### Memorix telemetry / Memorix 统计

- The memorix bridge forwards `agent_type=plugin`, UMO, conversation_id and
  trace_id.
- Summary resolves its real UMO and conversation_id, but keeps provider
  resolution on the default DeepSeek path via `telemetry_umo`.
- The end-to-end test goes through real `SummaryService`, `SummaryImporter`,
  `AstrBotLLMClient`, `AstrBotProviderBridge` and `provider_stats`.
- Episode segmentation has no reliable UMO source; `agent_type=plugin` is
  corrected, while episode UMO remains unknown.
- memorix bridge 透传 `agent_type=plugin`、UMO、conversation_id 与 trace_id。
- Summary 解析真实 UMO 与 conversation_id，但通过 `telemetry_umo` 让 provider
  解析继续走默认 DeepSeek。
- 端到端测试使用真实 `SummaryService`、`SummaryImporter`、
  `AstrBotLLMClient`、`AstrBotProviderBridge` 与 `provider_stats`。
- episode segmentation 没有可靠 UMO 来源；已修正 `agent_type=plugin`，
  episode UMO 仍为 unknown。

### Cloud fallback / 云端 fallback

- Selected semantics A: owner automatic fallback; `/cloud` is only an optional
  manual override.
- Non-legacy mode signals the router and does not require `/cloud`.
- 采用语义 A：owner 自动 fallback；`/cloud` 只是可选手动覆盖。
- 非 legacy 模式只向 router 发信号，不再要求 `/cloud`。

### apply-overlay / overlay 交付

- Three fixed mappings:
  - `overlay/astrbot/core/` -> `AstrBot/astrbot/core/`
  - `overlay/astrbot/dashboard/` -> `AstrBot/astrbot/dashboard/`
  - `overlay/astrbot/data/plugins/` -> `AstrBot/data/plugins/`
- Per-file hashes are backed up under `backups/overlay-{timestamp}/`;
  failures restore and compare the original hashes.
- Missing target plugins and missing manifest overlay files are skipped with a
  WARN instead of creating partial directories.
- The fixed `update_merge.ps1` is included in the package.
- The public-release router file is directly synced with the live router.
- 三条固定映射：
  - `overlay/astrbot/core/` -> `AstrBot/astrbot/core/`
  - `overlay/astrbot/dashboard/` -> `AstrBot/astrbot/dashboard/`
  - `overlay/astrbot/data/plugins/` -> `AstrBot/data/plugins/`
- 逐文件 hash 备份到 `backups/overlay-{timestamp}/`；失败时回滚并比对
  原始 hash。
- 目标插件不存在或 manifest 中 overlay 文件缺失时 WARN 并跳过，不创建
  不完整目录。
- 包内包含修复版 `update_merge.ps1`。
- public-release router 已与 live router 直接同步。

## ✅ Verification / 验证

```text
AstrBot pytest                 58 passed
release pytest                 12 passed
privacy scan                   OK
overlay private-identifier scan clean
manifest signature             VALID
router package tests           2 passed
update/overlay tests           10 passed
```

## ⚠️ Note / 注意

- **Router routing remains dormant: it requires `legacy=false` to take effect;
  the switch is planned for v1.5.2.** v1.5.1 keeps `legacy=true`.
- **Episode UMO is still unknown.** Only `agent_type=plugin` is corrected in
  v1.5.1; UMO repair is evaluated for v1.5.2.
- **Current default provider is DeepSeek.** Summary/episode background calls
  intentionally stay on DeepSeek by the B decision.
- **router 路由休眠，需 legacy=false 才生效，v1.5.2 切换。** v1.5.1 保持
  `legacy=true`。
- **episode umo 仍为 unknown。** v1.5.1 只修正 `agent_type=plugin`；
  UMO 修复在 v1.5.2 评估。
- **current default provider deepseek。** 按 B 决策，summary/episode 后台调用
  继续使用 DeepSeek。
