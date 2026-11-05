#Requires -RunAsAdministrator
<#
Elevated action helper for the Cyber-Butler dashboard.

The dashboard runs unprivileged and launches this script only after a UAC
prompt. Supported actions:
  RestartAgentRuntime
  ReleaseVram
  Fuse
  ClearConversation
  SaveApiKey
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('RestartAgentRuntime', 'ReleaseVram', 'Fuse', 'ClearConversation', 'SaveApiKey', 'SetBrokerChannel', 'RestartBroker')]
    [string]$Action,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$ConfirmationText = '',
    [string]$StatusFile = '',
    [string]$Umo = '',
    [string]$SecretFile = '',
    [string]$Channel = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$log = Join-Path $root 'AgentRuntime\data\dashboard-actions.log'

function Write-ActionStatus([string]$stage, [int]$progress, [string]$message) {
    if (-not $StatusFile) { return }
    try {
        $parent = Split-Path -Parent $StatusFile
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $json = [ordered]@{
            stage = $stage
            progress = $progress
            message = $message
            updated_at = (Get-Date).ToString('o')
        } | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($StatusFile, $json, (New-Object Text.UTF8Encoding($false)))
    } catch { Write-Verbose 'optional operation failed' }
}

function Write-ActionLog([string]$message) {
    try {
        $parent = Split-Path -Parent $log
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Add-Content -LiteralPath $log -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message) -Encoding UTF8
    } catch { Write-Verbose 'optional operation failed' }
}

function Wait-Port([int]$Port, [int]$Seconds = 60) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $client = New-Object Net.Sockets.TcpClient
        try {
            $task = $client.ConnectAsync('127.0.0.1', $Port)
            if ($task.Wait(700) -and $client.Connected) { return $true }
        } catch { Write-Verbose 'optional operation failed' } finally {
            $client.Dispose()
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

<#
.SYNOPSIS
    Stop-AgentRuntimeProcesses performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Stop-AgentRuntimeProcesses([switch]$IncludeBroker) {
    $killed = @()
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and
            $_.CommandLine -match '(?i)main\.py' -and
            $_.CommandLine -notmatch '(?i)broker\.py'
        })
    foreach ($proc in $procs) {
        try {
            Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop
            $killed += [int]$proc.ProcessId
        } catch { Write-Verbose 'optional operation failed' }
    }
    if ($IncludeBroker) {
        $brokers = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='pythonw.exe'" -ErrorAction SilentlyContinue |
            Where-Object { $_.CommandLine -and $_.CommandLine -match '(?i)broker\.py' })
        foreach ($proc in $brokers) {
            try { Stop-Process -Id $proc.ProcessId -Force -ErrorAction Stop; $killed += [int]$proc.ProcessId } catch { Write-Verbose 'optional operation failed' }
        }
    }
    # WMI command lines can be blank for a service-owned process.  Never leave
    # an old listener on 6185 behind; kill only the owner of AgentRuntime's port.
    $listeners = @(Get-NetTCPConnection -LocalPort 6185 -State Listen -ErrorAction SilentlyContinue)
    foreach ($listener in $listeners) {
        if ([int]$listener.OwningProcess -gt 0) {
            try { Stop-Process -Id ([int]$listener.OwningProcess) -Force -ErrorAction Stop; $killed += [int]$listener.OwningProcess } catch { Write-Verbose 'optional operation failed' }
        }
    }
    Write-ActionLog ('stopped AgentRuntime pids=' + (($killed | Select-Object -Unique) -join ','))
}

function Wait-PortClosed([int]$Port, [int]$Seconds = 20) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $listening = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
        if ($listening.Count -eq 0) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

function Wait-TaskNotRunning([string]$Name, [int]$Seconds = 15) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        if (-not $task -or $task.State -ne 'Running') { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $root 'AgentRuntime'))) {
        throw "ProjectRoot does not contain AgentRuntime: $root"
    }
    Write-ActionLog ("action=$Action")

    switch ($Action) {
        'RestartAgentRuntime' {
            Write-ActionStatus 'stopping' 20 '正在停止 AgentRuntime...'
            Write-ActionLog 'RestartAgentRuntime: stopping AgentRuntime service task'
            Stop-ScheduledTask -TaskName 'AgentRuntime Service' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            if (-not (Wait-TaskNotRunning 'AgentRuntime Service' 15)) {
                Write-ActionLog 'AgentRuntime task still running; issuing schtasks /End'
                $end = Start-Process -FilePath 'schtasks.exe' -ArgumentList '/End /TN "AgentRuntime Service"' -WindowStyle Hidden -Wait -PassThru
                Write-ActionLog ('schtasks /End AgentRuntime Service exit=' + $end.ExitCode)
                Start-Sleep -Seconds 2
            }
            Stop-AgentRuntimeProcesses
            if (-not (Wait-PortClosed 6185 20)) {
                throw 'AgentRuntime port 6185 is still listening after forced stop'
            }
            Write-ActionLog 'AgentRuntime stopped; port 6185 is free; broker path was not targeted'
            Write-ActionStatus 'starting' 55 '正在启动 AgentRuntime...'
            Start-ScheduledTask -TaskName 'AgentRuntime Service' -ErrorAction SilentlyContinue
            if (-not (Wait-Port 6185 60)) { throw 'AgentRuntime did not become healthy on 6185' }
            Write-ActionStatus 'done' 100 'AgentRuntime 已重启'
            Write-ActionLog 'AgentRuntime restart OK; broker was not stopped'
        }
        'ReleaseVram' {
            Write-ActionStatus 'releasing' 30 '正在释放本地模型显存...'
            $model = 'sujinyan-chat-24k:latest'
            try {
                $body = @{ model = $model; prompt = ''; stream = $false; keep_alive = 0 } | ConvertTo-Json -Compress
                Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:11434/api/generate' -ContentType 'application/json' -Body $body -TimeoutSec 20 | Out-Null
                Write-ActionStatus 'done' 100 '已请求释放模型显存'
                Write-ActionLog 'VRAM unload requested'
            } catch {
                throw ('Ollama unload failed: ' + $_.Exception.Message)
            }
        }
        'Fuse' {
            if ($ConfirmationText -cne 'FUSE') { throw 'FUSE confirmation rejected' }
            Write-ActionStatus 'fuse' 30 '正在执行紧急熔断...'
            Stop-ScheduledTask -TaskName 'AgentRuntime Service' -ErrorAction SilentlyContinue
            Stop-ScheduledTask -TaskName 'AgentRuntime TOTP Broker' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Stop-AgentRuntimeProcesses -IncludeBroker
            Write-ActionStatus 'done' 100 '紧急熔断完成：AgentRuntime 与 Broker 已停止'
            Write-ActionLog 'FUSE executed; AgentRuntime and Broker stopped'
        }
        'ClearConversation' {
            if (-not $Umo) { throw 'Umo is required' }
            $db = Join-Path $root 'AgentRuntime\data\data_v4.db'
            if (-not (Test-Path -LiteralPath $db)) { throw "database missing: $db" }
            Write-ActionStatus 'stopping' 20 '正在停止 AgentRuntime 以清理对话...'
            Stop-ScheduledTask -TaskName 'AgentRuntime Service' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Stop-AgentRuntimeProcesses
            $backup = $db + '.bak-dashboard-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
            Copy-Item -LiteralPath $db -Destination $backup -Force
            $python = Join-Path $root 'AgentRuntime\.venv\Scripts\python.exe'
            $code = @'
import sqlite3, sys
path, user = sys.argv[1], sys.argv[2]
c = sqlite3.connect(path)
try:
    c.execute("delete from conversations where user_id=?", (user,))
    c.commit()
finally:
    c.close()
'@
            $codePath = Join-Path $env:TEMP ('clear-user-' + [guid]::NewGuid().ToString('N') + '.py')
            [IO.File]::WriteAllText($codePath, $code, (New-Object Text.UTF8Encoding($false)))
            try {
                & $python $codePath $db $Umo
                if ($LASTEXITCODE -ne 0) { throw 'conversation delete failed' }
            } finally {
                Remove-Item -LiteralPath $codePath -Force -ErrorAction SilentlyContinue
            }
            Write-ActionStatus 'starting' 80 '正在重启 AgentRuntime...'
            Start-ScheduledTask -TaskName 'AgentRuntime Service' -ErrorAction SilentlyContinue
            if (-not (Wait-Port 6185 60)) { throw 'AgentRuntime did not recover after conversation clear' }
            Write-ActionStatus 'done' 100 '当前对话已清空'
            Write-ActionLog ('conversation cleared for ' + $Umo)
        }
        'SaveApiKey' {
            if (-not $SecretFile) { throw 'SecretFile is required' }
            Write-ActionStatus 'saving' 40 '正在加密保存 API Key...'
            $secretHelper = Join-Path $PSScriptRoot 'dashboard_secret.ps1'
            & $secretHelper -InputFile $SecretFile -OutputFile (Join-Path $root 'tools\deepseek.key.dpapi')
            if ($LASTEXITCODE -ne 0) { throw 'API key save failed' }
            Write-ActionStatus 'done' 100 'API Key 已保存；重启 AgentRuntime 后生效'
            Write-ActionLog 'API key saved'
        }
        'SetBrokerChannel' {
            if ($Channel -notin @('qq', 'email')) { throw 'Channel must be qq or email' }
            $configPath = Join-Path $root 'tools\broker_config.json'
            $payload = [ordered]@{ approval_channel = $Channel } | ConvertTo-Json -Compress
            [IO.File]::WriteAllText($configPath, $payload, (New-Object Text.UTF8Encoding($false)))
            Write-ActionStatus 'done' 100 ('审批通道已保存：' + $Channel)
            Write-ActionLog ('broker approval channel saved: ' + $Channel)
        }
        'RestartBroker' {
            Write-ActionStatus 'restarting' 30 '正在重启 Broker...'
            $restart = Join-Path $PSScriptRoot 'restart_broker.ps1'
            if (-not (Test-Path -LiteralPath $restart)) { throw 'restart_broker.ps1 is missing' }
            & $restart
            if (-not (Wait-Port 18090 30)) { throw 'Broker did not become healthy on 18090' }
            Write-ActionStatus 'done' 100 'Broker 已重启'
            Write-ActionLog 'Broker restarted successfully'
        }
    }
    exit 0
} catch {
    Write-ActionStatus 'failed' 100 ('操作失败：' + $_.Exception.Message)
    Write-ActionLog ('FAILED action=' + $Action + ' error=' + $_.Exception.Message)
    exit 1
}
