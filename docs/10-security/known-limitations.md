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

## What is verified

AgentRuntime SCM service, 6185, SQLite write probe, Job Object assignment, Broker 18090, WebUI 8765, OTP Mailer 8766, AuxRuntime 5099, and WFP audit status on the current host.

## Third-party components

AgentRuntime v4.29.3 and AuxRuntime v2.2.1 are external upstream applications. CBS verifies the integration boundary it owns, not the internal behaviour of those applications, their plugins, QQ clients, or upstream APIs. Hidden third-party defects and future upstream changes are outside CBS's guarantee and require revalidation after upgrades.

## WFP enforce status in v1.6.3

WFP remains in audit mode in v1.6.3. CBS does not currently provide an outbound enforcement block at the WFP layer. The red-team defence matrix therefore reports the WFP unknown-egress test as **FAIL**, not PASS or SKIP, until a real enforce implementation and rollback test exist.


## Installer SBOM scope

`artifacts/START-INSTALLER.exe.sbom.json` is generated from the self-contained
`START-INSTALLER.deps.json`. It lists the .NET runtime pack and ILLink task and
sets `nuget_packages` to an empty list because `build/StartInstaller.csproj`
has no `PackageReference`.

It is not a recursive third-party NuGet graph. This is an explicit scope
limitation, not a claim that every transitive package was audited.
