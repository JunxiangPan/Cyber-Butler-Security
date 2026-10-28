#Requires -RunAsAdministrator
$root = 'YOUR_PROJECT_PATH'
$log = Join-Path $root 'tools\install_broker_task.log'
Set-Content -LiteralPath $log -Value ('install broker ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

$action = New-ScheduledTaskAction -Execute (Join-Path $root 'AstrBot\.venv\Scripts\python.exe') `
    -Argument ('"{0}"' -f (Join-Path $root 'tools\broker.py')) `
    -WorkingDirectory (Join-Path $root 'tools')
$trigger = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)
Unregister-ScheduledTask -TaskName 'AstrBot TOTP Broker' -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName 'AstrBot TOTP Broker' -Description 'SYSTEM broker for TOTP-gated delete/overwrite' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
Start-ScheduledTask -TaskName 'AstrBot TOTP Broker'
Start-Sleep -Seconds 5
try { Get-ScheduledTaskInfo -TaskName 'AstrBot TOTP Broker' | Format-List | Out-String | Add-Content -LiteralPath $log } catch { }
Get-Process | Where-Object { $_.ProcessName -eq 'python' } | Select-Object Id,ProcessName | Format-Table -AutoSize | Out-String | Add-Content -LiteralPath $log
Write-Output 'BROKER_TASK_DONE'
Write-Output $log
