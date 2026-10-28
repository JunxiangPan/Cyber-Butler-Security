$ErrorActionPreference = 'Stop'
$exe = 'YOUR_PROJECT_PATH\tools\LibreHardwareMonitor\LibreHardwareMonitor.exe'
$workdir = 'YOUR_PROJECT_PATH\tools\LibreHardwareMonitor'
$marker = 'YOUR_PROJECT_PATH\tools\lhm_task_installed.txt'

Get-Process LibreHardwareMonitor -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

$action = New-ScheduledTaskAction -Execute $exe -WorkingDirectory $workdir
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero)
Register-ScheduledTask -TaskName 'LibreHardwareMonitor' -Action $action -Trigger $trigger -Settings $settings -RunLevel Highest -Force | Out-Null
Start-ScheduledTask -TaskName 'LibreHardwareMonitor'

$deadline = (Get-Date).AddSeconds(20)
$ok = $false
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Seconds 2
    try {
        $r = Invoke-WebRequest -Uri 'http://127.0.0.1:18085/data.json' -UseBasicParsing -TimeoutSec 3
        if ($r.StatusCode -eq 200) { $ok = $true; break }
    } catch {}
}
"ok=$ok time=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Set-Content -Path $marker -Encoding UTF8
if (-not $ok) { exit 1 }
