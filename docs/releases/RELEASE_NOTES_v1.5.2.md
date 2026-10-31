# v1.5.2 - Router Activation / Companion Stability / Web UI Autostart

## Description / 描述

v1.5.2 activates the local-first router, hardens the private companion against
repeated and sleepy replies, and makes the Cyber-Butler Web UI and OTP mailer
survive logon without temporary background processes.

v1.5.2 启用本地优先 router，收紧私聊陪伴的复读与困意回复，并让
Cyber-Butler Web UI 与 OTP mailer 在登录后自动启动，不再依赖临时进程。

## Features / 功能

### Router activation / Router 启用

- The router now runs with `legacy_provider_patch=false`; local model routing
  is the active production path.
- Free-VRAM threshold is lowered from 1200 MB to 1000 MB because normal local
  operation leaves only a small margin with qwen on GPU and bge on CPU.
- Circuit breaker, explicit override, VRAM debounce, and game-mode routing are
  active when the local provider is healthy.
- Router 以 `legacy_provider_patch=false` 运行，本地模型路由成为生产路径。
- free VRAM 阈值从 1200 MB 降到 1000 MB；qwen 在 GPU、bge 在 CPU 时正常余量
  很小。
- local provider 健康时，circuit、显式 override、VRAM 防抖与 game-mode 路由
  均生效。

### Private companion reply guards / 私聊回复保护

- The old hard-coded `(歪头看着哥)` fallback is replaced by a neutral phrase
  pool; adjacent repeats are excluded.
- Sleepy expressions are limited in code to at most one visible reply per
  rolling ten replies, with an hourly session window.
- Duplicate detection now compares the last five non-neutral bot replies, so
  two short fallbacks cannot hide an older long reply.
- Explicit repeat requests are still served, but a near-verbatim replay is
  replaced with a persona-appropriate soft line instead of a full recital.
- 旧的固定 `(歪头看着哥)` 兜底改为中性短句池，并排除相邻重复。
- 代码级限制困意表达：滚动 10 条回复最多 1 次，按 session 小时窗口重置。
- 去重比较最近 5 条非中性 Bot 回复，短句兜底不能再遮住旧长文。
- 显式复述请求仍会响应，但近似原样背书会替换成符合人设的撒娇短句。

### Web UI autostart / Web UI 自启

- New idempotent launcher:
  `public-release/webui/start-services.ps1`.
- New task installer:
  `public-release/webui/install-startup-task.ps1`.
- Scheduled task `Cyber-Butler Web UI Services` runs at user logon (+20 s),
  Interactive / Limited, and starts:
  - Web UI `0.0.0.0:8765`
  - OTP mailer `127.0.0.1:8766`
- `AtLogOn` is intentional: the OTP mailer needs the user's DPAPI-protected
  SMTP secret, which is unavailable to a SYSTEM AtStartup task.
- 新增幂等启动脚本 `public-release/webui/start-services.ps1` 与任务安装脚本。
- 计划任务 `Cyber-Butler Web UI Services` 在用户登录后 20 秒以
  Interactive / Limited 启动 Web UI 与 OTP mailer。
- 使用登录触发是刻意选择：OTP mailer 需要当前用户的 DPAPI 邮件密钥，
  SYSTEM 开机任务无法解密。

## ✅ Verification / 验证

```text
private companion DST / duplicate / sleep tests   33 passed
AstrBot core tests                                66 passed
public-release tests                              12 passed
manual launcher cold start                        OK
launcher second run                               IDEMPOTENT (same PIDs)
scheduled task manual run                         LastTaskResult=0
```

## ⚠️ Known limitations / 已知限制

- Free VRAM remains thin: observed roughly 1200–1600 MB with the local stack,
  leaving about 200–300 MB above the 1000 MB threshold. A transient allocation
  or background GPU task can still trigger an API fallback. The threshold is
  intentionally not lowered further.
- 本地栈 free VRAM 仍偏薄：约 1200–1600 MB，高于 1000 MB 阈值只有约
  200–300 MB 余量。瞬时分配或后台 GPU 任务仍可能触发 API fallback；
  阈值不再继续下调。
- Episode UMO remains `unknown`; only `agent_type=plugin` is corrected.
- episode UMO 仍为 `unknown`，仅修正 `agent_type=plugin`。
- The Web UI autostart task runs at user logon, so the page is not available
  before interactive login.
- Web UI 自启在用户登录后执行；交互登录前不会启动。
