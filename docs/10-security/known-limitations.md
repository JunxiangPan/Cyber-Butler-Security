# Known limitations (v1.6.2)

## Contents

- [WFP enforce mode is not enabled](#wfp-enforce-mode-is-not-enabled)
- [Light tier](#light-tier)
- [Clean VM acceptance](#clean-vm-acceptance)
- [6199 is not a service](#6199-is-not-a-service)
- [Other partial controls](#other-partial-controls)
- [What is verified](#what-is-verified)

This file is the authoritative list of current boundaries. It is linked from every language README.

## WFP enforce mode is not enabled

- Current policy mode: `audit`; `applied=0`.
- The native WFP filter path (`FwpmEngineOpen0` / `FwpmFilterAdd0`) is not implemented.
- The guard uses Windows Firewall rule scaffolding, not a kernel WFP filter.
- Enforce mode is blocked by: no real-machine pressure test, no clean recovery test for a failed rule update, and no proof that a deny-all state cannot survive a crash.
- Do **not** claim default-deny enforcement.

## Light tier

Light installation passed on a real machine, but its isolation is weaker than High. It is not a substitute for High.

## Clean VM acceptance

v1.6.2 has not completed a clean-VM install/upgrade/uninstall run. Host-side SCM validation passed on one machine only.

## 6199 is not a service

`6199` is opened dynamically by the AgentRuntime AgentProtocol adapter after the adapter is configured and enabled. It is not a CBS or AgentRuntime system service.

## Other partial controls

- Credential Proxy exists but is not fully integrated into the installer/service lifecycle.
- Full replacement of legacy audit writes with `audit_chain` is incomplete.
- Native WFP filtering remains unimplemented.
- Full clean install of the SCM installer branch has not been re-run end-to-end.

## Job Object is lifetime containment only

`JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE` cleans up the process tree when the last
Job handle closes. It is not a write filter and does not replace ACLs, a
separate service token, Broker path checks, reparse-point rejection, or TOCTOU
checks.

The claim "Broker crashed -> tree cleaned" requires evidence that the Broker is
the sole Job handle owner, children do not inherit/duplicate the handle, and
the last handle closes on normal and abnormal termination. Normal close-only
tests and fake kernel32 tests are not Windows E2E evidence.

AppContainer is **not implemented**. The current file-write boundary is not an
AppContainer sandbox. Q11a (owner alive: write denied outside allowed roots)
and Q11b (owner terminated: child tree cleaned) are separate acceptance items;
either one passing alone does not make Q11 pass.

Current Windows evidence: Q11a BLOCKED (service-account child logon denied),
Q11b FAIL (synthetic Job Object child remained: PID 6652). Q11 is not PASS.

## What is verified

AgentRuntime SCM service, 6185, SQLite write probe, Job Object assignment, Broker 18090, WebUI 8765, OTP Mailer 8766, AuxRuntime 5099, and WFP audit status on the current host.

## Third-party components

AgentRuntime v4.29.3 and AuxRuntime v2.2.1 are external upstream applications. CBS verifies the integration boundary it owns, not the internal behaviour of those applications, their plugins, QQ clients, or upstream APIs. Hidden third-party defects and future upstream changes are outside CBS's guarantee and require revalidation after upgrades.

## WFP enforce status in v1.6.3

WFP remains in audit mode in v1.6.3. CBS does not currently provide an outbound enforcement block at the WFP layer. The red-team defence matrix therefore reports the WFP unknown-egress test as **FAIL**, not PASS or SKIP, until a real enforce implementation and rollback test exist.

