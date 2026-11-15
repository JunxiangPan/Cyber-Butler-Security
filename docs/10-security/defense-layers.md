# Defense layers

| Layer | Control | Current state |
|---|---|---|
| Account isolation | `CyberButlerSvc` + `SeDenyInteractiveLogonRight` | implemented |
| Service hosting | SCM service `CyberButlerAgentRuntime` | implemented and host-tested |
| Binary integrity | service binary ACL `Svc:RX / SYSTEM:F / Administrators:F` | implemented |
| Process tree | Job Object `KILL_ON_JOB_CLOSE` — lifetime containment only; **not a write filter** | implemented |
| File-write boundary | `CyberButlerSvc` SID + data-directory ACL + Broker path guard + reparse/TOCTOU checks | partially implemented; Q06 ACL and Q11a/b still required |
| TOTP approval | local Broker 18090 | implemented |
| Network policy | WFP Guard audit mode | not enforcement |
| Audit | JSONL / audit_chain sidecar | partial replacement only |
| Credential proxy | fake token / loopback injection | module exists, not fully installer-integrated |

Job Object shutdown kills the child tree; it is not a file-write authorization control. The write boundary is ACL/service SID/Broker path checking, not the Job Object.

## Non-claims

This release does not claim a native WFP filter, full audit-chain replacement, Light real-machine acceptance, or clean-VM acceptance.

## Q11 status

Q11a: PASS (service-account child denied unauthorized writes; allowed workspace write succeeded). Q11b: FAIL (synthetic Job owner left orphan child PID 6860). Q11 is not PASS. Job Object is lifetime containment only; write boundary remains ACL/service SID/Broker path guard. AppContainer is not implemented.
