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

$secretNames = @('totp_secret.dpapi', 'totp_recovery.json')
foreach ($name in $secretNames) {
    $secretPath = Join-Path (Join-Path $root 'tools') $name
    if (-not (Test-Path -LiteralPath $secretPath)) {
        $bad.Add("missing protected TOTP file: $secretPath")
        continue
    }
    try {
        $secretAcl = Get-Acl -LiteralPath $secretPath
        $denyRead = @($secretAcl.Access | Where-Object {
            $_.AccessControlType -eq 'Deny' -and
            (([string]$_.IdentityReference) -eq $ServiceUser -or ([string]$_.IdentityReference).Contains([string][char]92 + $ServiceUser)) -and
            $_.FileSystemRights -match 'Read|ReadData|ReadAttributes|ReadExtendedAttributes|ReadPermissions'
        })
        if ($denyRead.Count -eq 0) {
            $bad.Add("missing explicit Deny Read for $ServiceUser on $secretPath")
        }
    } catch {
        $bad.Add("cannot read ACL for ${secretPath}: $($_.Exception.Message)")
    }
}

if ($bad.Count -gt 0) {
    $bad | ForEach-Object { Write-Error $_ }
    exit 1
}
Write-Output 'Broker runtime ACL: OK'
exit 0
