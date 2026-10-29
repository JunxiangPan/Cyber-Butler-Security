#Requires -Version 5.1
<#
Create a desktop shortcut that launches the WPF updater through wscript.exe so
no console window appears. Run as the desktop user; administrator rights are
only needed later for the update itself.
#>
param(
    [string]$ShortcutName = '检查苏瑾言更新'
)

$ErrorActionPreference = 'Stop'
$vbs = Join-Path $PSScriptRoot 'update_gui.vbs'
if (-not (Test-Path -LiteralPath $vbs)) { throw "GUI launcher missing: $vbs" }
$desktop = [Environment]::GetFolderPath('Desktop')
$shortcutPath = Join-Path $desktop ($ShortcutName + '.lnk')
$shell = New-Object -ComObject WScript.Shell
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $env:SystemRoot 'System32\wscript.exe'
$shortcut.Arguments = '"' + $vbs + '"'
$shortcut.WorkingDirectory = $PSScriptRoot
$shortcut.IconLocation = (Join-Path $env:SystemRoot 'System32\shell32.dll') + ',167'
$shortcut.Description = '检查并安装苏瑾言更新'
$shortcut.Save()
Write-Output ('SHORTCUT=' + $shortcutPath)
