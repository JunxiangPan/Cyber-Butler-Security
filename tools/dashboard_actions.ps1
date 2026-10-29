#Requires -RunAsAdministrator
<#
Elevated action helper for the Cyber-Butler dashboard.

The dashboard runs unprivileged and launches this script only after a UAC
prompt. Supported actions:
  RestartAstrBot
  ReleaseVram
  Fuse
  ClearConversation
  SaveApiKey
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('RestartAstrBot', 'ReleaseVram', 'Fuse', 'ClearConversation', 'SaveApiKey')]
    [string]$Action,
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$ConfirmationText = '',
    [string]$StatusFile = '',
    [string]$Umo = '',
    [string]$SecretFile = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path -LiteralPath $ProjectRoot).Path
$log = Join-Path $root 'AstrBot\data\dashboard-actions.log'

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
    } catch { }
}

function Write-ActionLog([string]$message) {
    try {
        $parent = Split-Path -Parent $log
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Add-Content -LiteralPath $log -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message) -Encoding UTF8
    } catch { }
}

function Wait-Port([int]$Port, [int]$Seconds = 60) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $client = New-Object Net.Sockets.TcpClient
        try {
            $task = $client.ConnectAsync('127.0.0.1', $Port)
            if ($task.Wait(700) -and $client.Connected) { return $true }
        } catch {
        } finally {
            $client.Dispose()
        }
        Start-Sleep -Seconds 2
    }
    return $false
}

function Stop-AstrBotProcesses {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and (
                $_.CommandLine -match 'AstrBot.*main\.py' -or
                $_.CommandLine -match 'tools[\\/]broker\.py'
            )
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

try {
    if (-not (Test-Path -LiteralPath (Join-Path $root 'AstrBot'))) {
        throw "ProjectRoot does not contain AstrBot: $root"
    }
    Write-ActionLog ("action=$Action")

    switch ($Action) {
        'RestartAstrBot' {
            Write-ActionStatus 'stopping' 20 '正在停止 AstrBot...'
            Stop-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Stop-AstrBotProcesses
            Write-ActionStatus 'starting' 55 '正在启动 AstrBot...'
            Start-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
            if (-not (Wait-Port 6185 60)) { throw 'AstrBot did not become healthy on 6185' }
            Write-ActionStatus 'done' 100 'AstrBot 已重启'
            Write-ActionLog 'AstrBot restart OK'
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
            Stop-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
            Stop-ScheduledTask -TaskName 'AstrBot TOTP Broker' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 3
            Stop-AstrBotProcesses
            Write-ActionStatus 'done' 100 '紧急熔断完成：AstrBot 与 Broker 已停止'
            Write-ActionLog 'FUSE executed; AstrBot and Broker stopped'
        }
        'ClearConversation' {
            if (-not $Umo) { throw 'Umo is required' }
            $db = Join-Path $root 'AstrBot\data\data_v4.db'
            if (-not (Test-Path -LiteralPath $db)) { throw "database missing: $db" }
            Write-ActionStatus 'stopping' 20 '正在停止 AstrBot 以清理对话...'
            Stop-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            Stop-AstrBotProcesses
            $backup = $db + '.bak-dashboard-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
            Copy-Item -LiteralPath $db -Destination $backup -Force
            $python = Join-Path $root 'AstrBot\.venv\Scripts\python.exe'
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
            Write-ActionStatus 'starting' 80 '正在重启 AstrBot...'
            Start-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
            if (-not (Wait-Port 6185 60)) { throw 'AstrBot did not recover after conversation clear' }
            Write-ActionStatus 'done' 100 '当前对话已清空'
            Write-ActionLog ('conversation cleared for ' + $Umo)
        }
        'SaveApiKey' {
            if (-not $SecretFile) { throw 'SecretFile is required' }
            Write-ActionStatus 'saving' 40 '正在加密保存 API Key...'
            $secretHelper = Join-Path $PSScriptRoot 'dashboard_secret.ps1'
            & $secretHelper -InputFile $SecretFile -OutputFile (Join-Path $root 'tools\deepseek.key.dpapi')
            if ($LASTEXITCODE -ne 0) { throw 'API key save failed' }
            Write-ActionStatus 'done' 100 'API Key 已保存；重启 AstrBot 后生效'
            Write-ActionLog 'API key saved'
        }
    }
    exit 0
} catch {
    Write-ActionStatus 'failed' 100 ('操作失败：' + $_.Exception.Message)
    Write-ActionLog ('FAILED action=' + $Action + ' error=' + $_.Exception.Message)
    exit 1
}
