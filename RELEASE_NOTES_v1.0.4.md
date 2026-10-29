# v1.0.4 — UTF-8 QQ Notifications and Self-Healing

## Encoding fix

The previous manual OneBot HTTP test used a shell `curl` payload that was decoded as GBK, producing mojibake on QQ.

All project-owned QQ notification paths now send explicit UTF-8:

- `tools/snowluma_guard.py::notify`
  - `json.dumps(..., ensure_ascii=False).encode("utf-8")`
  - `Content-Type: application/json; charset=utf-8`
- `tools/boot-selfcheck.ps1::Notify-Owner`
  - `[System.Text.Encoding]::UTF8.GetBytes($json)`
  - `Content-Type: application/json; charset=utf-8`

Verified live:

```text
09:20:01 私聊 2351671738 | 发送：哥，编码修复测试：这条消息应为正常中文，不再是乱码。
```

## Self-healing retained

- `wallpaperui` / `wallpaperengine` / `wallpaper engine` ignored by game-mode.
- Boot self-check warms `sujinyan-chat-24k`, checks Ollama/AstrBot/SnowLuma, restores `local_qwen36`.
- SnowLuma guard detects an inbound `MsgPush` without a corresponding `[Event]` for five minutes and restarts SnowLuma.
- `cloud_fallback` keeps the 90-second startup grace and UTF-8 BOM-tolerant config read.

## Verification

- 17 tests passed.
- UTF-8 notification delivered and SnowLuma log displays correct Chinese.
- Boot self-check script parsed successfully.
