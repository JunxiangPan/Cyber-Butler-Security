#Requires -RunAsAdministrator
$root = 'YOUR_PROJECT_PATH'
$log = Join-Path $root 'tools\install_weekly_task.log'
Set-Content -LiteralPath $log -Value ('install weekly ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

Unregister-ScheduledTask -TaskName 'AstrBot Nightly Restart' -Confirm:$false -ErrorAction SilentlyContinue
Log 'removed daily AstrBot Nightly Restart'

$action = New-ScheduledTaskAction -Execute 'powershell.exe' `
    -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'tools\weekly-selfheal.ps1')) `
    -WorkingDirectory (Join-Path $root 'tools')
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At '4:00AM'
$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 60) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 5)
Unregister-ScheduledTask -TaskName 'AstrBot Weekly Self-Heal' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'AstrBot Weekly Self-Heal' -Description 'Sunday 04:00 process/VRAM/temp cleanup and retry restart' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
try {
    $t = Get-ScheduledTask -TaskName 'AstrBot Weekly Self-Heal'
    $i = Get-ScheduledTaskInfo -TaskName 'AstrBot Weekly Self-Heal'
    Log ('installed state=' + $t.State + ' next=' + $i.NextRunTime)
} catch { Log ('verify failed: ' + $_.Exception.Message) }
Write-Output 'WEEKLY_TASK_DONE'
Write-Output $log
