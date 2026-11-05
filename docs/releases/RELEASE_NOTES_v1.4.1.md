# v1.4.1 — Correct inbound chat semantics (no Bot impersonation)

> Community acknowledgements: [CONTRIBUTORS.md](../../CONTRIBUTORS.md)

## Fixed

- The previous `POST /api/chat/send` called AgentRuntime's outbound
  `/api/v1/im/messages`, so text appeared in QQ as if **local agent** sent it. That
  was the wrong direction and a dangerous impersonation path. The outbound call
  has been removed completely.
- Web UI text now goes through the new `agentruntime_plugin_webui_bridge` plugin:
  the plugin commits a synthetic **fixed-owner inbound private event**, AgentRuntime
  processes it normally, and local agent replies through QQ.
- The Web UI only appends the user's own bubble and shows "已发送。local agent会在
  QQ 回复你。"; it does not display or fetch the bot reply.
- The bridge is inbound-only: no `send_by_session`, no arbitrary recipient, no
  outbound API. It is JWT-protected by AgentRuntime's dashboard auth, fixed to
  `owner_id`/`platform_id` config, 500 characters, rate-limited 5/min.
- Removed the sidecar's `owner_umo`/outbound configuration.

## Verified

```text
webui pytest                 9 passed
release pytest              43 passed
Direct bridge POST          200 {"ok":true,"queued":true}
Sidecar /api/chat/send      200 {"ok":true,"queued":true}
AgentRuntime event bus           主人/OWNER_QQ: Web 侧入站链路测试，请回复我。
QQ reply                    Prepare to send - 主人/OWNER_QQ: ...
```

## Package

`webui/` and `plugins/agentruntime_plugin_webui_bridge/` are included. The live
bridge config (`owner_id`, `platform_id`) is not packaged; configure it in the
AgentRuntime plugin settings or `data/config/agentruntime_plugin_webui_bridge_config.json`.
