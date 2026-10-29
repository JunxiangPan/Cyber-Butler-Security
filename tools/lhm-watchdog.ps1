#Requires -Version 5.1
<#
LibreHardwareMonitor watchdog.

Checks the local sensor endpoint and, when it is down or unresponsive,
restarts LibreHardwareMonitor. The scheduled task runs it as SYSTEM every five
minutes, so it can start the monitoring process with the privileges the
sensors need.

Exit codes: 0 healthy/recovered, 1 could not recover.
#>
param(
    [string]$Url = 'http://127.0.0.1:18085/data.json',
    [string]$ExePath = '',
    [string]$TaskName = 'LibreHardwareMonitor',
    [int]$TimeoutSec = 5,
    [int]$RecoveryWaitSec = 30
)

$ErrorActionPreference = 'Stop'
$stateDir = Join-Path $env:ProgramData 'CyberButler'
New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
$logPath = Join-Path $stateDir 'lhm-watchdog.log'
$statePath = Join-Path $stateDir 'lhm-watchdog-state.json'

function Write-WatchdogLog([string]$Message) {
    try {
        if ((Test-Path -LiteralPath $logPath) -and ((Get-Item -LiteralPath $logPath).Length -gt 256KB)) {
            Move-Item -LiteralPath $logPath -Destination ($logPath + '.1') -Force -ErrorAction SilentlyContinue
        }
        Add-Content -LiteralPath $logPath -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message) -Encoding UTF8
    } catch { }
}

function Test-SensorEndpoint {
    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec $TimeoutSec
        return ([int]$response.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Save-WatchdogState([bool]$Healthy, [string]$Action) {
    try {
        [ordered]@{
            checked_at = (Get-Date).ToString('o')
            healthy    = $Healthy
            action     = $Action
            url        = $Url
        } | ConvertTo-Json -Compress | Set-Content -LiteralPath $statePath -Encoding UTF8
    } catch { }
}

if (Test-SensorEndpoint) {
    Save-WatchdogState $true 'none'
    exit 0
}

Write-WatchdogLog 'sensor endpoint is down; checking the process'
$process = Get-Process -Name 'LibreHardwareMonitor' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($process) {
    Start-Sleep -Seconds 3
    if (Test-SensorEndpoint) {
        Save-WatchdogState $true 'none'
        exit 0
    }
    Write-WatchdogLog ('process {0} is unresponsive; stopping it' -f $process.Id)
    try { Stop-Process -Id $process.Id -Force -ErrorAction Stop } catch {
        Write-WatchdogLog ('stop failed: ' + $_.Exception.Message)
    }
    Start-Sleep -Seconds 2
}

if (-not $ExePath) {
    $ExePath = Join-Path $PSScriptRoot 'LibreHardwareMonitor\LibreHardwareMonitor.exe'
}

$started = $false
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-WatchdogLog ('starting scheduled task ' + $TaskName)
    try {
        Start-ScheduledTask -TaskName $TaskName -ErrorAction Stop
        $started = $true
    } catch {
        Write-WatchdogLog ('scheduled task start failed: ' + $_.Exception.Message)
    }
}
if (-not $started -and (Test-Path -LiteralPath $ExePath)) {
    Write-WatchdogLog ('starting executable ' + $ExePath)
    try {
        Start-Process -FilePath $ExePath -WorkingDirectory (Split-Path -Parent $ExePath) -WindowStyle Hidden
        $started = $true
    } catch {
        Write-WatchdogLog ('executable start failed: ' + $_.Exception.Message)
    }
}

if (-not $started) {
    Write-WatchdogLog 'could not start LibreHardwareMonitor (task and executable both failed)'
    Save-WatchdogState $false 'start-failed'
    exit 1
}

for ($waited = 0; $waited -lt $RecoveryWaitSec; $waited += 2) {
    Start-Sleep -Seconds 2
    if (Test-SensorEndpoint) {
        Write-WatchdogLog 'sensor endpoint recovered'
        Save-WatchdogState $true 'started'
        exit 0
    }
}

Write-WatchdogLog ('recovery timed out after {0}s' -f $RecoveryWaitSec)
Save-WatchdogState $false 'timeout'
exit 1
