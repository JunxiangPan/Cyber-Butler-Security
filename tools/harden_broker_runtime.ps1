# One-shot elevated ACL hardening for the SYSTEM Broker runtime.
# Run only during deployment, from an elevated PowerShell, after testing.
# This intentionally removes inherited write access and grants the desktop
# account read/execute only, so game-mode can still load its script.
param(
    [string]$ServiceUser = '',
    [string]$DesktopUser = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$paths = @(
    (Join-Path $root 'tools'),
    (Join-Path $root 'python')
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
        /grant:r "${ServiceUser}:(OI)(CI)RX" `
        /grant:r "${DesktopUser}:(OI)(CI)RX" | Out-Null
    foreach ($broadSid in @('*S-1-5-32-545', '*S-1-5-11', '*S-1-1-0')) {
        icacls.exe $path /remove:g $broadSid 2>$null | Out-Null
    }
}

Write-Host 'Done. Re-run tools/verify_broker_acl.ps1 and restart the Broker.'
Write-Host 'WARNING: updates to these paths now require an elevated administrator.'
