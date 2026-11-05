# Cyber-Butler Security v1.6.2

**Release date:** 2026-11-03

Cyber-Butler Security (CBS) is a defensive control plane for self-hosted LLM agents on Windows. v1.6.2 is the first release built around a native Windows SCM service for AgentRuntime, replacing the retired S4U scheduled-task startup path.

## Highlights

### Native Windows SCM service

AgentRuntime now runs as the Windows service `CyberButlerAgentRuntime` under the dedicated local account `CyberButlerSvc`.

- The service uses an absolute Python path and an explicit working directory.
- `AgentRuntime_ROOT` points to the AgentRuntime application root, so configuration and plugin data resolve to one canonical location.
- `AgentRuntime\data\logs\service-agentruntime.log` records startup, the data-write probe, the child PID, and Job Object assignment.
- `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` terminates the AgentRuntime child tree when the service stops.
- The service binary ACL is restricted to `CyberButlerSvc:RX`, `SYSTEM:F`, and `Administrators:F`.
- `SeDenyInteractiveLogonRight` is restored; SCM uses `SeServiceLogonRight`.
- S4U and Password Task Scheduler startup paths are retired. The installer no longer registers AgentRuntime as a scheduled task.

### Isolation and approval controls

- High tier uses a dedicated service account and a split data ACL.
- The TOTP Broker listens only on loopback port 18090.
- Approval evidence is objective: path, size, hash, bounded diff, script warning, and redaction.
- File-handle-bound approval reduces TOCTOU risk.
- Protected test and policy files are denied or require explicit approval.
- Job Objects constrain process-tree lifetime.

### Operational improvements

- The WebUI has a language selector and a plain-language status surface.
- The AgentRuntime initial password is stored in a one-time administrator-readable file and is no longer forced into a change-password loop.
- The control panel exposes the AgentProtocol reverse-WebSocket address and Access Token with reveal and copy controls. The token is masked by default and is never logged.
- AuxRuntime login credentials are read from AuxRuntime's own startup log. If the initial password was never logged, CBS shows manual guidance instead of writing AuxRuntime's configuration across an account boundary.
- Game Mode runs from `%LOCALAPPDATA%\CyberButler\game-mode`; it no longer creates state or log files on the Desktop.
- The uninstaller stops and deletes the SCM service before removing its binary, and cleans the Game Mode runtime directory.

## Known limitations

These boundaries are intentional and must not be read as completed guarantees.

- **WFP is audit-only.** The guard records status and policy but does not install an enforcement filter. `wfp-guard-status.json` reports `mode: "audit"` and `applied: 0`. The native WFP filter API (`FwpmEngineOpen0` / `FwpmFilterAdd0`) is not implemented.
- **6199 is not a system service.** The AgentRuntime AgentProtocol adapter opens `6199` dynamically only after the adapter is configured and enabled. CBS does not install or manage it.
- **Light installation passed on a real machine.** Its isolation is weaker than High; High remains the only tier with a dedicated service-account design.
- **Clean-VM acceptance is not claimed by this document alone.** Use the included `tools/clean-vm-acceptance.ps1` and `docs/_data/clean-vm-expected.json` before promoting the release.
- **AuxRuntime password display is read-only.** CBS reads the initial credential from AuxRuntime's log. It does not reset AuxRuntime's password or write `AuxRuntime\config\webui.json` across account boundaries. If the password was not logged, reset it in AuxRuntime.
- **Game Mode releases local-model VRAM only.** It can unload the configured Ollama model; it cannot reduce VRAM already allocated by a running game such as War Thunder.
- **Credential Proxy and full audit-chain replacement remain partial.** They are not presented as complete in this release.

## Verification

The release assets are signed with RSA-3072 and SHA-256.

```powershell
python tools/verify_release.py `
  --manifest update-manifest.json `
  --signature update-manifest.sig `
  --pubkey update_pubkey.pem
```

Expected output:

```text
VALID
```

The ZIP, manifest, signature, and public key are the only release assets required for verification.

## Upgrade notes

- Back up `AgentRuntime\data`, `tools\totp-vault`, `AuxRuntime\config`, `AuxRuntime\data`, and `webui\data` before upgrading.
- The installer must run as administrator.
- Existing 1.6.0 installations should use the upgrade/repair path and preserve data.
- If AgentRuntime was previously reading the wrong data root, the service correction applies after the new service binary is installed.


## Third-party components and scope of validation

AgentRuntime (v4.29.3) and AuxRuntime (v2.2.1) are independent upstream applications. CBS validates the integration boundary it owns: service launch, account and ACL boundaries, port ownership, configuration hand-off, TOTP/approval routing, and health checks.

CBS does not audit or guarantee the internal behaviour of AgentRuntime, AuxRuntime, their plugins, QQ clients, upstream APIs, or future upstream releases. Hidden defects in a third-party component remain the responsibility of that upstream project. An upstream update may invalidate the tested integration and requires revalidation.

The High-tier real-machine test has been reported as completed by the operator. A full clean-VM install/upgrade/uninstall acceptance is still a separate requirement and is not claimed by this release note alone.

## Acknowledgements

CBS was shaped by the global open-source community. See [CONTRIBUTORS.md](../../CONTRIBUTORS.md) for the full record.

International community: u/Practical-Craft4967, u/QuanTradin, u/Reid Marlow, u/Auten (Auten Team), u/mp3sss, u/More-Ad7285, u/HeartMaleficent35, u/rikulauttia.

China ecosystem: Sandy (玩AI的Sandy君), 程序员阿江, 牧羊人AILab (DSQQ 作者).

AgentRuntime Community Group 18: 若宸, 墨莘子凌, and the wider group.

> “CBS 的架构不是由作者一个人闭门造车想出来的，而是全球开源社区共同打磨的结晶。”
>
> CBS's architecture was not invented alone behind a closed door; it is the result of the global open-source community polishing it together.

## License

See [LICENSE](../../LICENSE).
