#Requires -Version 5.1
<#
Deprecated shortcut compatibility script.

The standalone update window has been folded into the Cyber-Butler dashboard.
This script never creates an update shortcut; it removes the old desktop entry.
#>
$ErrorActionPreference = 'Stop'
$desktop = [Environment]::GetFolderPath('Desktop')
$old = Join-Path $desktop '检查苏瑾言更新.lnk'
if (Test-Path -LiteralPath $old) {
    Remove-Item -LiteralPath $old -Force
    Write-Output ('REMOVED=' + $old)
} else {
    Write-Output 'NO_UPDATE_SHORTCUT'
}
