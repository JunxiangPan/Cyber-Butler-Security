# Install the 2-minute boot self-check as SYSTEM with startup + logon triggers.
$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'boot-selfcheck.ps1'
if (-not (Test-Path -LiteralPath $script)) { throw "missing $script" }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`""
$startup = New-ScheduledTaskTrigger -AtStartup
$startup.Delay = 'PT2M'
$logon = New-ScheduledTaskTrigger -AtLogOn
$logon.Delay = 'PT2M'
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10) -Hidden
Register-ScheduledTask -TaskName 'Boot SelfCheck' -Action $action -Trigger @($startup, $logon) `
    -Principal $principal -Settings $settings -Force | Out-Null
Write-Output 'Installed Boot SelfCheck (startup + logon, +2 minutes, current user)'
