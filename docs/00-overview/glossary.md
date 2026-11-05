# Glossary — zero-background cards

| Term | Plain-language meaning |
|---|---|
| SCM | Windows 的“服务管家”：开机自动启动、崩溃可重启，不需要用户登录桌面。 |
| CyberButlerAgentRuntime | 本项目注册的 Windows 服务名；真正跑 AgentRuntime 的是它。 |
| CyberButlerSvc | 专用于 AgentRuntime 的本地服务账户；不是你的日常登录账户。 |
| S4U | 计划任务的一种“不存密码也能跑”的登录方式；本机拒绝，已废弃。 |
| Job Object | Windows 的进程树管理；关掉主进程时，它偷偷跑出来的子进程也会被一起清掉。 |
| WFP | Windows 的底层网络过滤平台；当前仅做审计，不强制拦截。 |
| ACL | 文件/目录的“谁能读、谁能写、谁能删”清单。 |
| TOTP | 手机验证器上的 6 位动态码；比只看 AI 文字说明更可靠。 |
| Broker | 本机 18090 上的审批服务；负责 TOTP/审批，不直接执行 AI 代码。 |
| AgentProtocol adapter | AgentRuntime 的 QQ 适配器；6199 是它运行时才打开的端口，不是系统服务。 |
