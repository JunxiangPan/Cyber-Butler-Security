# Install a per-user, one-minute watchdog for stale game-mode state.
# Run from an elevated PowerShell once per deployment.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'game-mode-watchdog.ps1'
$launcher = Join-Path $PSScriptRoot 'CyberButlerLauncher.exe'
if (-not (Test-Path -LiteralPath $script)) { throw "missing $script" }
if (-not (Test-Path -LiteralPath $launcher)) { throw "missing $launcher" }

# Use the signed native launcher with CREATE_NO_WINDOW; no wscript/cmd shim.
$action = New-ScheduledTaskAction -Execute $launcher `
    -Argument ('--exe "powershell.exe" --workdir "' + $PSScriptRoot + '" --args "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File \"' + $script + '\"" --hidden --wait')
$trigger = New-ScheduledTaskTrigger -Once -At ((Get-Date).AddMinutes(1)) `
    -RepetitionInterval (New-TimeSpan -Minutes 1) `
    -RepetitionDuration (New-TimeSpan -Days 3650)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5) -Hidden
Register-ScheduledTask -TaskName 'Game Mode Watchdog' -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null
Write-Output 'Installed Game Mode Watchdog (every 1 minute, native hidden launcher)'
