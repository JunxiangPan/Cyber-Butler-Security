# Launch the long-running game-mode monitor as a detached child.
# The scheduled task can then end successfully (LastTaskResult=0) without
# keeping a long-running PowerShell process inside the task instance.
$ErrorActionPreference = 'Stop'
$runtime = Join-Path $env:USERPROFILE 'Desktop\大肥鱼专用文件夹'
$log = Join-Path $runtime 'start-game-mode.log'
$monitor = Join-Path $PSScriptRoot 'game-mode.ps1'

function Write-LaunchLog([string]$message) {
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message
    try {
        New-Item -ItemType Directory -Path $runtime -Force | Out-Null
        Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    } catch { }
}

function Get-MonitorProcesses {
    return @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like '*game-mode.ps1*' -and $_.CommandLine -notlike '*ListGames*' })
}

$running = Get-MonitorProcesses
if ($running.Count -gt 0) {
    Write-LaunchLog ('monitor already running: ' + (($running | ForEach-Object { $_.ProcessId }) -join ','))
    exit 0
}

if (-not (Test-Path -LiteralPath $monitor)) {
    Write-LaunchLog ('monitor script missing: ' + $monitor)
    exit 1
}

try {
    Start-Process -FilePath 'powershell.exe' `
        -ArgumentList @('-NoProfile','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',('"' + $monitor + '"')) `
        -WorkingDirectory $PSScriptRoot -WindowStyle Hidden | Out-Null
} catch {
    Write-LaunchLog ('launch failed: ' + $_.Exception.Message)
    exit 1
}

Start-Sleep -Seconds 5
$running = Get-MonitorProcesses
if ($running.Count -eq 0) {
    Write-LaunchLog 'monitor did not stay running'
    exit 1
}
Write-LaunchLog ('monitor launched: ' + (($running | ForEach-Object { $_.ProcessId }) -join ','))
exit 0
