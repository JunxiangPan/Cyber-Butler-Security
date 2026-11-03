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

`6199` is opened dynamically by the AstrBot OneBot adapter after the adapter is configured and enabled. It is not a CBS or AstrBot system service.

## Other partial controls

- Credential Proxy exists but is not fully integrated into the installer/service lifecycle.
- Full replacement of legacy audit writes with `audit_chain` is incomplete.
- Native WFP filtering remains unimplemented.
- Full clean install of the SCM installer branch has not been re-run end-to-end.

## What is verified

AstrBot SCM service, 6185, SQLite write probe, Job Object assignment, Broker 18090, WebUI 8765, OTP Mailer 8766, SnowLuma 5099, and WFP audit status on the current host.

## Third-party components

AstrBot v4.29.3 and SnowLuma v2.2.1 are external upstream applications. CBS verifies the integration boundary it owns, not the internal behaviour of those applications, their plugins, QQ clients, or upstream APIs. Hidden third-party defects and future upstream changes are outside CBS's guarantee and require revalidation after upgrades.

