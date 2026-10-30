# Cyber-Butler / 苏瑾言部署与排障交接

## 记忆数据位置（重要）

| 数据 | 实际文件 | 表/字段 | 说明 |
|---|---|---|---|
| 原始逐条消息 | `AstrBot/data/plugin_data/astrbot_plugin_livingmemory/conversations.db` | `messages(id, session_id, role, content, sender_id, sender_name, group_id, platform, timestamp, metadata)` | 苏瑾言与用户的原始对话。`messages.id` 就是排障时使用的消息 ID。 |
| 会话列表 | 同上 | `sessions(...)` | LivingMemory 的会话记录。 |
| 记忆正文 | `AstrBot/data/plugin_data/astrbot_plugin_livingmemory/livingmemory.db` | `documents(id, doc_id, text, metadata, ...)` | 长期记忆主库；`metadata` 含 `source_window`、人格、主题、关键事实。 |
| 记忆原文窗口 | 同上 | `memory_sources(memory_id, source_json, ...)` | `resummarize_memory` 真正读取的 source。`source_json` 保存本次记忆覆盖的原始消息数组。 |
| 记忆原子/图 | 同上 | `memory_atoms`、`graph_entries`、`graph_nodes`、`graph_edges` | 记忆派生数据。 |
| 图文档库 | `AstrBot/data/plugin_data/astrbot_plugin_livingmemory/livingmemory_graph_documents.db` | `documents` 等 | 图记忆文档；回滚图相关摘要时一并处理。 |

### 不是记忆主库

`AstrBot/data/data_v4.db` 只有 AstrBot 核心数据：

- `conversations`：核心会话记录，不是逐条原始消息表；
- `provider_stats`：模型/token 用量；
- `personas`、`preferences`、`platform_*` 等。

**`data_v4.db` 没有 `messages` 表。** 排障时不要到这里找逐条聊天记录。

## `resummarize_memory` 的读取链路

```text
Page API
  -> memory_engine.get_memory_record(memory_id)        # livingmemory.db.documents
  -> memory_engine.get_memory_source(memory_id)        # livingmemory.db.memory_sources.source_json
  -> restore_source_messages(source)
  -> memory_processor.process_conversation(...)
  -> memory_engine.replace_memory(...)                 # livingmemory.db
```

所以：

- **source window 来自 `livingmemory.db.memory_sources`**；
- **不来自 `data_v4.db`**；
- **不是直接重读 `conversations.db`**。

如果 `memory_sources` 没有对应 `memory_id`，API 会返回“没有可重新总结的完整原文”，即使 `documents.metadata.source_window` 存在也不行。

## 备份与恢复

记忆摘要相关备份必须包含：

```text
AstrBot/data/data_v4.db
AstrBot/data/plugin_data/astrbot_plugin_livingmemory/conversations.db
AstrBot/data/plugin_data/astrbot_plugin_livingmemory/livingmemory.db
AstrBot/data/plugin_data/astrbot_plugin_livingmemory/livingmemory_graph_documents.db
```

恢复原则：

- 原始消息在 `conversations.db`，**不删除、不覆盖**；
- 只回滚记忆摘要时，恢复 `livingmemory.db` 的 memory 相关表（必要时含图文档库）；
- 不要用 `data_v4.db` 的 `conversations` 代替 LivingMemory 的原始消息。

## 快速检查

```sql
-- 原始消息
SELECT id, role, substr(content, 1, 80), timestamp
FROM messages WHERE id BETWEEN 334 AND 413 ORDER BY id;

-- 记忆正文与 source window
SELECT id, substr(text, 1, 120), metadata
FROM documents ORDER BY id DESC;

-- 某个记忆的 source 是否存在
SELECT memory_id, length(source_json)
FROM memory_sources WHERE memory_id IN (18, 19, 20, 21);

-- source 最大消息 ID（用于判断是否有记忆覆盖）
SELECT MAX(CAST(json_extract(j.value, '$.id') AS INTEGER))
FROM memory_sources, json_each(memory_sources.source_json) AS j;
```

## 已知网络暴露面（需用户确认）

当前主 Ollama（11434）设置 `OLLAMA_HOST=0.0.0.0`。

**影响：**

- 局域网内可访问 11434；
- 可拉取/删除模型、运行推理；
- 这是已知暴露面，**本轮不改**，但需要用户确认是否符合预期；
- 不阻塞本轮 VRAM 治理。

**如果要收紧，两种方案：**

1. 改绑定：
   - 在 Ollama 服务/启动环境设置 `OLLAMA_HOST=127.0.0.1:11434`；
   - 重启 Ollama；
   - 用 `netstat -ano | findstr :11434` 确认只监听 loopback；
   - 回滚改为 `0.0.0.0:11434` 并重启。

2. 防火墙限制：
   - 只允许 `127.0.0.1` 访问 11434；
   - 拒绝局域网入站；
   - 不改 11434 的 `OLLAMA_HOST`；
   - 需单独验证不会影响本机 AstrBot/embedding 调用。

计划中的第二个 Ollama（11435）只绑定 `127.0.0.1`，不新增防火墙规则。

## 2026-10-30 重总结记录

- `memory 18 -> 22`，`memory 19 -> 23` 已通过 `resummarize_memory` 重做，source 仍为 330–350、351–370。
- `memory 20/21` 只有 `documents.metadata.source_window`，没有 `memory_sources.source_json`，因此不能直接 resummarize。
- 09:39 的原始消息 402–405 被 memory 21 的正文覆盖，但 memory 21 没有 source_json；不要误以为“没有 memory 覆盖”。
- 备份目录：`AstrBot/data/backups/memory_resummarize_20261030_130411`。

## 2026-10-30 VRAM 治理记录

- 新增 `sujinyan-chat-16k:latest`，`num_ctx=16384`；保留 `sujinyan-chat-24k:latest` 用于回滚。
- `local_qwen36.model` 已切到 16k。
- 第二个 Ollama 实例：`127.0.0.1:11435`，共享 `D:\.ollama\models`，`OLLAMA_KEEP_ALIVE=10m`，仅用于 bge。
- embedding base 已改为 `http://127.0.0.1:11435/v1`。
- bge 在 11434/11435 均已停止；qwen 16k-only 采样：
  - min 2209 MiB / median 2219 MiB / max 2239 MiB（60 samples）。
- `local_loaded_min_free_mb` 定为 2048；`effective_cold_min=21856`。
- AstrBot 已通过 `/api/v1/system/restart` 重启（新进程 13400）。
- **运维说明**：11435 的启动/停止状态以发布包内脚本和 PID 文件为准；历史手动启动细节不再展开。

### 阈值抖动规则（路由设计）

`local_loaded_min_free_mb=2048` 时，单次采样低于 2048 不立即切换；必须**连续 3 次采样**都低于 2048 才切 DeepSeek。单次低于只记录，不切换。


## 2026-10-30 provider_stats 历史口径与数据保护

- `internal` 226 条是 **v1.4.4 之前**的历史行；`main` 3 条是 v1.4.4 之后的新行。两者不代表同一时期的主聊天量，不能直接相加比较。
- `provider_stats.umo` 含完整 QQ 号；`data_v4.db` 按敏感文件保护：不提交、不外发，备份必须加密保存。
- 主聊天非 streaming 时，`time_to_first_token` 固定为 `0.0`，看板显示“未测量”；要获得真实 TTFT，需要启用 streaming。

## 2026-10-30 Router 信号端点

实际挂载路径（AstrBot 插件 Web API）：

```text
POST /api/v1/plugins/extensions/astrbot_plugin_router/signal
Authorization: Bearer <astrbot-token>
X-Router-Signal-Token: <router-signal-dpapi-token>
```

- `/api/router/signal` 不是最终路径；直接请求会 405。
- 双 token：
  - `Authorization: Bearer`：AstrBot 的 `.astrbot_token`；
  - `X-Router-Signal-Token`：DPAPI 保护的 router signal token。
- 下一轮 `game-mode.ps1` 和 `cloud_fallback` 改造必须使用上述路径和双 token。
- AstrBot token 获取：项目根目录 `.astrbot_token`（`<PROJECT_ROOT>\.astrbot_token`）。game-mode 已使用 `$AstrBotRoot/.astrbot_token`；cloud_fallback 使用 `ROOT/.astrbot_token`。
- Router token：`C:\ProgramData\CyberButler\secrets
outer_signal.token.dpapi`，只能通过 DPAPI 解密，不写入 outbox。

## 2026-10-30 Router legacy / /cloud / 回滚

- `AstrBot/data/router/settings.json`：`legacy_provider_patch` 默认 `true`，保留旧 PATCH 回滚路径；设为 `false` 才由 router 接管。
- `/cloud`：owner 私聊命令，120 秒一次性授权；非 owner/群聊拒绝；连续 `/cloud` 刷新 TTL。
- cloud_fallback：legacy=true 走旧 PATCH；legacy=false 只发 local_unavailable/local_ready 信号。
- game-mode：legacy=true 走旧 PATCH；legacy=false 只发 game_start/game_end + outbox，信号失败不先停模型。
- 信号端点：`POST /api/v1/plugins/extensions/astrbot_plugin_router/signal`，双 token。
- 回滚：先把 `legacy_provider_patch` 设为 `true`，重启 AstrBot/game-mode；旧 PATCH 路径恢复。若 router 异常，fail closed，不自动切云。
- 注意：AstrBot 端口 6185 被旧 supervisor 占用时，新进程可能只起 dashboard 不处理消息；需要先停止 supervisor/task 再启动。

## 测试注意事项（Live 测试）

- live 测试不得直接写生产 `AstrBot/data/plugin_data/astrbot_plugin_livingmemory/conversations.db`。
- 必须使用独立测试库，或在测试前停止 LivingMemory/AstrBot 写入，并明确记录测试产生的消息数。
- 如果误写生产库，恢复时不能只覆盖主 `.db` 而保留旧 `-wal/-shm`；必须先停进程、移除 WAL/SHM、再从备份恢复并跑 `PRAGMA integrity_check`，否则会出现 btree 损坏。
- 本轮事故：bridge live 测试把 messages 从 414 写到 445；恢复时先复制主库仍带着旧 WAL，触发 `btreeInitPage error 11`；清理 WAL/SHM 后重新从 13:04 的 414 条备份恢复，才恢复 integrity ok。

## v1.5.0 Graph 重建记录

- 第一次 `index_memory(22, ...)` 失败：临时 embedding 适配器缺 `get_embeddings_batch`。
- 第二次失败：`get_embeddings_batch` 缺 `batch_size` / `tasks_limit` 参数。
- 每次失败后从 `graph_rebuild_20261030_201834` 备份恢复：
  - `livingmemory.db`
  - `livingmemory_graph_documents.db`
  - `livingmemory_graph.index`
- 第三次成功：
  - memory 22 entries 45 -> 56
  - memory 22 edges 40 -> 42
  - memory 22 entry_nodes 85 -> 99
  - vector_doc_id 29 -> 33
  - 其他 memory 的 entries/edges/entry_nodes 数量不变
  - livingmemory.db 与 graph documents DB `PRAGMA integrity_check` 均为 `ok`

## Memorix Telemetry（v1.5.1）

- `AstrBotProviderBridge.generate_text()` 现在会传 `agent_type="plugin"`；UMO / conversation_id / trace_id 在调用方提供时透传。
- summary 使用独立的 `telemetry_umo`：provider 解析仍用空 UMO，保持 deepseek；统计里的 UMO 才是真实会话。
- **episode umo 仍为 unknown**：episode_segmentation 当前没有 UMO 来源，不硬编；`agent_type=plugin` 已修正，UMO 修复在 v1.5.2 评估。
- 不要把 lecture/本地文件路径写进 provider_stats；统计只保存 UMO / conversation_id / trace_id。

## Release 签名私钥

- 私钥：`C:\ProgramData\CyberButler\keys\update_private.pem`
- 公钥：`C:\ProgramData\CyberButler\keys\update_public.pem`
- 仓库公钥：`public-release/tools/update_pubkey.pem`
- 三者 RSA-3072，SHA-256 指纹：`3eabcb7813e15e86aff649030aeafc03eb1ebd005b5104c88527bae38fc8de93`
- 权限：仅 Administrators / SYSTEM 可读写；不进入 Git、不进入 zip。

## Web UI / OTP 开机自启（2026-10-30）

- 启动脚本：`public-release\webui\start-services.ps1`
- 安装脚本：`public-release\webui\install-startup-task.ps1`
- 计划任务：`Cyber-Butler Web UI Services`
- 触发：用户 `PCVP\pjx20` 登录后 20 秒（`AtLogOn`，Interactive / Limited）
- 不用 `AtStartup`/SYSTEM 的原因：OTP mailer 需要当前用户的 DPAPI 邮件密钥；SYSTEM 下解不开。
- Web UI：`0.0.0.0:8765`
- OTP mailer：`127.0.0.1:8766`

手动启动 / 幂等验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "D:\qq苏瑾言大肥鱼\public-release\webui\start-services.ps1"
Start-ScheduledTask -TaskName 'Cyber-Butler Web UI Services'
Get-ScheduledTaskInfo -TaskName 'Cyber-Butler Web UI Services'
```

日志：

```text
public-release\webui\data\webui-startup.log       启动脚本（每次检查/跳过）
public-release\webui\data\webui.out.log           Web UI 标准输出
public-release\webui\data\webui.err.log           Web UI 错误输出
public-release\webui\data\otp_mailer.log          OTP mailer 内部日志
public-release\webui\data\otp_mailer.out.log      OTP 标准输出
public-release\webui\data\otp_mailer.err.log      OTP 错误输出
```

手动验证结果：首次启动创建 8765/8766；第二次运行保持同一 PID，未重复拉起；计划任务手动运行 `LastTaskResult=0`。
