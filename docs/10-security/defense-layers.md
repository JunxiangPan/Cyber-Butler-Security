# Defense layers

| Layer | Control | Current state |
|---|---|---|
| Account isolation | `CyberButlerSvc` + `SeDenyInteractiveLogonRight` | implemented |
| Service hosting | SCM service `CyberButlerAgentRuntime` | implemented and host-tested |
| Binary integrity | service binary ACL `Svc:RX / SYSTEM:F / Administrators:F` | implemented |
| Process tree | Job Object `KILL_ON_JOB_CLOSE` | implemented |
| Data split | sensitive subdirectories read-only; runtime DB root writable | implemented with host repair |
| TOTP approval | local Broker 18090 | implemented |
| Network policy | WFP Guard audit mode | not enforcement |
| Audit | JSONL / audit_chain sidecar | partial replacement only |
| Credential proxy | fake token / loopback injection | module exists, not fully installer-integrated |

## Non-claims

This release does not claim a native WFP filter, full audit-chain replacement, Light real-machine acceptance, or clean-VM acceptance.
