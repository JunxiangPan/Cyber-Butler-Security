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

## ACL checker hash

The package build computes `tools/broker_acl_manifest.json` from the exact
`verify_broker_acl.ps1` bytes placed in the zip, and verifies the hash again by
reading the finished archive. The broker fails closed if that manifest is
missing or its path/hash does not match, so line-ending conversion or a stale
package cannot silently weaken the ACL self-check.
