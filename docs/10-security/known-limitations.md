# Known limitations (v1.6.2)

This file is the authoritative list of current boundaries. It is linked from every language README.

## WFP enforce mode is not enabled

- Current policy mode: `audit`; `applied=0`.
- The native WFP filter path (`FwpmEngineOpen0` / `FwpmFilterAdd0`) is not implemented.
- The guard uses Windows Firewall rule scaffolding, not a kernel WFP filter.
- Enforce mode is blocked by: no real-machine pressure test, no clean recovery test for a failed rule update, and no proof that a deny-all state cannot survive a crash.
- Do **not** claim default-deny enforcement.

## Light tier

Light has no real-machine acceptance. It is not a substitute for High.

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
