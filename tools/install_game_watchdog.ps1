# Install a per-user, one-minute watchdog for stale game-mode state.
# Run from an elevated PowerShell once per deployment.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'game-mode-watchdog.ps1'
$launcher = Join-Path $PSScriptRoot 'game-mode-watchdog.vbs'
if (-not (Test-Path -LiteralPath $script)) { throw "missing $script" }
if (-not (Test-Path -LiteralPath $launcher)) { throw "missing $launcher" }

# Use wscript.exe (GUI host) plus a VBS hidden launcher. Calling powershell.exe
# directly from Task Scheduler can flash a console before -WindowStyle Hidden
# takes effect.
$action = New-ScheduledTaskAction -Execute 'wscript.exe' `
    -Argument "//B //NoLogo `"$launcher`""
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -Hidden
Register-ScheduledTask -TaskName 'Game Mode Watchdog' -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
Write-Output 'Installed Game Mode Watchdog (every 1 minute, hidden wscript launcher)'
