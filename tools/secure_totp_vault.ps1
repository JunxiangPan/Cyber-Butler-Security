#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$desktop = 'YOUR_USER_PATH\Desktop'
$vault = 'YOUR_USER_PATH\Documents\苏瑾言TOTP保险箱'
$files = @(
    (Join-Path $desktop '苏瑾言TOTP.png'),
    (Join-Path $desktop '苏瑾言TOTP恢复码.txt')
)
$log = 'YOUR_PROJECT_PATH\tools\secure_totp_vault.log'
Set-Content -LiteralPath $log -Value ('secure vault ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

New-Item -ItemType Directory -Force -Path $vault | Out-Null
foreach ($file in $files) {
    if (Test-Path -LiteralPath $file) {
        $dest = Join-Path $vault (Split-Path $file -Leaf)
        Move-Item -LiteralPath $file -Destination $dest -Force
        Log ('moved ' + $file + ' -> ' + $dest)
    } else {
        Log ('missing ' + $file)
    }
}

$user = (whoami)
$rules = @(
    @{ Identity = $user; Rights = 'FullControl'; Type = 'Allow' },
    @{ Identity = 'SYSTEM'; Rights = 'FullControl'; Type = 'Allow' },
    @{ Identity = 'BUILTIN\Administrators'; Rights = 'FullControl'; Type = 'Allow' },
    @{ Identity = 'YOUR_HOST\YOUR_SERVICE_USER'; Rights = 'FullControl'; Type = 'Deny' }
)

$dirAcl = New-Object System.Security.AccessControl.DirectorySecurity
$dirAcl.SetAccessRuleProtection($true, $false)
foreach ($rule in $rules) {
    $ace = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $rule.Identity, $rule.Rights,
        [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit',
        [System.Security.AccessControl.PropagationFlags]'None',
        [System.Security.AccessControl.AccessControlType]$rule.Type)
    $dirAcl.AddAccessRule($ace)
}
Set-Acl -LiteralPath $vault -AclObject $dirAcl
Log ('vault ACL set: ' + $vault)

Get-ChildItem -LiteralPath $vault -File -Force | ForEach-Object {
    $fileAcl = New-Object System.Security.AccessControl.FileSecurity
    $fileAcl.SetAccessRuleProtection($true, $false)
    foreach ($rule in $rules) {
        $ace = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $rule.Identity, $rule.Rights,
            [System.Security.AccessControl.InheritanceFlags]'None',
            [System.Security.AccessControl.PropagationFlags]'None',
            [System.Security.AccessControl.AccessControlType]$rule.Type)
        $fileAcl.AddAccessRule($ace)
    }
    Set-Acl -LiteralPath $_.FullName -AclObject $fileAcl
    Log ('file ACL set: ' + $_.FullName)
}

Write-Output 'TOTP_VAULT_DONE'
Write-Output $vault
