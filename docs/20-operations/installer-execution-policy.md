# Installer execution policy

`START-INSTALLER.exe` is a self-contained .NET single-file launcher. It starts the
visible PowerShell installer GUI with `-ExecutionPolicy Bypass` for the child
process only. This is required because the v1.6.3 installer scripts are not
Authenticode-signed yet and a clean Windows VM may use `Restricted` or
`AllSigned`, which otherwise blocks the GUI with `UnauthorizedAccess`.

The bypass is not machine-wide and does not change the system policy. It is
limited to the installer child process, which remains visible so the user can
review the elevated window. Once the installer scripts are signed, this
transitional bypass should be removed in v1.6.4.

## Runtime ACL check

The broker does not compare the ACL checker against a packaged hash. It requires
`tools/verify_broker_acl.ps1` to exist, runs it with a timeout, and requires both
exit code 0 and the explicit `Broker runtime ACL: OK` confirmation. Any missing
file, execution error, non-zero exit, or missing confirmation fails closed.
