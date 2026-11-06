# Cyber-Butler Security（CBS）


## 发布验证说明

CBS 的发布包经过了 CBP 流水线的基础拦截，但这并不能证明代码绝对安全。CBP 只能检查常见的低级错误和明显伪造，不能替代独立安全评审，也不能阻止拥有特权的操作者绕过流程。

## Release verification

CBS release packages pass CBP baseline gates; this does not prove absolute security.

## 状态红绿灯

| 组件 | 状态 | 说明 |
|---|---|---|
| SCM 服务、SQLite 读写、Job Object | ✅ | |
| TOTP/审批 Broker 18090 | ✅ | |
| WebUI 8765 | ✅ | |
| WFP 出站拦截——仅 audit | ⚠️ | |
| OTP Mailer 8766 / AuxRuntime 5099 | ✅ | |
| 6199 AgentProtocol 适配器——需手动配置 | ❌ | |
| Light 档——安装通过；隔离较弱 | ✅ | |
面向自托管 LLM 智能体的防御性安全控制面。

## 快速开始

- Windows 10/11 x64, administrator rights.
- Run `START-INSTALLER.exe`; choose High, Loopback, and the personal plugin path.
- Scan the TOTP QR and store recovery codes offline.
- Verify: `Get-Service CyberButlerAgentRuntime`; port 6185 must listen.

## High 架构：原生 Windows SCM 服务

AgentRuntime 以 `CyberButlerSvc` 运行原生 SCM 服务 `CyberButlerAgentRuntime`。服务二进制 ACL 已锁定，禁止交互登录，并用 Job Object 接管子进程树。

- Service binary ACL: `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored.
- Log: `AgentRuntime\data\logs\service-agentruntime.log`.
- Job Object: `KILL_ON_JOB_CLOSE`.

## 本版本状态

| Item | State |
|---|---|
| SCM service 6185 | verified on host |
| SQLite write probe | passed |
| Broker 18090 | listening |
| WebUI 8765 / OTP 8766 | listening |
| AuxRuntime 5099 | listening |
| WFP | audit-only, enforce not enabled |
| 6199 | dynamic AgentProtocol adapter port, not a service |
| Light install / clean VM | ✅ install; clean VM not accepted |

Canonical source: [`docs/_data/status-v1.6.2.json`](docs/_data/status-v1.6.2.json).

## 端口

```text
6185  AgentRuntime SCM service
18090 TOTP Broker
8765  WebUI
8766  OTP Mailer
5099  AuxRuntime
6199  AgentRuntime AgentProtocol adapter (dynamic; not a CBS service)
```

## 已知限制

WFP enforce mode is **not enabled**; the guard is audit-only (`applied=0`). Native WFP filtering is not implemented. Light 已完成实机安装；隔离强度弱于 High。v1.6.2 尚无干净 VM 验收。 See [`docs/10-security/known-limitations.md`](docs/10-security/known-limitations.md).

## 文档

- [Documentation index](docs/README.md)
- [SCM architecture](docs/00-overview/architecture-scm.md)
- [Known limitations](docs/10-security/known-limitations.md)
- [Ports and adapters](docs/20-operations/ports-and-adapters.md)
- [Troubleshooting](docs/20-operations/troubleshooting.md)

6199 不是 CBS/AgentRuntime 的系统服务；它由 AgentRuntime AgentProtocol 适配器在配置并启用后动态建立。

legacy S4U 计划任务路径已废弃；不要再把 AgentRuntime 注册为计划任务。

- [FAQ — why not?](docs/00-overview/why-not-faq.md)

## 签名格式变更（v1.6.3 起）

从 v1.6.3 起，`update-manifest.json` 使用四文件签名格式
（manifest + BUILD_REPORT + FINAL_QA_REPORT + ACCEPTANCE_PROOF）。
旧版本（v1.6.2 及之前）的 `update-manifest.sig` 在新 `verify_release.py`
下会 INVALID，必须显式使用 `--legacy` 才能验旧签名。

## 边界声明 / Boundary Statement

CBS 是一个通用的本地 Agent 审批与证据层。
它不拥有、不支持、不认证、不推荐任何具体的第三方 QQ 客户端或非官方生态。

CBS 只提供通用的外部 Agent 接入边界。
第三方应用是否使用 CBS、如何接入、是否合规，由用户自行判断并承担全部责任。

CBS 的测试使用 synthetic external agent，不使用任何真实第三方应用作为 fixture。

