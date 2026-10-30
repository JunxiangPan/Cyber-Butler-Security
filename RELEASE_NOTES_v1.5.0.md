# v1.5.0 - Router Architecture / Dual Ollama / Capacity Policy

## Description / 描述

This release introduces the router signal/gate architecture, a dedicated
embedding Ollama instance, the capacity policy, and two LivingMemory metadata
corrections. It keeps the legacy provider patch as a rollback path.

本次发布引入路由信号/门禁架构、独立 embedding Ollama 实例、容量策略与
两条 LivingMemory metadata 修正，并保留 legacy provider patch 作为回滚路径。

## Features / 功能

### Router Architecture / 路由架构

- New `astrbot_plugin_router` plugin.
- `/cloud` owner-only command with a 120-second one-shot grant.
- Gate is bound to the single owner and checks the actual provider.
- `legacy_provider_patch` remains available for rollback.

### Dual Ollama / 双 Ollama

- A second Ollama instance on `127.0.0.1:11435` serves bge embedding.
- `OLLAMA_KEEP_ALIVE=10m` for bge.
- qwen stays on 11434 with `FOREVER`.

### Capacity Policy / 容量策略

- Structured `OllamaTagLookup`.
- 16k model tag for the local provider.
- `local_loaded_min_free_mb=2048`.
- `effective_cold_min=21856`.

### Memory Metadata / 记忆元数据

- memory 22: `historical_alias`, `fact_correction`, corrected `key_facts`.
- memory 21: `contains_duplicate_span`, `source_missing`.

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
