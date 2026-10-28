#Requires -RunAsAdministrator
$root = 'YOUR_PROJECT_PATH'
$log = Join-Path $root 'tools\install_daily_tasks.log'
Set-Content -LiteralPath $log -Value ('install daily tasks ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

$python = Join-Path $root 'AstrBot\.venv\Scripts\python.exe'
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 15)
$principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest

$jobs = @(
    @{ Name = 'AstrBot Daily Audit'; Script = 'daily_audit.py'; Time = '11:00PM' },
    @{ Name = 'AstrBot Morning Brief'; Script = 'daily_brief.py'; Time = '8:00AM' }
)
foreach ($job in $jobs) {
    $action = New-ScheduledTaskAction -Execute $python -Argument ('"{0}"' -f (Join-Path $root ('tools\' + $job.Script))) -WorkingDirectory $root
    $trigger = New-ScheduledTaskTrigger -Daily -At $job.Time
    Unregister-ScheduledTask -TaskName $job.Name -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $job.Name -Description 'AstrBot daily QA/audit job' -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    try {
        $t = Get-ScheduledTask -TaskName $job.Name
        $i = Get-ScheduledTaskInfo -TaskName $job.Name
        Log ($job.Name + ' state=' + $t.State + ' next=' + $i.NextRunTime)
    } catch { Log ($job.Name + ' verify failed: ' + $_.Exception.Message) }
}
Write-Output 'DAILY_TASKS_DONE'
Write-Output $log
