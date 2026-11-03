# WFP / Windows Firewall guard

## Current mode

```text
mode: audit
applied: 0
status: wfp-guard-status.json ok=true
```

The guard runs as SYSTEM. It validates the service SID, reads `webui\data\network-policy.json`, and writes status. Audit mode does **not** install block rules.

## Why enforcement is not enabled

- The native WFP filter API (`FwpmEngineOpen0` / `FwpmFilterAdd0`) is not implemented.
- Firewall rule cleanup previously failed on an empty rule set; the guard now checks for matching rules before removing them.
- Enforce mode has not passed real-machine pressure or recovery testing.
- A failed firewall update must not silently leave a deny-all state.

## Do not claim

Do not describe v1.6.2 as "WFP enforced" or "network default-deny validated". It is audit-only.
