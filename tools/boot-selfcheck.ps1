# Boot self-check: wait for the stack, warm the local model and restore local routing.
# Runs as SYSTEM at startup/logon; user-scoped SnowLuma/QQ tasks are started by name.
$ErrorActionPreference = 'Continue'
$root = 'YOUR_PROJECT_PATH'
$runtime = 'YOUR_USER_PATH\Desktop\大肥鱼专用文件夹'
$log = Join-Path $runtime 'boot-selfcheck.log'
$tokenFile = Join-Path $root '.astrbot_token'
$umo = 'qq_sujinyan:FriendMessage:YOUR_QQ_ID'
$model = 'sujinyan-chat-24k:latest'

function Write-CheckLog([string]$message) {
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message
    try {
        New-Item -ItemType Directory -Path $runtime -Force | Out-Null
        Add-Content -LiteralPath $log -Value $line -Encoding UTF8
    } catch { }
}

function Test-Http([string]$url) {
    try { return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200 }
    catch { return $false }
}

function Ensure-Task([string]$name) {
    try { Start-ScheduledTask -TaskName $name -ErrorAction Stop; Write-CheckLog "started task $name" }
    catch { Write-CheckLog "task $name start failed: $($_.Exception.Message)" }
}

function Notify-Owner([string]$message) {
    try {
        if (-not (Test-Http 'http://127.0.0.1:6185')) { return }
        $token = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
        $json = @{ umo = $umo; message = $message } | ConvertTo-Json -Compress
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
        Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:6185/api/v1/im/messages' `
            -Headers @{ Authorization = "Bearer $token" } `
            -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 15 | Out-Null
        Write-CheckLog 'owner notification sent (UTF-8)'
    } catch {
        Write-CheckLog "owner notification failed: $($_.Exception.Message)"
    }
}

Write-CheckLog 'boot self-check started'

if (-not (Test-Http 'http://127.0.0.1:11434/api/tags')) {
    Ensure-Task 'Ollama Startup'
    Start-Sleep -Seconds 20
}

if (-not (Test-Http 'http://127.0.0.1:6185')) {
    Ensure-Task 'AstrBot Service'
    Start-Sleep -Seconds 25
}

if (-not (Test-Http 'http://127.0.0.1:5099')) {
    Ensure-Task 'SnowLuma Startup'
    Start-Sleep -Seconds 20
}

# Warm the local chat model if it is not resident.
try {
    $ps = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/ps' -TimeoutSec 5
    $names = @($ps.models | ForEach-Object { $_.name })
    if ($names -notcontains $model) {
        Write-CheckLog "local model missing; warming $model"
        $body = @{ model = $model; prompt = 'hi'; stream = $false; keep_alive = '5m';
                   options = @{ num_predict = 1 } } | ConvertTo-Json -Depth 6
        Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:11434/api/generate' `
            -Body $body -ContentType 'application/json' -TimeoutSec 180 | Out-Null
        Write-CheckLog 'local model warm request finished'
    } else {
        Write-CheckLog 'local model already resident'
    }
} catch {
    Write-CheckLog "model warm failed: $($_.Exception.Message)"
}

# Restore the private session to the local provider after a reboot.
try {
    if (Test-Http 'http://127.0.0.1:6185') {
        $token = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
        $body = @{ umos = @($umo); provider_id = 'local_qwen36';
                   provider_type = 'chat_completion' } | ConvertTo-Json -Depth 4
        $response = Invoke-RestMethod -Method Patch `
            -Uri 'http://127.0.0.1:6185/api/v1/sessions/provider' `
            -Headers @{ Authorization = "Bearer $token" } `
            -ContentType 'application/json' -Body $body -TimeoutSec 20
        Write-CheckLog ('provider restore: ' + $response.status)
    }
} catch {
    Write-CheckLog "provider restore failed: $($_.Exception.Message)"
}

$status = [ordered]@{
    ollama = (Test-Http 'http://127.0.0.1:11434/api/tags')
    astrbot = (Test-Http 'http://127.0.0.1:6185')
    snowluma = (Test-Http 'http://127.0.0.1:5099')
}
Write-CheckLog ('boot self-check finished: ' + ($status | ConvertTo-Json -Compress))
$failed = @($status.GetEnumerator() | Where-Object { -not $_.Value })
if ($failed.Count -gt 0) {
    $names = ($failed | ForEach-Object { $_.Key }) -join ', '
    Notify-Owner "哥，开机自检发现异常：$names。瑾言已经尝试自动处理，请你有空看一下日志。"
}
