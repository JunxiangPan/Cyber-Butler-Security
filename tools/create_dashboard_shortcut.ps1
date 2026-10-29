#Requires -Version 5.1
<#
Create a desktop shortcut for the Cyber-Butler dashboard.

The shortcut targets wscript.exe, which launches the VBS shim. No console
window is shown. Administrator rights are not required to open the dashboard.
#>
param(
    [string]$ShortcutName = 'Cyber-Butler 主控台',
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'
# Always target the INSTALL ROOT's launcher, even when this script is executed
# from the release tree. The shortcut, the running code, the VERSION file and
# the updater then all live in the same directory.
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$vbs = Join-Path $ProjectRoot 'tools\cyber_butler_dashboard.vbs'
if (-not (Test-Path -LiteralPath $vbs)) { throw "Dashboard launcher missing: $vbs" }
$desktop = [Environment]::GetFolderPath('Desktop')
$legacy = Join-Path $desktop '检查苏瑾言更新.lnk'
if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force }
$shortcutPath = Join-Path $desktop ($ShortcutName + '.lnk')
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$shortcut.Arguments = '"' + $vbs + '" "' + $ProjectRoot + '"'
$shortcut.WorkingDirectory = Join-Path $ProjectRoot 'tools'
$shortcut.IconLocation = (Join-Path $env:SystemRoot 'System32\shell32.dll') + ',21'
$shortcut.Description = 'Cyber-Butler 本地主控台（只读）'
$shortcut.Save()
Write-Output ('SHORTCUT=' + $shortcutPath)
