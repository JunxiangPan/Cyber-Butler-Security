# Fail-closed check for the SYSTEM Broker runtime.
# Run from tools/broker.py startup, and also manually before deploying.
param(
    [string]$ServiceUser = 'YOUR_SERVICE_USER'
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$paths = @(
    (Join-Path $root 'tools'),
    (Join-Path $root 'AstrBot\.venv')
)
$bad = New-Object System.Collections.Generic.List[string]
$writeMask = 'Write|Modify|FullControl|TakeOwnership|ChangePermissions'
$broadPrincipals = 'Users|Everyone|Authenticated Users|YOUR_USER_NAME|' + [regex]::Escape($ServiceUser)

foreach ($path in $paths) {
    if (-not (Test-Path -LiteralPath $path)) {
        $bad.Add("missing path: $path")
        continue
    }
    $acl = Get-Acl -LiteralPath $path
    if ($acl.Owner -notmatch 'SYSTEM|Administrators') {
        $bad.Add("owner is not SYSTEM/Administrators: $path ($($acl.Owner))")
    }
    foreach ($ace in @($acl.Access)) {
        if ($ace.AccessControlType -ne 'Allow') { continue }
        if ($ace.FileSystemRights -match $writeMask -and
            $ace.IdentityReference -match $broadPrincipals) {
            $bad.Add("broad or service write ACE: $path <- $($ace.IdentityReference) $($ace.FileSystemRights)")
        }
    }
}

if ($bad.Count -gt 0) {
    $bad | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output 'Broker runtime ACL: OK'
exit 0
