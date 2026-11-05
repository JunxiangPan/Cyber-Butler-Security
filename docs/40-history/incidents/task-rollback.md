# Incident: task rollback deleted the diagnostic target

## Contents

- [Symptom](#symptom)
- [Cause](#cause)
- [Alternatives predicted and abandoned](#alternatives-predicted-and-abandoned)
- [Resolution](#resolution)

## Symptom

After a Services assertion failure, `AstrBot Service` disappeared from Task Scheduler, so the failure could not be reproduced or inspected.

## Cause

The rollback unconditionally unregistered tasks created during the install.

## Alternatives predicted and abandoned

- Keep every task: rejected for other components that may be broken.
- Keep no tasks and reinstall: rejected, loses evidence.
- Manual task creation: rejected, service account password was not recoverable.

## Resolution

`Undo-CyberButlerServices` now accepts `KeepTaskDefinitions`; the Services failure path keeps `AstrBot Service` (now the SCM service definition) and only stops processes/ports.
