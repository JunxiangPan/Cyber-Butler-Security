# Roadmap / 路线图

> This roadmap describes intended direction, not a delivery promise. Security
> work is gated on reproducible tests and a signed release; dates are not
> commitments.

Canonical test coverage and known gaps: [docs/TEST_MATRIX.md](docs/TEST_MATRIX.md).
Minimum v2.0 interface contract and trust boundaries:
[THREAT_MODEL.md](THREAT_MODEL.md).

## Current release — v1.6.6 shipped

**Status:** signed and published on 2026-11-09.

- Release: https://github.com/JunxiangPan/Cyber-Butler-Security/releases/tag/v1.6.6
- Product tag: `v1.6.6` at `29a57d9`
- Signing tooling tag: `v1.6.6-sign` at `987943a`
- Zip SHA256: `2c5e5e76d9a79d044b31f24372ed80be7a6ef6c46b91537662d0cd165a572470`

**Known debt:** Q05–Q17 were not individually re-executed; they are marked passed
under the release coverage policy, with the real VM acceptance proof as evidence.
Broker coverage is 46% for v1.6.6. v1.7 must restore the full hard gate and must
not reuse this coverage substitution as the default release method.

The next contract work is v1.7.1; it is not frozen.

## Cross-version upgrade and migration policy

**Hard rule:** a direct overwrite from v1.6.2 to v1.7.0 is forbidden.

The supported upgrade path is:

```text
v1.6.2 -> v1.6.3 (decoupling) -> v1.6.4 (signing baseline)
       -> v1.6.6 (current signed release) -> v1.7.0 (deep-water features)
```

`v1.6.5` was never released and is not a bridge. Do not omit `v1.6.6` from
upgrade documentation. The v1.7.0 minimum is proposed as `>= 1.6.6`; the final
contract freeze must confirm it.

### v1.6.2 -> v1.6.3

- The v1.6.3 installer must detect a v1.6.2 installation before changing files.
- The migration entry point is `installer/Migrate-v1.6.2-to-v1.6.3.ps1`.
- It must create a timestamped, integrity-checked backup of the user data
  before stopping or deleting anything.
- It must guide the operator to remove the old AgentRuntime SCM service and reinstall
  AgentRuntime as an independently managed application. CBS never performs that
  third-party installation.
- Data backup includes, when present: `AgentRuntime\data`, `AuxRuntime\config`,
  `AuxRuntime\data`, `AuxRuntime\logs`, `tools/totp-vault`, `webui\data`,
  `data`, Broker configuration, and audit logs.
- The backup is not encrypted by default; it is ACL-restricted and must be
  moved to offline media by the operator. Never place the signing private key
  in a backup.

### v1.7.0 and later

- The installer must block upgrades from v1.6.2 or earlier with this message:

```text
Please upgrade through v1.6.3, v1.6.4, and v1.6.6 first;
there is no direct v1.6.2 -> v1.7.0 path.
```

- A v1.7.0 installer may proceed only when the installed VERSION is at least
  `1.6.6`.
- The version gate is fail-closed: if the installed version cannot be read, the
  installer stops instead of guessing.

### Backup and rollback

- Every cross-version upgrade must offer
  `installer/Backup-CyberButler.ps1` and
  `installer/Restore-CyberButler.ps1`.
- A backup contains a manifest with SHA-256 for every payload file.
- Restore must validate the manifest before writing, stop CBS processes first,
  and offer a dry-run.
- No upgrade is complete until the operator has a successful backup and a
  tested restore path.

## v1.6.2 — WFP, anti-blind approval, and tamper evidence

**Goal:** make the network and runtime boundary enforceable at the OS layer,
not only by application policy.

- **WFP outbound controls**: bind rules to the `CyberButlerSvc` SID; allow
  loopback broker traffic; deny unexpected egress by default. Start with
  audit-only mode; enforce only after a documented rollback path and
  per-process identity tests exist.
- **Tripwire**: consume WFP/firewall blocks as
  `NETWORK_EXFILTRATION_ATTEMPT`, handle log rotation, and never freeze or kill
  a process solely on an alert.
- **Job Object limits**: `KILL_ON_JOB_CLOSE`, process/job memory, job CPU time,
  and active-process limits; no `BREAKAWAY_OK` / `SILENT_BREAKAWAY_OK`.
- **Anti-blind approval**: show server-derived path, size/mtime/hash, bounded
  diff, script warning, and redaction; never show an AI-written summary as the
  approval evidence.
- **TOCTOU**: bind approval to the opened handle and re-hash that same handle
  immediately before execution; quarantine high-risk deletes.
- **Tamper-evident audit**: hash-chain JSONL plus an anchor; strict redaction.
- **Installer auto-provisioning**: AgentRuntime Open API key (`im` scope),
  `.agentruntime_token`, AuxRuntime reverse-WS bootstrap, `broker_config` bootstrap,
  and a self-test before success is reported.
- **Physical separation**: installer/WebUI warn when the TOTP authenticator is
  on the same host.

**Exit criteria**

```text
WFP audit evidence on a clean VM
SID identity, loopback allow, and unexpected-egress events verified
no BREAKAWAY_OK in the effective Job Object
TOCTOU swap returns a rejection and never writes the changed target
quarantine manifest and restore path are tested
audit chain verifies after restart and after rotation
installer token self-test returns HTTP 200
```

## Post-v1.6.2 Backlog — Coexist with Microsoft MXC

**Decision:** do not fight Microsoft's system-level sandbox (MXC) at the
kernel boundary. CBS should be a **consumer-grade front end** that helps a user
adopt MXC correctly.

- **Generate MXC Policy**: a GUI wizard that exports the Microsoft MXC JSON
  policy shape from the same path/action/network choices the user already makes
  in CBS.
- **Import/export round-trip**: preserve unknown MXC fields, validate the
  exported document against the MXC schema version, and never auto-apply it.
- **Compatibility matrix**: document which MXC capabilities map to CBS ACL,
  WFP, Job Object, and approval controls; explicitly list gaps.
- **No bypass promise**: a generated MXC policy is not proof that an agent is
  contained. MXC version drift and local administrator access remain residual
  risks.

**Backlog entry**

```text
[ ] Generate MXC Policy (v1.7.0, optional backend)
[ ] Export a user-reviewable JSON file; no silent apply (v1.7.0)
[ ] Schema validation and round-trip tests (v1.7.0)
[ ] Map CBS controls to MXC capabilities (v1.7.0)
```

## v1.6.3 — Tiered authorization, not one approval for everything

**Goal:** remove approval fatigue without weakening the boundary. The current
Scoped Token is a transition mechanism, not the final policy.

- **Tier 1 — read:** local read/list operations inside the approved workspace
  are allowed without a TOTP challenge.
- **Tier 2 — ordinary write:** a Scoped Token authorizes
  `delete` / `overwrite` / `write_file` only within its time and canonical
  directory bound; issuing it still requires owner TOTP.
- **Tier 3 — sensitive/high-risk:** memory, config, TOTP vault, file egress,
  and any write outside the scoped directory require **immediate TOTP**, not a
  scoped token. Consider a second confirmation for vault/config mutation.
- **Policy is server-side**: the agent cannot choose its tier or upgrade a
  scoped token.
- **UX objective**: fewer prompts for routine draft edits, never fewer prompts
  for memory/config/egress.

### v1.6.3 backlog carried from the review

- **Full WebUI session/CSRF protection**: every state-changing form requires a
  session-bound CSRF token; no state-changing GET.
- **Sensitive config encryption**: DPAPI for secrets, ACL-locked config files,
  and no plaintext tokens in WebUI responses.
- **XSS hardening**: escape file names and log lines at every render boundary.
- **One-time recovery codes**: generate, display once, hash at rest, consume on
  use, and require a fresh TOTP to regenerate.
- **Overlay self-heal**: detect when an AgentRuntime upgrade overwrites an overlay
  patch and report/repair it without silently claiming success.
- **Upgrade rollback**: one-click rollback plus a documented config migration
  path.
- **Uninstall cleanup**: RunOnce removal for a locked service profile, WFP
  rules, extraction directory, and scheduled tasks.
- **AgentRuntime/DSH cache alignment**: the same scoped-token cache semantics in the
  native plugin and the DSH adapter.

**Exit criteria**

```text
read-only path produces no approval request
ordinary scoped write works only inside its bound and expires
memory/config/vault/egress always requires fresh TOTP
a scoped token cannot be replayed outside its directory or after restart
```

## Two-Stage Delayed Delete (两阶段延迟删除)

**Goal:** make a high-risk delete recoverable after a blind approval, without
turning the staging area into a new data-leak path.

- A TOTP-approved `delete` is moved to `tools/broker/trash_staging/<request_id>/`; it is not physically destroyed.
- The staging entry is ACL-locked to `NT AUTHORITY\SYSTEM:(F)`; the desktop owner and `CyberButlerSvc` receive explicit deny ACEs. The Broker, not Explorer or the agent, performs restore.
- The owner gets a 10-minute undo window. The WebUI calls a CSRF-protected backend, which calls the authenticated Broker `/trash/undo` endpoint.
- A SYSTEM-only sweeper purges expired entries. Purge overwrites the file with random bytes for up to three passes, flushes, then unlinks it.
- Staging capacity is capped at 500 MB or 1000 entries (configurable). A capacity breach is a fail-closed block on further deletes, with an audit event. Overwrite-based erasure is best-effort on SSDs; wear levelling and snapshots can retain physical copies.
- The undo API is the only supported restore path. Direct access to the staging directory is not a supported user workflow.

## v1.6.4 — Embedded Python runtime (planned)

**Goal:** remove the last external prerequisite for the offline package.

- Evaluate a signed Windows x64 CPython 3.13 embeddable runtime.
- Resolve redistribution/license, pip/venv bootstrap, DLL loading, and SBOM
  entries.
- Run the Wheelhouse install, WebUI start, Broker start, and real TOTP
  enrollment fully offline.
- Only after that test passes may documentation use the phrase
  **zero-dependency**.
- Until then, every offline statement must say:
  `Windows x64 + CPython 3.13 + bundled wheelhouse`.

This is **not** part of v1.6.3 RC.

## v1.7 — Temporal replay, IPC, and MXC (optional backends)

**Version boundary:** v1.6.3 is a mandatory bridge release. A v1.6.2 host must
complete `v1.6.2 -> v1.6.3` before any v1.7.0 installation. There is no direct
v1.6.2 -> v1.7.0 path.

The v1.7.0 line will add IPC and Microsoft MXC compatibility only as
**detectable, optional backends**:

- IPC and MXC are capability-detected, not assumed.
- They are off by default; no silent enablement and no automatic policy apply.
- Unsupported capabilities must return a typed, fail-closed result.
- CBS must not claim kernel-level containment or non-bypassability because an
  optional IPC/MXC backend is present.
- The v1.6.3 approval gateway, ACL boundary, and migration contract remain the
  supported base.

## v1.7 — Temporal replay and pipeline

**Goal:** let an owner reconstruct and safely replay what an agent did without
turning the audit log into a second execution path.

- **Time-travel reconstruction**: read-only timeline over audit, quarantine,
  tool calls, and approvals; before/after hashes and actor.
- **Deterministic pipeline replay**: replay a recorded sequence in a sandbox
  with network and filesystem writes disabled by default.
- **Quarantine browser**: restore only with a fresh approval; never automatic.
- **Cross-agent correlation**: correlate AgentRuntime, DSH, and Broker events by a
  shared request id; keep token/TOTP material out of the timeline.

**Exit criteria**

```text
replay produces the same hashes in a sandbox
network/FS mutations are denied by default
a corrupted audit record is detected and marked as a gap
restore requires a fresh approval and leaves an audit record
```

## v2.0 — Threat model first, thin SDK second

**Decision:** do not start with a large cross-framework gateway. First publish
the contract and threat model, then ship a deliberately thin adapter.

### v2.0 prerequisites

1. **`THREAT_MODEL.md`**: define the "local agent security middleware" minimum
   interface contract and defense boundary, including what is explicitly outside
   the boundary (local administrator, compromised desktop/phone, OS sandbox
   bypass).
2. **Thin SDK**: the SDK only adapts an agent's tool call into the versioned
   Broker protocol. It must not contain policy, approval, token storage, file
   access, or a second execution path. The Broker remains the only decision
   point.
3. **Protocol conformance corpus**: one request/status/verify corpus every SDK
   must pass, including fail-closed behavior when the Broker is unreachable.

### v2.0 scope

- **Platform adapters**: Windows (ACL + WFP + Job Objects), macOS (sandbox
  profiles / EndpointSecurity evaluation), Linux (Landlock, seccomp, cgroups,
  nftables) behind one capability interface.
- **Stable approval protocol**: versioned schemas, capability negotiation,
  idempotency keys, replay-safe status polling.
- **Policy-as-data**: signed policy bundle; server-side, fail-closed.
- **SDK packages**: TypeScript and Python clients; no shell interpolation and no
  implicit token refresh.
- **Reference conformance suite**: unsupported capabilities must be reported,
  never silently emulated.
- **Third-party review**: protocol and at least one adapter.

**Exit criteria**

```text
THREAT_MODEL.md is published and reviewed before SDK implementation starts
same protocol corpus passes on Windows/macOS/Linux
unsupported capability returns a typed fail-closed error
SDK contains no policy/approval/token implementation
third-party review of the protocol and one adapter
```

## Test and release matrix

All security claims must map to a test or be explicitly marked as a manual/
missing test. The authoritative table is
[docs/TEST_MATRIX.md](docs/TEST_MATRIX.md).

```text
High   full real-machine end-to-end acceptance
Medium multiple partial tests; complete real-machine acceptance pending
Light  complete real-machine acceptance pending; unit/contract tests only
```

Light real-machine testing is a required release gate from v1.6.3 onward; it is
not optional because the tier is "minimal".

## Non-goals

```text
guaranteed non-bypassability against a local administrator
protection against a compromised phone, QQ account, or desktop session
antivirus/SmartScreen reputation guarantees
a claim of third-party security certification
fighting Microsoft MXC at the kernel boundary
making the SDK a second security boundary
```

## Documentation lifecycle gate

Every major release (for example v1.6.x to v1.7.x) must complete a seven-round documentation audit before packaging. The audit covers structure, deduplication, eight-language consistency, Markdown/link checks, known limitations, GitHub-facing cleanup, and UX readability.

Obsolete documents must be moved to `docs/40-history/archive/` with `[ARCHIVED - 已废弃]` at the top. They are never deleted. The canonical status source is `docs/_data/status-v1.6.2.json`; CI runs `tests/test_docs_consistency.py` on every pull request.

## v1.6.4 — Engineering debt (deferred from v1.6.3)

- Split `tools/broker.py` into `broker_core.py`, `broker_policy.py`, `broker_audit.py`, and `broker_totp.py` without changing `TargetSnapshot`.
- Raise Broker test coverage above 80% and add hash-pinned runtime dependency lock.
- Resolve Pillow/filelock CVEs when the Python 3.10 floor is raised.
- Fix the self-contained `START-INSTALLER.exe` C# shell: on a clean VM it exits 0 without launching the GUI; direct `powershell.exe -File installer\CyberButler.Installer.GUI.ps1` works. Investigate single-file `Environment.ProcessPath` / UAC relaunch / `Process.Start` visibility and add a VM smoke test for the C# launcher.
- Raise Broker test coverage above 80%, especially exception paths.
- Add `requirements-runtime.lock` with dependency hashes.
- Upgrade CBP SHA-256 self-seal to a DPAPI key + HMAC signature.
- Fix the C# self-contained `START-INSTALLER.exe` silent-exit launcher and add a VM smoke test.
- Install `jinja2` in CI and restore WebUI template/API tests.
