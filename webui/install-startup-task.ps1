# Register the Cyber-Butler Web UI + OTP mailer logon task.
# AtLogOn is intentional: the OTP mailer uses the interactive user's DPAPI
# secret, so a SYSTEM AtStartup task is not suitable.
$ErrorActionPreference = 'Stop'
$taskName = 'Cyber-Butler Web UI Services'
$script = Join-Path $PSScriptRoot 'start-services.ps1'
if (-not (Test-Path -LiteralPath $script)) {
    throw "missing $script"
}

$userId = "$env:COMPUTERNAME\$env:USERNAME"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$script`"" `
    -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId
$trigger.Delay = 'PT20S'
$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet `
    -MultipleInstances IgnoreNew `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 1) `
    -Hidden

Register-ScheduledTask -TaskName $taskName -Description 'Cyber-Butler Web UI (8765) and OTP mailer (8766) at user logon' `
    -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null

Write-Output "Installed task: $taskName"
Write-Output "Trigger: AtLogOn $userId (+20s)"
Write-Output "Action: powershell.exe -File `"$script`""
