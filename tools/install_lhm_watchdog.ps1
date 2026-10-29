#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
Install the LibreHardwareMonitor watchdog.

Creates a SYSTEM scheduled task that runs tools\lhm-watchdog.vbs every five
minutes from boot, with no console window. The script copies the watchdog files
into the install root when this installer is run from the release tree, then
performs a stop/start recovery self-test.

Usage (elevated):
    powershell -ExecutionPolicy Bypass -File tools\install_lhm_watchdog.ps1 -ProjectRoot D:\qq苏瑾言大肥鱼
#>
param(
    [string]$ProjectRoot = '',
    [switch]$SkipSelfTest
)

$ErrorActionPreference = 'Stop'
$taskName = 'LibreHardwareMonitor Watchdog'

if (-not $ProjectRoot) {
    $candidate = Split-Path -Parent $PSScriptRoot
    if ((Split-Path -Leaf $candidate) -eq 'public-release') { $candidate = Split-Path -Parent $candidate }
    $ProjectRoot = $candidate
}
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$tools = Join-Path $root 'tools'
$vbs = Join-Path $tools 'lhm-watchdog.vbs'
$ps1 = Join-Path $tools 'lhm-watchdog.ps1'
$logDir = Join-Path $env:ProgramData 'CyberButler'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$installLog = Join-Path $logDir 'lhm-watchdog-install.log'
$statusPath = Join-Path $root 'tmp-plugins\lhm-watchdog-install.json'

function Write-InstallLog([string]$Message) {
    try {
        Add-Content -LiteralPath $installLog -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message) -Encoding UTF8
    } catch { }
}

function Test-SensorEndpoint {
    try {
        $response = Invoke-WebRequest -Uri 'http://127.0.0.1:18085/data.json' -UseBasicParsing -TimeoutSec 5
        return ([int]$response.StatusCode -eq 200)
    } catch {
        return $false
    }
}

$result = [ordered]@{
    ok               = $false
    installed_at     = (Get-Date).ToString('o')
    task_name        = $taskName
    project_root     = $root
    copied           = @()
    trigger          = ''
    principal        = ''
    self_test        = $null
    last_task_result = $null
    error            = ''
}

try {
    # 1. Make sure the watchdog files live in the install root.
    $sourceTools = $PSScriptRoot
    $copiedFiles = New-Object System.Collections.ArrayList
    foreach ($name in @('lhm-watchdog.ps1', 'lhm-watchdog.vbs', 'install_lhm_watchdog.ps1')) {
        $source = Join-Path $sourceTools $name
        $target = Join-Path $tools $name
        if (-not (Test-Path -LiteralPath $source)) { throw "installer source missing: $source" }
        if ([IO.Path]::GetFullPath($source) -ne [IO.Path]::GetFullPath($target)) {
            Copy-Item -LiteralPath $source -Destination $target -Force
            [void]$copiedFiles.Add($name)
        }
    }
    $result.copied = @($copiedFiles)
    if (-not (Test-Path -LiteralPath $vbs)) { throw "watchdog launcher missing: $vbs" }
    Write-InstallLog ('watchdog files ready in ' + $tools)

    # 2. Register the SYSTEM task: every five minutes forever, plus one run at boot.
    # schtasks is used for the minute schedule because Register-ScheduledTask
    # rejects TimeSpan.MaxValue as a repetition duration on Windows PowerShell 5.1.
    $taskRun = 'wscript.exe //B "' + $vbs + '"'
    & schtasks.exe /Create /TN $taskName /TR $taskRun /SC MINUTE /MO 5 /RU SYSTEM /RL HIGHEST /F | Out-Null
    if ($LASTEXITCODE -ne 0) { throw ('schtasks /Create failed: ' + $LASTEXITCODE) }
    $created = Get-ScheduledTask -TaskName $taskName
    $startup = New-ScheduledTaskTrigger -AtStartup
    Set-ScheduledTask -TaskName $taskName -Trigger (@($created.Triggers) + $startup) | Out-Null
    Write-InstallLog 'task registered (5 minute schedule + AtStartup trigger)'

    $registered = Get-ScheduledTask -TaskName $taskName
    $result.trigger = 'AtStartup + every 5 minutes'
    $result.principal = [string]$registered.Principal.UserId + ' / ' + [string]$registered.Principal.RunLevel

    # 3. Start it once and check the last result.
    Start-ScheduledTask -TaskName $taskName
    Start-Sleep -Seconds 6
    $info = Get-ScheduledTaskInfo -TaskName $taskName
    $result.last_task_result = $info.LastTaskResult
    Write-InstallLog ('task started; LastTaskResult=' + $info.LastTaskResult)

    # 4. Recovery self-test: stop LHM, let the watchdog bring it back.
    if (-not $SkipSelfTest) {
        $before = Test-SensorEndpoint
        Get-Process -Name 'LibreHardwareMonitor' -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
        $down = -not (Test-SensorEndpoint)
        Write-InstallLog ('self-test: endpoint before=' + $before + ' after stop=' + (-not $down))
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ps1
        $watchdogExit = $LASTEXITCODE
        Start-Sleep -Seconds 3
        $recovered = Test-SensorEndpoint
        $running = [bool](Get-Process -Name 'LibreHardwareMonitor' -ErrorAction SilentlyContinue)
        $result.self_test = [ordered]@{
            before         = $before
            stopped        = $down
            watchdog_exit  = $watchdogExit
            recovered      = $recovered
            process_running = $running
        }
        Write-InstallLog ('self-test: exit=' + $watchdogExit + ' recovered=' + $recovered + ' running=' + $running)
    }

    $result.ok = (Test-SensorEndpoint)
    Write-InstallLog ('install finished ok=' + $result.ok)
} catch {
    $result.error = $_.Exception.ToString()
    Write-InstallLog ('install failed: ' + $_.Exception.Message)
}

try {
    $parent = Split-Path -Parent $statusPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $statusPath -Encoding UTF8
} catch { }

if ($result.ok) { exit 0 }
exit 1
