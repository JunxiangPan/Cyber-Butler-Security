#Requires -RunAsAdministrator
$root = 'YOUR_PROJECT_PATH'
$log = Join-Path $root 'tools\install_snow_task2.log'
Set-Content -LiteralPath $log -Value ('install snow task2 ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'tools\start-snowluma.ps1')) -WorkingDirectory (Join-Path $root 'tools')
$trigger = New-ScheduledTaskTrigger -AtLogOn -User 'YOUR_HOST\YOUR_USER_NAME'
$trigger.Delay = 'PT15S'
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
$principal = New-ScheduledTaskPrincipal -UserId 'YOUR_HOST\YOUR_USER_NAME' -LogonType Interactive -RunLevel Limited

Unregister-ScheduledTask -TaskName 'SnowLuma Startup' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'SnowLuma Startup' -Description 'SnowLuma + guardian as YOUR_USER_NAME at logon' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
try {
    $t = Get-ScheduledTask -TaskName 'SnowLuma Startup'
    $i = Get-ScheduledTaskInfo -TaskName 'SnowLuma Startup'
    Log ('task state=' + $t.State + ' action=' + $t.Actions.Arguments + ' last=' + $i.LastTaskResult)
} catch { Log ('verify failed: ' + $_.Exception.Message) }
Write-Output 'SNOW_TASK2_DONE'
Write-Output $log
