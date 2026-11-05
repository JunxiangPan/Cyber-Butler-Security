# Incident: WFP empty-rule Remove failure

## Contents

- [Symptom](#symptom)
- [Cause](#cause)
- [Alternatives predicted and abandoned](#alternatives-predicted-and-abandoned)
- [Resolution](#resolution)

## Symptom

`WFP policy apply failed: Remove-NetFirewallRule failed` on every watch cycle.

## Cause

`Get-NetFirewallRule ... | Remove-NetFirewallRule` was executed even when no matching rules existed. An empty pipeline makes the remove call fail.

## Alternatives predicted and abandoned

- Ignore all errors: rejected, would hide real permission failures.
- Disable WFP Guard: rejected, removes audit evidence.
- Enable enforce mode immediately: rejected, no pressure/recovery test and no native filter.

## Resolution

Check rule count first; only call `Remove-NetFirewallRule` when rules exist. Guard remains audit-only. Current status: `ok=true`, `applied=0`.
