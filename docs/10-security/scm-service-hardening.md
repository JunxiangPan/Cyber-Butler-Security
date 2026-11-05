# SCM service hardening

## Contents

- [Required binary ACL](#required-binary-acl)
- [Required account rights](#required-account-rights)
- [Runtime environment](#runtime-environment)

## Required binary ACL

```text
CyberButlerAgentRuntimeService.exe
  CyberButlerSvc:RX
  SYSTEM:F
  Administrators:F
```

The service directory must not be writable by `CyberButlerSvc` or by a desktop user.

## Required account rights

```text
SeServiceLogonRight
SeBatchLogonRight
SeDenyInteractiveLogonRight
```

`SeDenyInteractiveLogonRight` is restored after service creation. The SCM service does not require interactive logon.

## Runtime environment

The wrapper sets:

```text
AgentRuntime_SERVICE_MODE=1
AgentRuntime_ROOT=<install root>
AgentRuntime_DISABLE_GUI=1
NO_GUI=1
PYTHONUTF8=1
PYTHONIOENCODING=utf-8
MPLBACKEND=Agg
QT_QPA_PLATFORM=offscreen
DISPLAY=
```

Any GUI initialization must fail closed in Session 0, not block on a desktop.
