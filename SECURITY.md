# Security

The canonical security documentation is:

- [Defense layers](docs/10-security/defense-layers.md)
- [SCM service hardening](docs/10-security/scm-service-hardening.md)
- [WFP network policy](docs/10-security/wfp-network-policy.md)
- [Known limitations](docs/10-security/known-limitations.md)

AgentRuntime runs as the SCM service `CyberButlerAgentRuntime` under `CyberButlerSvc`; S4U scheduled tasks are retired. WFP is audit-only in v1.6.2-rc2.

## Two-Stage Delayed Delete (两阶段延迟删除)

A high-risk `delete` approved by TOTP is not destroyed immediately. The Broker moves it to `tools/broker/trash_staging/<request_id>/` and applies an ACL that grants only `NT AUTHORITY\SYSTEM:(F)`, with explicit deny ACEs for the desktop owner and `CyberButlerSvc`. The owner has a 10-minute undo window through the CBS WebUI, which calls the authenticated Broker undo API; Explorer and the agent are not supported restore paths. When the deadline expires, a SYSTEM-only watchdog overwrites the bytes with random data for up to three passes, flushes, and deletes the entry. The staging area is capped at 500 MB or 1000 entries; exceeding it fails closed and blocks further deletes. Overwrite-based purging is best-effort, not a physical-erasure guarantee on SSDs or snapshotted storage. The signing private key is never included in staging or backups.

## Boundary Statement

CBS is a generic local Agent approval and evidence layer.
It does not own, support, certify, or endorse any specific third-party QQ client or unofficial ecosystem.

CBS provides only a generic external Agent boundary.
Whether a third-party application uses CBS, how it integrates, and whether it is compliant, is the sole responsibility of the user.

CBS tests use synthetic external agents, not real third-party applications as fixtures.

