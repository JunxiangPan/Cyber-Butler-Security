# v1.6.2 — SCM Service Release

> This is the current v1.6.2 release note. Earlier `v1.6.2-preview`, `v1.6.2-beta`, and `v1.6.2-rc` files are historical and superseded.

## Contents

- [Highlights](#highlights)
- [Verified on the current host](#verified-on-the-current-host)
- [Why S4U was retired](#why-s4u-was-retired)
- [SQLite fix](#sqlite-fix)
- [WFP status — read this before claiming network isolation](#wfp-status-read-this-before-claiming-network-isolation)
- [Other known limitations](#other-known-limitations)
- [Compatibility](#compatibility)
- [Upgrade / install](#upgrade-install)
- [Documentation](#documentation)

## Highlights

- **AstrBot now runs as a native Windows SCM service.** High tier uses `CyberButlerAstrBot` under `CyberButlerSvc`, not an S4U scheduled task.
- **SQLite write failure resolved.** The service wrapper uses absolute paths, a fixed working directory, a data-directory write probe, and the corrected data ACL. The AstrBot database opens read/write and 6185 listens.
- **Job Object owns the child tree.** `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` is set before launch; descendants are terminated when the service stops.
- **Service account isolation restored.** `SeDenyInteractiveLogonRight` is restored; service logon uses `SeServiceLogonRight`.
- **Service binary ACL locked.** `CyberButlerSvc:RX`, `SYSTEM:F`, `Administrators:F`.
- **S4U retired.** On this local non-domain Windows host, Task Scheduler rejected both S4U and Password registration; a SYSTEM launcher was rejected as a privilege-escalation surface.

## Verified on the current host

```text
6185  LISTEN  AstrBot SCM service
18090 LISTEN  TOTP Broker
8765  LISTEN  WebUI
8766  LISTEN  OTP Mailer
5099  LISTEN  SnowLuma
6199  DOWN    Dynamic OneBot adapter port; not a system service
```

Additional evidence:

```text
SERVICE_START account=CyberButlerSvc
SERVICE_DATA_WRITE_OK
SERVICE_CHILD ... job=assigned
WFP guard status: ok=true, mode=audit, applied=0
```

## Why S4U was retired

- Task Scheduler rejected S4U registration with `Access is denied`.
- Task Scheduler rejected Password registration with `username or password incorrect`, even though `runas` worked.
- The SYSTEM launcher workaround worked but created a SYSTEM parent process and an unnecessary privilege-escalation surface.
- The final design uses SCM, which does not depend on Task Scheduler account logon.

## SQLite fix

The failure was not a simple file permission:

- High's data ACL made the data root read-only for the service account.
- SQLite needs to create `-wal` / `-shm` beside `data_v4.db`.
- A stale broad delete-deny on the install root was inherited by data.
- The first service wrapper did not prove data-directory write access before launching Python.

The final wrapper logs `SERVICE_DATA_WRITE_OK` before starting AstrBot. The host service now opens SQLite read/write and listens on 6185.

## WFP status — read this before claiming network isolation

**WFP enforce mode is not enabled.** The guard runs as SYSTEM in **audit** mode:

```text
mode: audit
applied: 0
status: wfp-guard-status.json ok=true
```

The native WFP filter API (`FwpmEngineOpen0` / `FwpmFilterAdd0`) is not implemented. Enforce mode is blocked by lack of pressure testing, no clean recovery test for a failed rule update, and no proof that a deny-all state cannot survive a crash. Do not describe v1.6.2 as “WFP enforced” or “default-deny validated”.

## Other known limitations

- Light tier has no real-machine acceptance.
- v1.6.2 has no clean-VM full install/uninstall acceptance.
- Credential Proxy is not fully integrated into the installer/service lifecycle.
- Full replacement of legacy audit writes with `audit_chain` is incomplete.
- 6199 is not a CBS/AstrBot service; it is opened dynamically by the AstrBot OneBot adapter after that adapter is configured and enabled.

## Compatibility

- v1.6.1 remains the previous stable release.
- v1.6.2 preview/beta/rc notes are historical; this note supersedes them.
- High tier requires administrator rights; the service runs as `CyberButlerSvc`.
- Do not install v1.6.2 as a normal stable upgrade until the clean-VM acceptance is completed.

## Upgrade / install

1. Back up `AstrBot\data`, `tools	otp-vault`, `SnowLuma` configuration, and `webui\data`.
2. Run `START-INSTALLER.exe` as administrator.
3. Choose High + Loopback, or the tier you have validated.
4. At TOTP, scan the QR and save recovery codes offline.
5. Verify `CyberButlerAstrBot`, port 6185, and `service-astrbot.log`.

## Documentation

- [Documentation index](../README.md)
- [SCM architecture](../00-overview/architecture-scm.md)
- [Known limitations](../10-security/known-limitations.md)
- [Ports and adapters](../20-operations/ports-and-adapters.md)
- [Documentation audit](../90-audit/DOCUMENTATION_AUDIT_v1.6.2.md)
