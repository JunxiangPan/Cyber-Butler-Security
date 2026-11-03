# Cyber-Butler Security（CBS）


## 状态红绿灯

| 组件 | 状态 | 说明 |
|---|---|---|
| SCM 服务、SQLite 读写、Job Object | ✅ | |
| TOTP/审批 Broker 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| WFP 出站拦截——仅 audit | ⚠️ | |
| OTP Mailer 8766 / SnowLuma 5099 | ✅ | |
| 6199 OneBot 适配器——需手动配置 | ❌ | |
| Light 档——安装通过；隔离较弱 | ✅ | |
面向自托管 LLM 智能体的防御性安全控制面。

## 快速开始

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAstrBot`; port 6185 must listen.

## High 架构：原生 Windows SCM 服务

AstrBot 以 `CyberButlerSvc` 运行原生 SCM 服务 `CyberButlerAstrBot`。服务二进制 ACL 已锁定，禁止交互登录，并用 Job Object 接管子进程树。

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AstrBot\data\logs\service-astrbot.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## 本版本状态

| Item | State |
|---|---|
| SCM service 6185 | verified on host |
| SQLite write probe | passed |
| Broker 18090 | listening |
| WebUI 8765 / OTP 8766 | listening |
| SnowLuma 5099 | listening |
| WFP | audit-only, enforce not enabled |
| 6199 | dynamic OneBot adapter port, not a service |
| Light install / clean VM | ✅ install; clean VM not accepted |

Canonical source: [`docs/_data/status-v1.6.2.json`](docs/_data/status-v1.6.2.json).

## 端口

```text
6185  AstrBot SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  SnowLuma
6199  AstrBot OneBot adapter (dynamic; not a CBS service)
```

## 已知限制

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light 已完成实机安装；隔离强度弱于 High。v1.6.2 尚无干净 VM 验收。 See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## 文档

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 不是 CBS/AstrBot 的系统服务；它由 AstrBot OneBot 适配器在配置并启用后动态建立。

S4U 计划任务路径已废弃；不要再把 AstrBot 注册为计划任务。

- [FAQ — why not?](docs/00-overview/why-not-faq.md)
