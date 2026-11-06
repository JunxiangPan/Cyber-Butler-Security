# Incident: S4U retirement

## Contents

- [Symptom](#symptom)
- [Alternatives predicted and abandoned](#alternatives-predicted-and-abandoned)
- [Resolution](#resolution)

## Symptom

Task Scheduler returned `Access is denied` for S4U registration and `username or password incorrect` for Password registration, even though `runas` opened cmd with the same account.

## Alternatives predicted and abandoned

1. **S4U scheduled task** - theoretically best: no stored password, service account, Task Scheduler. Rejected because local non-domain Windows refused registration.
2. **Password scheduled task** - rejected because Task Scheduler still failed authentication and High's interactive-logon deny conflicts with the task logon model.
3. **SYSTEM launcher** - works, but creates a SYSTEM parent process and a privilege-escalation surface. Rejected.
4. **Medium desktop account** - works, but removes High isolation. Rejected for High.

## Resolution

Native SCM service `CyberButlerAgent` running as `CyberButlerSvc`, with a locked binary ACL and SCM-managed recovery.
