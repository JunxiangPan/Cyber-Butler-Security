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
$vbs = Join-Path $PSScriptRoot 'cyber_butler_dashboard.vbs'
if (-not (Test-Path -LiteralPath $vbs)) { throw "Dashboard launcher missing: $vbs" }
$desktop = [Environment]::GetFolderPath('Desktop')
$legacy = Join-Path $desktop '检查苏瑾言更新.lnk'
if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force }
$shortcutPath = Join-Path $desktop ($ShortcutName + '.lnk')
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$shortcut.Arguments = '"' + $vbs + '" "' + (Resolve-Path -LiteralPath $ProjectRoot).Path + '"'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = (Join-Path $env:SystemRoot 'System32\shell32.dll') + ',21'
$shortcut.Description = 'Cyber-Butler 本地主控台（只读）'
$shortcut.Save()
Write-Output ('SHORTCUT=' + $shortcutPath)
