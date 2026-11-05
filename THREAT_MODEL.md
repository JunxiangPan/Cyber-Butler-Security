# CBS THREAT_MODEL.md

> Status: v2.0 prerequisite draft. This is not a certification and does not
> replace the threat model in [SECURITY.md](SECURITY.md).

## 1. Scope

CBS is a local security middleware for agent file/network actions. Its job is
to make the boundary between an autonomous agent and the owner's files
**explicit, deny-by-default where possible, and auditable**.

The only security decision point is the local Broker (and, for OS-level
enforcement, the Windows ACL/WFP/Job Object controls). An SDK or UI is never a
security boundary.

## 2. Trust boundary

| Principal | Trust | Notes |
|---|---|---|
| Owner (human) | trusted for approval decisions | phone/email is outside the host boundary |
| Agent / model / plugin | **untrusted** | may be prompt-injected, buggy, or compromised |
| Broker | trusted, SYSTEM | no OTP secret in agent address space |
| WebUI / installer | local administrative UI | same-user compromise is outside guarantee |
| Windows kernel / ACL / WFP | trusted OS | a local administrator can change it |

**Invariant:** the OTP code, scoped token, and broker token never enter the
agent's address space. The agent receives only a request id and status.

## 3. Minimum interface contract

The v2.0 SDK must be a **thin adapter** around these operations:

```text
POST /request
  action, target, source?, content?, manifest?, approval_only?, scoped_token?
  -> accepted/denied/requires_totp/allowed

GET  /api/request_approval/status?id=...
  -> pending/approved/denied/expired + scoped token when approved

POST /verify
  -> one-time code verification by the owner/broker path
```

Rules:

- server-side policy owns `action`, path classification, tier, and scope;
- the SDK cannot set `risk`, approve itself, or mint a token;
- the SDK must fail closed when the Broker is unreachable or returns malformed
  JSON;
- no retries that could duplicate a destructive action; use the status id;
- no shell interpolation and no implicit token refresh.

## 4. Defense boundary

In scope:

```text
filesystem ACL / separate service identity
WFP or firewall egress control for the agent SID
Job Object process-tree containment and resource limits
TOTP/approval outside the agent
TOCTOU handle binding
quarantine for destructive deletes
tamper-evident audit
```

Out of scope / residual:

```text
a local administrator can bypass or modify any local control
a compromised desktop session or phone is a credential compromise
AppContainer/restricted-token sandbox is NOT implemented in v1.6.x
no syscall sandbox, no kernel driver, no third-party audit
no guarantee against every plugin, shell, GUI, or egress path
QQ protocol account risk and model/provider behavior are external
```

## 5. AppContainer and MXC

v1.6.x **does not** implement AppContainer. It uses ACL, WFP-backed egress
rules, and Job Objects. Do not describe it as an AppContainer sandbox.

CBS will not fight Microsoft MXC at the kernel boundary. The planned
**Generate MXC Policy** feature exports a reviewable JSON policy for MXC; it is
not an enforcement claim and must never be auto-applied.

## 6. Security claims require evidence

Every public claim must map to one of:

```text
automated unit/contract test
Windows integration test
manual real-machine acceptance (with tier and result)
explicit "not implemented / not guaranteed"
```

The mapping is maintained in [docs/TEST_MATRIX.md](docs/TEST_MATRIX.md).

## Boundary Statement

CBS is a generic local Agent approval and evidence layer.
It does not own, support, certify, or endorse any specific third-party QQ client or unofficial ecosystem.

CBS provides only a generic external Agent boundary.
Whether a third-party application uses CBS, how it integrates, and whether it is compliant, is the sole responsibility of the user.

CBS tests use synthetic external agents, not real third-party applications as fixtures.

