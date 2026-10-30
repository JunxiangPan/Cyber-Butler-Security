# v1.5.0 - Router Architecture / Dual Ollama / Capacity Policy

## Description / 描述

This release introduces the router signal/gate architecture, a dedicated
embedding Ollama instance, the capacity policy, and two LivingMemory metadata
corrections. The legacy provider patch remains as a rollback path.

本次发布引入路由信号/门禁架构、独立 embedding Ollama 实例、容量策略与
两条 LivingMemory metadata 修正，并保留 legacy provider patch 作为回滚路径。

## Features / 功能

### Router Architecture / 路由架构

- New `astrbot_plugin_router` plugin.
- `/cloud` owner-only command with a 120-second one-shot grant.
- Gate is bound to the single owner and checks the actual provider.
- `legacy_provider_patch` remains available for rollback.
- 新增 `astrbot_plugin_router` 插件。
- `/cloud` 仅 owner 可用，120 秒一次性授权。
- gate 只绑定单一 owner，并依据实际 provider 判断。
- `legacy_provider_patch` 保留为回滚路径。

### Dual Ollama / 双 Ollama

- A second Ollama instance on `127.0.0.1:11435` serves bge embedding.
- `OLLAMA_KEEP_ALIVE=10m` for bge.
- qwen stays on 11434 with `FOREVER`.
- 第二个 Ollama 实例监听 `127.0.0.1:11435`，专供 bge embedding。
- bge 使用 `OLLAMA_KEEP_ALIVE=10m`。
- qwen 留在 11434，保持 `FOREVER`。

### Capacity Policy / 容量策略

- Structured `OllamaTagLookup`.
- 16k model tag for the local provider.
- `local_loaded_min_free_mb=2048`.
- `effective_cold_min=21856`.
- 结构化 `OllamaTagLookup` 查询。
- 本地 provider 使用 16k 模型 tag。
- `local_loaded_min_free_mb=2048`。
- `effective_cold_min=21856`。

### Memory Metadata / 记忆元数据

- memory 22: `historical_alias`, `fact_correction`, corrected `key_facts`.
- memory 21: `contains_duplicate_span`, `source_missing`.
- memory 22：写入 `historical_alias`、`fact_correction`，修正 `key_facts`。
- memory 21：写入 `contains_duplicate_span`、`source_missing`。

## ✅ Verification / 验证

```text
webui pytest                 22 passed
release pytest               43 passed
router pytest                12 passed
privacy scan                 OK
manifest signature           VALID
sensitive files              none
```

## ⚠️ Note / 注意

- `fact_correction` is not read by the retrieval layer; the correction is
  applied through metadata-only `key_facts` update and a single-memory graph
  rebuild.
- The 11435 PID file once pointed to a parent process, causing one stop to be
  ignored; it was corrected, but PID logic is not yet unified.
- `provider_stats` main/plugin instrumentation is still incomplete; full
  instrumentation is planned for v1.5.1.
- The 2048 threshold has thin headroom (min 2209); desktop VRAM fluctuation may
  cause router oscillation; debounce is planned for v1.5.1.
- `fact_correction` 当前检索层不读；已通过 metadata-only 更新 `key_facts`
  纠正，并对 memory 22 做了单条 graph 重建。
- 11435 PID 文件曾指向父进程，导致一次 stop 被忽略；已修正，但 PID
  逻辑尚未统一。
- `provider_stats` 主聊天/插件调用插桩仍不完整，完整插桩留 v1.5.1。
- 2048 阈值余量薄（min 2209），桌面 VRAM 波动可能导致路由抖动；
  防抖留 v1.5.1。
