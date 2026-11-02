# Roadmap / 路线图

> This roadmap describes intended direction, not a delivery promise. Security
> work is gated on reproducible tests and a signed release; dates are not
> commitments. The v1.6.1 scope is frozen.

## v1.6.2 — Windows Filtering Platform and tamper evidence

**Goal:** make the network and runtime boundary enforceable at the OS layer,
not only by application policy.

- **WFP outbound controls**: evaluate Windows Filtering Platform callouts for
  AstrBot/Agent processes so loopback broker traffic is allowed but unexpected
  egress is denied by default. Start with audit-only mode; only enforce after a
  documented rollback path and per-process identity tests exist.
- **Tamper-evident audit**: hash-chain JSONL audit records and add a signed
  checkpoint. This detects local edits by a non-administrator; it does not stop
  a local administrator.
- **Installer auto-provisioning**: create the AstrBot Open API key (`im` scope)
  during install, write `.astrbot_token` with restricted ACL, and self-test
  `/api/v1/im/messages` before reporting success.
- **SnowLuma reverse-WS bootstrap**: when an existing
  `SnowLuma\config\onebot_*.json` is present, ensure a `wsClients` entry for
  `ws://127.0.0.1:6199/ws` with the matching AstrBot token; never overwrite an
  existing user token. Verify `6199 Established` before claiming success.
- **Broker config bootstrap**: ship `broker_config.example.json`; create
  `broker_config.json` on first install, default to the configured email channel
  when an admin email exists, and preserve it on upgrade.
- **Installer finish**: harden the delete flow against locked service profiles
  and prove the extraction folder is removed after the launcher exits.
- **Release checks**: an automated acceptance matrix for High, with explicit
  “not run” status for Medium/Light rather than inferred success.

**Exit criteria**

```text
WFP audit evidence on a clean VM
no unexpected outbound connection in the High test scenario
audit chain verify command passes after restart
SnowLuma bootstrap and 6199 check pass on a profile with no wsClients
installer token self-test returns HTTP 200
```

## v1.7 — Temporal replay and pipeline

**Goal:** let an owner reconstruct and safely replay what an agent did without
turning the audit log into a second execution path.

- **Time-travel reconstruction**: a read-only timeline over audit, file
  quarantine, tool calls, and approvals; show before/after hashes and actor.
- **Deterministic pipeline replay**: replay a recorded sequence in a sandbox
  with network and filesystem writes disabled by default.
- **Approval diff**: show a structured diff for overwrite/write/delete before
  the TOTP prompt; never render a raw path as the only evidence.
- **Quarantine browser**: browse and restore Broker-quarantined files with a
  second approval; restoration is never automatic.
- **Cross-agent correlation**: correlate AstrBot, DSH, and Broker events by a
  shared request id, while keeping token and TOTP material out of the timeline.

**Exit criteria**

```text
replay produces the same hashes as the recorded result in a sandbox
network/FS mutations are denied by default in replay mode
a corrupted audit record is detected and the timeline marks the gap
restore requires a fresh approval and leaves an audit record
```

## v2.0 — Cross-platform SDK

**Goal:** expose the boundary as a portable SDK without pretending Windows ACL
semantics exist everywhere.

- **Platform adapters**: Windows (ACL + WFP + Job Objects), macOS (sandbox
  profiles / EndpointSecurity evaluation), Linux (Landlock, seccomp, cgroups,
  nftables) behind one capability interface.
- **Stable approval protocol**: versioned request/status/verify schemas,
  capability negotiation, idempotency keys, and replay-safe status polling.
- **Policy-as-data**: declarative path/action rules with a signed policy bundle;
  the policy engine remains server-side and fail-closed.
- **SDK packages**: TypeScript and Python clients for DSH/Cordis and native
  agents; no shell interpolation and no implicit token refresh.
- **Reference conformance suite**: one test corpus run against every adapter;
  unsupported capabilities must be reported, never silently emulated.
- **Threat-model publication**: per-platform guarantees and residual risks,
  including what the SDK cannot protect against a local administrator.

**Exit criteria**

```text
same policy corpus passes on Windows/macOS/Linux
unsupported capability returns a typed, fail-closed error
two independent agents use the same approval protocol without shared state
third-party security review of the protocol and at least one adapter
```

## Non-goals

```text
guaranteed non-bypassability against a local administrator
protection against a compromised phone, QQ account, or desktop session
antivirus/SmartScreen reputation guarantees
a claim of third-party security certification
```
