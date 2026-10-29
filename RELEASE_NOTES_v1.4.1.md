# v1.4.1 — Correct inbound chat semantics (no Bot impersonation)

## Fixed

- The previous `POST /api/chat/send` called AstrBot's outbound
  `/api/v1/im/messages`, so text appeared in QQ as if **苏瑾言** sent it. That
  was the wrong direction and a dangerous impersonation path. The outbound call
  has been removed completely.
- Web UI text now goes through the new `astrbot_plugin_webui_bridge` plugin:
  the plugin commits a synthetic **fixed-owner inbound private event**, AstrBot
  processes it normally, and 苏瑾言 replies through QQ.
- The Web UI only appends the user's own bubble and shows "已发送。苏瑾言会在
  QQ 回复你。"; it does not display or fetch the bot reply.
- The bridge is inbound-only: no `send_by_session`, no arbitrary recipient, no
  outbound API. It is JWT-protected by AstrBot's dashboard auth, fixed to
  `owner_id`/`platform_id` config, 500 characters, rate-limited 5/min.
- Removed the sidecar's `owner_umo`/outbound configuration.

## Verified

```text
webui pytest                 9 passed
release pytest              43 passed
Direct bridge POST          200 {"ok":true,"queued":true}
Sidecar /api/chat/send      200 {"ok":true,"queued":true}
AstrBot event bus           主人/OWNER_QQ: Web 侧入站链路测试，请回复我。
QQ reply                    Prepare to send - 主人/OWNER_QQ: ...
```

## Package

`webui/` and `plugins/astrbot_plugin_webui_bridge/` are included. The live
bridge config (`owner_id`, `platform_id`) is not packaged; configure it in the
AstrBot plugin settings or `data/config/astrbot_plugin_webui_bridge_config.json`.
