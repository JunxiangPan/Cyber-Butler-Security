# Incident: ACL self-lock

## Contents

- [Symptom](#symptom)
- [Cause](#cause)
- [Alternatives predicted and abandoned](#alternatives-predicted-and-abandoned)
- [Resolution](#resolution)

## Symptom

After hardening, administrators could not read/replace the service task or task binary; `Register-ScheduledTask` returned access denied even after `takeown` of the task file.

## Cause

Task definition and directory ACLs were changed without preserving the administrators/SYSTEM management path; a running service also locked its binary.

## Alternatives predicted and abandoned

- Delete the service/task without backup: rejected.
- Run everything as SYSTEM: rejected.
- Add Everyone full control: rejected, privilege escalation.

## Resolution

Stop the SCM service before replacing the binary; keep administrators/SYSTEM full control of the service directory; use a dedicated read-only service binary ACL for `CyberButlerSvc`. Task rollback preserves the external agent service definition on assertion failure.
