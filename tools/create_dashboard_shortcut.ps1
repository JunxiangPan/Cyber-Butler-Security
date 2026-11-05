#Requires -Version 5.1
<#
Create a desktop shortcut for the Cyber-Butler dashboard.

The shortcut targets the signed native launcher, which starts the hidden
PowerShell dashboard without wscript.exe or a console window. Administrator
rights are not required to open the dashboard.
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
$launcher = Join-Path $ProjectRoot 'tools\CyberButlerLauncher.exe'
$dashboard = Join-Path $ProjectRoot 'tools\start-dashboard.ps1'
if (-not (Test-Path -LiteralPath $launcher)) { throw "Native launcher missing: $launcher" }
if (-not (Test-Path -LiteralPath $dashboard)) { throw "Dashboard script missing: $dashboard" }
$desktop = [Environment]::GetFolderPath('Desktop')
$legacy = Join-Path $desktop '检查local agent更新.lnk'
if (Test-Path -LiteralPath $legacy) { Remove-Item -LiteralPath $legacy -Force }
$shortcutPath = Join-Path $desktop ($ShortcutName + '.lnk')
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = $launcher
$shortcut.Arguments = '--exe "powershell.exe" --workdir "' + (Split-Path -Parent $dashboard) + '" --args "-NoProfile -STA -ExecutionPolicy Bypass -WindowStyle Hidden -File \"' + $dashboard + '\" -ProjectRoot \"' + $ProjectRoot + '\"" --hidden'
$shortcut.WorkingDirectory = Join-Path $ProjectRoot 'tools'
$shortcut.IconLocation = (Join-Path $env:SystemRoot 'System32\shell32.dll') + ',21'
$shortcut.Description = 'Cyber-Butler 本地主控台（只读）'
$shortcut.Save()
Write-Output ('SHORTCUT=' + $shortcutPath)
