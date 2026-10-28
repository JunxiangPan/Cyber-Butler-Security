#Requires -RunAsAdministrator
$root = 'YOUR_PROJECT_PATH'
$log = Join-Path $root 'tools\install_startup_tasks.log'
Set-Content -LiteralPath $log -Value ('install startup tasks ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -Encoding UTF8
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

$principal = New-ScheduledTaskPrincipal -UserId 'YOUR_HOST\YOUR_USER_NAME' -LogonType Interactive -RunLevel Limited
$trigger = New-ScheduledTaskTrigger -AtLogOn -User 'YOUR_HOST\YOUR_USER_NAME'
$trigger.Delay = 'PT15S'
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)

function Install-Task([string]$name, [string]$exe, [string]$args, [string]$workdir, [string]$desc) {
    $action = New-ScheduledTaskAction -Execute $exe -Argument $args -WorkingDirectory $workdir
    Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $name -Description $desc -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Log ("installed " + $name)
}

Install-Task 'SnowLuma Startup' 'cmd.exe' ('/c "{0}"' -f (Join-Path $root 'start-bot.bat')) $root 'SnowLuma + guardian as YOUR_USER_NAME at logon'
Install-Task 'Ollama Startup' 'powershell.exe' ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'tools\start-ollama.ps1')) (Join-Path $root 'tools') 'Ollama + local model at logon'
Install-Task 'Game Mode Startup' 'powershell.exe' ('-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}"' -f (Join-Path $root 'tools\game-mode.ps1')) (Join-Path $root 'tools') 'Game mode monitor as YOUR_USER_NAME at logon'

# Remove the old Startup shortcuts so they cannot double-start SnowLuma/Ollama.
$startup = 'YOUR_USER_PATH\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup'
$backup = Join-Path $root 'tools\startup-backup'
New-Item -ItemType Directory -Force -Path $backup | Out-Null
foreach ($name in @('QQBot.lnk','Ollama.lnk','AstrBot Game Mode.lnk')) {
    $src = Join-Path $startup $name
    if (Test-Path -LiteralPath $src) {
        Move-Item -LiteralPath $src -Destination (Join-Path $backup $name) -Force
        Log ("moved startup shortcut: " + $name)
    }
}
Write-Output 'STARTUP_TASKS_DONE'
Write-Output $log
