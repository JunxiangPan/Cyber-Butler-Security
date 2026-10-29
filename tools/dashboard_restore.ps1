#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
Elevated recovery helper for the Cyber-Butler dashboard.

Modes:
  Restore   - safety backup current data, stop AstrBot, replace data, restart
  Downgrade - safety backup data, then call update_merge.ps1 for a selected release

This helper is intentionally separate from the WPF UI: all destructive work
runs elevated and writes progress to a status file.
#>
param(
    [Parameter(Mandatory = $true)][ValidateSet('Restore', 'Downgrade')][string]$Mode,
    [Parameter(Mandatory = $true)][string]$TargetRoot,
    [string]$BackupPath = '',
    [string]$AssetUrl = '',
    [string]$Version = '',
    [string]$StatusFile = '',
    [string]$LogFile = ''
)

$ErrorActionPreference = 'Stop'
$target = (Resolve-Path -LiteralPath $TargetRoot).Path
$dataDir = Join-Path $target 'AstrBot\data'
$backupDir = Join-Path $target 'backups'
$mergeScript = Join-Path $target 'tools\update_merge.ps1'
$python = Join-Path $target 'AstrBot\.venv\Scripts\python.exe'
if (-not $LogFile) { $LogFile = Join-Path $backupDir 'restore_history.log' }
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

function Write-Status([string]$stage, [int]$progress, [string]$message) {
    if (-not $StatusFile) { return }
    try {
        $parent = Split-Path -Parent $StatusFile
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [ordered]@{ stage = $stage; progress = $progress; message = $message; updated_at = (Get-Date).ToString('o') } |
            ConvertTo-Json -Compress | Set-Content -LiteralPath $StatusFile -Encoding UTF8
    } catch { }
}

function Write-Log([string]$message) {
    try {
        Add-Content -LiteralPath $LogFile -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message) -Encoding UTF8
    } catch { }
}

function New-SafetyBackup([string]$label) {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zip = Join-Path $backupDir ('pre-' + $label + '-' + $stamp + '.zip')
    $temp = Join-Path $env:TEMP ('cbs-pre-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        $exclude = @(
            (Join-Path $dataDir 'temp'), (Join-Path $dataDir 'logs'),
            (Join-Path $dataDir 'cache'), (Join-Path $dataDir '__pycache__'),
            (Join-Path $dataDir 'dist'), (Join-Path $dataDir 'plugins'),
            (Join-Path $dataDir 'plugin_data\meme_manager\packs'),
            (Join-Path $dataDir 'workspaces')
        )
        $args = @($dataDir, $temp, '/E', '/R:1', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XD') + $exclude + @('/XF', '*.log', '*.tmp', '*.lock')
        & robocopy.exe @args | Out-Null
        if ($LASTEXITCODE -gt 7) { throw ('safety robocopy failed: ' + $LASTEXITCODE) }
        Compress-Archive -Path (Join-Path $temp '*') -DestinationPath $zip -CompressionLevel Fastest -Force
        Write-Log ('safety backup: ' + $zip)
        return $zip
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Stop-AstrBot {
    Write-Status 'stopping' 25 '正在停止 AstrBot 服务...'
    Stop-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -match 'main\.py' })
    foreach ($p in $procs) { try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop } catch { } }
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        $listen = @(Get-NetTCPConnection -LocalPort 6185 -State Listen -ErrorAction SilentlyContinue)
        if ($listen.Count -eq 0) { return }
        Start-Sleep -Seconds 1
    }
    throw 'AstrBot did not release port 6185'
}

function Start-AstrBot {
    Write-Status 'starting' 85 '正在启动 AstrBot 服务...'
    Start-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        try {
            if ((Invoke-WebRequest -Uri 'http://127.0.0.1:6185' -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) { return }
        } catch { }
        Start-Sleep -Seconds 2
    }
    throw 'AstrBot did not become healthy after restart'
}

function Invoke-Restore {
    if (-not $BackupPath -or -not (Test-Path -LiteralPath $BackupPath)) { throw ('备份文件不存在：' + $BackupPath) }
    if (-not (Test-Path -LiteralPath $dataDir)) { throw ('数据目录不存在：' + $dataDir) }
    Write-Status 'preparing' 10 '正在准备恢复...'
    Write-Log ('RESTORE requested backup=' + $BackupPath)
    Stop-AstrBot
    try {
        $safety = New-SafetyBackup 'restore'
    } catch {
        Start-AstrBot
        throw
    }
    $extract = Join-Path $env:TEMP ('cbs-restore-' + [guid]::NewGuid().ToString('N'))
    $oldData = $dataDir + '.pre-restore-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
    try {
        Write-Status 'extracting' 40 '正在解压备份...'
        New-Item -ItemType Directory -Path $extract -Force | Out-Null
        Expand-Archive -LiteralPath $BackupPath -DestinationPath $extract -Force
        if (@(Get-ChildItem -LiteralPath $extract -Force -ErrorAction SilentlyContinue).Count -eq 0) { throw '备份压缩包为空' }
        Write-Status 'replacing' 60 '正在替换数据目录...'
        Move-Item -LiteralPath $dataDir -Destination $oldData -Force
        New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
        Copy-Item -Path (Join-Path $extract '*') -Destination $dataDir -Recurse -Force
        Write-Status 'restarting' 80 '数据已恢复，正在重启服务...'
        Start-AstrBot
        Write-Status 'done' 100 '恢复完成'
        Write-Log ('RESTORE OK safety=' + $safety + ' old=' + $oldData)
        return [ordered]@{ status = 'ok'; safety_backup = $safety; old_data = $oldData }
    } catch {
        Write-Log ('RESTORE FAILED: ' + $_.Exception.Message)
        try {
            if (Test-Path -LiteralPath $dataDir) { Remove-Item -LiteralPath $dataDir -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $oldData) { Move-Item -LiteralPath $oldData -Destination $dataDir -Force }
            Start-AstrBot
        } catch { }
        throw
    } finally {
        Remove-Item -LiteralPath $extract -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-Downgrade {
    if (-not $AssetUrl) { throw '缺少历史版本资产 URL' }
    if (-not (Test-Path -LiteralPath $mergeScript)) { throw ('更新脚本不存在：' + $mergeScript) }
    Write-Status 'preparing' 10 ('正在准备回退到 ' + $Version + '...')
    Write-Log ('DOWNGRADE requested version=' + $Version + ' url=' + $AssetUrl)
    $safety = New-SafetyBackup 'downgrade'
    Write-Status 'downloading' 25 '正在校验历史版本资产...'
    $download = Join-Path $env:TEMP ('cbs-downgrade-' + [guid]::NewGuid().ToString('N') + '.zip')
    try {
        Invoke-WebRequest -Uri $AssetUrl -OutFile $download -UseBasicParsing -TimeoutSec 300
        $sha = (Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash.ToLower()
        $checkDir = Join-Path $env:TEMP ('cbs-manifest-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $checkDir -Force | Out-Null
        Expand-Archive -LiteralPath $download -DestinationPath $checkDir -Force
        $manifest = Join-Path $checkDir 'update-manifest.json'
        if (-not (Test-Path -LiteralPath $manifest)) {
            throw '历史包缺少 update-manifest.json；为安全起见已停止回退，未修改生产代码。'
        }
        Write-Status 'applying' 45 '正在调用生产更新器...'
        # The user already confirmed this reinstall/downgrade in the dashboard.
        # Replacing the selected release is the point of the action, so allow
        # update_merge.ps1 to overwrite local code changes in the target tree.
        Write-Log 'applying release with AllowLocalCodeChanges (explicit user confirmation)'
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $mergeScript `
            -TargetRoot $target -PythonPath $python -AssetUrl $AssetUrl `
            -ExpectedSha256 $sha -ConfirmationText 'UPDATE PRODUCTION' -StatusFile $StatusFile `
            -AllowLocalCodeChanges
        if ($LASTEXITCODE -ne 0) { throw ('update_merge failed: ' + $LASTEXITCODE) }
        Write-Status 'done' 100 ('已回退到 ' + $Version)
        Write-Log ('DOWNGRADE OK version=' + $Version + ' safety=' + $safety)
        return [ordered]@{ status = 'ok'; safety_backup = $safety; version = $Version }
    } catch {
        Write-Log ('DOWNGRADE FAILED: ' + $_.Exception.Message)
        throw
    } finally {
        Remove-Item -LiteralPath @($download, $checkDir) -Recurse -Force -ErrorAction SilentlyContinue
    }
}

try {
    $result = if ($Mode -eq 'Restore') { Invoke-Restore } else { Invoke-Downgrade }
    if ($StatusFile) { $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $StatusFile -Encoding UTF8 }
    $result | ConvertTo-Json -Depth 5
    exit 0
} catch {
    Write-Status 'failed' 100 ('操作失败：' + $_.Exception.Message)
    Write-Log ('FATAL: ' + $_.Exception.Message)
    [ordered]@{ status = 'failed'; error = $_.Exception.Message } | ConvertTo-Json -Depth 4
    exit 1
}
