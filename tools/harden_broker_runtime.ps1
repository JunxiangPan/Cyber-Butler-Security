# One-shot elevated ACL hardening for the SYSTEM Broker runtime.
# Run only during deployment, from an elevated PowerShell, after testing.
# This intentionally removes inherited write access from the desktop user.
param(
    [string]$ServiceUser = 'YOUR_SERVICE_USER'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$paths = @(
    (Join-Path $root 'tools'),
    (Join-Path $root 'AstrBot\.venv')
)

foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "missing path: $path"
    }
    Write-Host "Hardening $path ..."
    # Make Administrators the owner, then remove inherited low-privilege write.
    takeown.exe /f $path /a /r /d Y | Out-Null
    icacls.exe $path /inheritance:r `
        /grant:r "SYSTEM:(OI)(CI)F" `
        /grant:r "*S-1-5-32-544:(OI)(CI)F" `
        /grant:r "${ServiceUser}:(OI)(CI)RX" | Out-Null
}

Write-Host 'Done. Re-run tools/verify_broker_acl.ps1 and restart the Broker.'
Write-Host 'WARNING: updates to these paths now require an elevated administrator.'
