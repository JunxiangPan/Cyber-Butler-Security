# DST Guard：对话状态感知的防复读架构

这份文档描述 `astrbot_plugin_private_companion` 中的 DST（Dialogue-State Tracking）防复读补丁。它不是一份完整插件源码，而是一套可审查、可移植的运行时设计；完整插件仍由使用者在自己的 AstrBot 数据目录中维护。

目标不是“检测某个词”，而是判断用户这一轮到底是在：

- 顺着同一话题追问；
- 换了一个话题；
- 只回了一个敷衍词。

这三种状态对应完全不同的回复策略。

## 行为矩阵

| 用户状态 | 判定 | AI 行为 | 去重策略 |
| --- | --- | --- | --- |
| 同一话题追问 | `followup` | 继续回答、补充细节，禁止强行转移话题 | 跳过旧话题去重，允许复用关键词 |
| 明确换话题 | `new` | 停止旧话题，给出全新回应 | 开启旧话题去重；相似度超过阈值时重写/兜底 |
| 敷衍/无意义 | `filler` | 一句短回应，或轻巧抛出新话题 | 长回复强制缩短 |

## 1. Prompt 层

`astrbot_plugin_private_companion_config.json` 的 `reply_style_prompt` 中加入了通用 DST 规则：

```text
【对话状态感知（DST）与通用反刍禁令】
1. 同一话题的连续追问：必须顺着回答，禁止强行转移话题。
2. 明确换话题：立即停止旧话题，不要无意义地反复扯旧账。
3. 敷衍或无意义输入：只回一句短回应，禁止长篇大论。
4. 禁止连续 3 轮重复相同的核心观点、情绪词或括号动作。
5. “追问”优先于“防复读”：用户继续深挖时允许复用旧话题关键词。
```

这里不再出现“困/累”这类具体词语补丁。

## 2. 插件层

### 2.1 用户意图

`helpers.py` 新增两个纯函数：

```python
def _dst_user_intent(current, previous) -> str:
    """Returns followup / filler / new."""
    compact = re.sub(r"[\s...]+", "", str(current or ""))
    if not compact:
        return "filler"
    if _DST_FILLER_RE.match(compact):
        return "filler"
    if _DST_FOLLOWUP_RE.search(compact):
        return "followup"
    if previous and _text_similarity(current, previous) >= 0.42:
        return "followup"
    return "new"
```

追问词包含“真的吗 / 然后呢 / 为什么 / 怎么会 / 还有呢 / 继续 / 具体一点 / 什么意思”等通用表达，不是某一个话题的词表。

```python
def _dst_reply_similarity(reply, recent_replies) -> float:
    """Highest normalized similarity against recent bot replies."""
```

相似度取字符 n-gram 与 `SequenceMatcher` 的组合，并剔除“哥 / 我 / 的 / 了 / 啊 / 有点 / 今天”等噪声词。

### 2.2 状态存储

在用户消息写入点保存上一轮用户输入：

```python
user["previous_user_message"] = str(user.get("last_user_message") or "")
user["last_user_message"] = safe_text or text
```

在确认发送的 Bot 回复写入点保存上一轮 Bot 回复：

```python
user["previous_companion_message"] = str(user.get("last_companion_message") or "")
user["last_companion_message"] = visible_text
```

因此插件可以判断“与上一轮用户输入相比，是在追问还是换话题”，而不只比较 Bot 回复。

### 2.3 回复复核

`user_memory.py::_response_review_flags()` 新增：

```text
followup -> 移除 repeated_topic / repeats_last_bot_message
filler   -> 回复超过 80 字时加 dst_filler_too_long
new      -> 与最近两轮 Bot 回复相似度不低于 0.60 时加 dst_stale_topic_repeat
```

`dst_stale_topic_repeat` 与 `dst_filler_too_long` 被列入 severe flags，触发已有的被动回复复核：

```text
⚠️ 用户已经换了话题或停止追问，这条回复正在复读旧话题。
请立刻给出全新的回应，不要重复上一条 Bot 的核心观点、情绪词或括号动作。
```

复核本身就是一次“重写重试”。若重写后仍重复：

```text
(歪头看着哥)
```

以短动作把主动权交还用户，而不是继续输出旧话题。

### 2.4 追问豁免

`_should_drop_duplicate_reply_text()` 在 `followup` 时直接返回 `False`：

```python
if _dst_user_intent(inbound_text, user.get("previous_user_message")) == "followup":
    return False, ""
```

这是“该深入就深入”的关键：追问时允许 AI 继续使用同一话题的词汇和细节，不会因为相似度高而被误杀。

### 2.5 分段关闭

当复核或兜底触发 DST 时：

```python
event._private_companion_dst_disable_segmenting = True
```

`apply_segmented_llm_reply_scope()` 检测该标记后直接返回单条消息：

```python
if bool(getattr(event, "_private_companion_dst_disable_segmenting", False)):
    return
```

这样触发防复读重写时，不会再把多句话拆成多条 QQ 消息。

### 2.6 主动消息冷却

`_record_dst_guard()` 记录 10 分钟窗口内的触发次数：

```text
3 次 DST 触发
→ dst_proactive_cooldown_until = now + 600
→ next_proactive_at 延后
```

连续触发时降低主动聊天频率，避免“拦截了被动回复却马上又主动发起”的体验问题。

## 3. 部署方式

这是对本地 `astrbot_plugin_private_companion` 的运行时补丁，不是本仓库发布的独立插件包。部署时应：

1. 备份插件目录与 `astrbot_plugin_private_companion_config.json`；
2. 将补丁应用到 `AstrBot/data/plugins/astrbot_plugin_private_companion/`；
3. 保留本地 `companions.json`、长期记忆数据库和配置；
4. 重启 AstrBot；
5. 发送两类测试消息：
   - “真的吗？然后呢？为什么？”应继续深入；
   - “算了不说这个了，来聊点别的”应停止旧话题。

## 4. 安全边界

- DST 去重只作用于被动私聊回复；不影响用户明确要求复述原文。
- 不删除长期记忆；它只调整当前回复和主动消息冷却。
- 完整 `private_companion` 目录约有 44 MB、973 个文件，包含本地运行数据与测试资产，**不随公开 release 一起分发**。
- 公开仓库只保存这套设计的文档和可审查代码片段；生产插件文件应通过单独备份/补丁管理。

## 5. 测试

`tests/test_dst_guard.py`：

```text
真的吗 / 然后呢 / 为什么会这样 -> followup
在吗 / 来玩点别的 -> new
嗯 / 哦 / ？ -> filler
相似旧回复 -> 高相似度
新话题回复 -> 低相似度
```

本地结果：

```text
4 passed
py_compile: OK
AstrBot plugin loaded: OK
```

## Standalone plugin installation

The open-source package now includes a small, independent implementation:

```text
plugins/astrbot_plugin_dst_guard/
├── main.py
├── metadata.yaml
└── tests/test_dst_guard_plugin.py
```

It does **not** import the 44 MB companion plugin. It provides the same
three-state behavior through AstrBot hooks:

1. `on_llm_request` remembers the previous user turn and appends the generic
   DST rule to the request system prompt;
2. `on_llm_response` classifies the current turn as follow-up / new topic /
   filler;
3. a follow-up is left untouched, a filler reply over 80 characters is
   shortened, and a new-topic reply that is too similar to the last two bot
   replies is replaced with `(歪头看着哥)`;
4. when a rewrite happens it sets
   `event._private_companion_dst_disable_segmenting = True`, so the optional
   companion plugin can disable QQ segmentation.

### Install

1. Back up the existing AstrBot data directory.
2. Copy `plugins/astrbot_plugin_dst_guard/` into
   `AstrBot/data/plugins/`.
3. Enable `astrbot_plugin_dst_guard` in the AstrBot plugin panel.
4. Restart AstrBot.
5. Optional: add the `dst_guard` block from `config.pro.example.json` to the
   plugin configuration. Defaults are shown there.

The standalone plugin keeps state in memory per `unified_msg_origin`; it does
not write chat history, memory databases, or user data.

### Test

```bash
cd plugins/astrbot_plugin_dst_guard
python -m pytest -q tests/test_dst_guard_plugin.py
```

Expected:

```text
4 passed
```

### Relationship to private_companion

Run this plugin **instead of**, or alongside, the companion's built-in DST
patch. When both are active, the companion's reply-review pass still owns the
full rewrite/retry path; the standalone plugin is the portable fallback and
sets the same segmentation-disable marker.

