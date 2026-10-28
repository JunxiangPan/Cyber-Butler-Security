#Requires -RunAsAdministrator
$ErrorActionPreference = 'Stop'
$shared = 'YOUR_USER_PATH\Desktop\大肥鱼专用文件夹'
$log = 'YOUR_PROJECT_PATH\tools\protect_shared_acl.log'
$backup = 'YOUR_PROJECT_PATH\tools\shared-acl-before-totp.clixml'
Set-Content -LiteralPath $log -Value ('ACL protect ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

try {
    Get-Acl -LiteralPath $shared | Export-Clixml -LiteralPath $backup -Force
    Log ('backup written: ' + $backup)
} catch { Log ('backup failed: ' + $_.Exception.Message) }

# Deleting children is denied at the folder level. Creating new files is still
# allowed; this blocks os.remove / Remove-Item / rmdir from YOUR_SERVICE_USER.
$acl = Get-Acl -LiteralPath $shared
$deleteRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    'YOUR_SERVICE_USER', 'Delete,DeleteSubdirectoriesAndFiles',
    'ContainerInherit,ObjectInherit', 'None', 'Deny')
$acl.AddAccessRule($deleteRule)
Set-Acl -LiteralPath $shared -AclObject $acl
Log 'folder delete deny applied for YOUR_SERVICE_USER'

# Existing files become read-only for YOUR_SERVICE_USER (no overwrite), but new
# files can still be created. The SYSTEM broker is unaffected.
$count = 0
Get-ChildItem -LiteralPath $shared -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $fileAcl = Get-Acl -LiteralPath $_.FullName
        $writeRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            'YOUR_SERVICE_USER', 'Write,Delete', 'None', 'None', 'Deny')
        $fileAcl.AddAccessRule($writeRule)
        Set-Acl -LiteralPath $_.FullName -AclObject $fileAcl
        $count++
    } catch { Log ('file ACL failed: ' + $_.FullName + ' ' + $_.Exception.Message) }
}
Log ('existing files protected: ' + $count)
Write-Output 'ACL_PROTECT_DONE'
Write-Output $log
