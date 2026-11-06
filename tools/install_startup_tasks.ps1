#Requires -RunAsAdministrator
$root = 'YOUR_PROJECT_PATH'
$log = Join-Path $root 'tools\install_startup_tasks.log'
Set-Content -LiteralPath $log -Value ('install startup tasks ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

$launcher = Join-Path $root 'tools\CyberButlerLauncher.exe'

$principal = New-ScheduledTaskPrincipal -UserId 'YOUR_HOST\test-user' -LogonType Interactive -RunLevel Limited
$trigger = New-ScheduledTaskTrigger -AtLogOn -User 'YOUR_HOST\test-user'
$trigger.Delay = 'PT15S'
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

function Install-Task([string]$name, [string]$exe, [string]$taskArgs, [string]$workdir, [string]$desc) {
    $action = New-ScheduledTaskAction -Execute $exe -Argument $taskArgs -WorkingDirectory $workdir
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $name -Description $desc -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Log ("installed " + $name)
}

Install-Task 'AuxRuntime Startup' $launcher ('--exe "powershell.exe" --workdir "{0}" --args "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"{1}\"" --hidden --wait' -f (Join-Path $root 'tools'), (Join-Path $root 'tools\start-auxruntime.ps1')) (Join-Path $root 'tools') 'AuxRuntime + guardian as test-user at logon'
Install-Task 'Game Mode Startup' $launcher ('--exe "powershell.exe" --workdir "{0}" --args "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"{1}\"" --hidden --wait' -f (Join-Path $root 'tools'), (Join-Path $root 'tools\start-game-mode.ps1')) (Join-Path $root 'tools') 'Game mode monitor launcher as test-user at logon'

# Remove the old Startup shortcuts so they cannot double-start AuxRuntime.
$startup = 'YOUR_USER_PATH\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
$backup = Join-Path $root 'tools\startup-backup'
New-Item -ItemType Directory -Force -Path $backup | Out-Null
foreach ($name in @('QQBot.lnk','Ollama.lnk','AgentRuntime Game Mode.lnk')) {
    $src = Join-Path $startup $name
    if (Test-Path -LiteralPath $src) {
        Move-Item -LiteralPath $src -Destination (Join-Path $backup $name) -Force
        Log ("moved startup shortcut: " + $name)
    }
}
Write-Output 'STARTUP_TASKS_DONE'
Write-Output $log
