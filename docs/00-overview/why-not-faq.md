# FAQ — why not?

### Why not Docker?

Docker does not solve Windows service-account isolation, ACLs, or TOTP vault ownership. It can hide the host boundary and make SCM/service debugging harder. This project targets a native Windows boundary.

### Why not block directly in the application layer?

Because the agent often owns the application layer. A compromised agent can edit its own checks. The broker, SCM service, ACLs, and Job Object sit outside the agent.

### Why phone TOTP instead of a yes/no button?

A local button can be automated by the same user session. A separate device makes approval an intentional human action and provides a recovery path.

### Why not run AgentRuntime as SYSTEM?

SYSTEM is more privilege than AgentRuntime needs. A dedicated `CyberButlerSvc` plus a service boundary limits blast radius.

### Why keep WFP in audit mode?

The native WFP filter is not implemented and enforce mode has not passed pressure/recovery testing. Audit-only is honest; fake enforcement would be worse.

### Why is 6199 missing?

It is not a CBS service. It is opened by AgentRuntime's AgentProtocol adapter after configuration.
