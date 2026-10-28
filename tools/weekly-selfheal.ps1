$ErrorActionPreference = 'Continue'
$root = 'YOUR_PROJECT_PATH'
$log = Join-Path $root 'tools\weekly-selfheal.log'
$memoryFile = Join-Path $root 'tools\weekly-selfheal-memory.jsonl'
$gameModeLog = Join-Path $env:USERPROFILE 'Desktop\大肥鱼专用文件夹\game-mode.log'
$gameList = Join-Path $root 'tools\game-list.txt'
$tempDir = Join-Path $root 'AstrBot\data\temp'

function Log([string]$m) {
    Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8
}

function Test-Url([string]$url) {
    try { return ((Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200) }
    catch { return $false }
}

function Get-MemorySnapshot([string]$phase) {
    $cs = Get-CimInstance Win32_ComputerSystem
    $os = Get-CimInstance Win32_OperatingSystem
    $total = [double]$cs.TotalPhysicalMemory
    $free = [double]$os.FreePhysicalMemory * 1KB
    $pids = @{}
    foreach ($port in @(6185, 5099, 11434)) {
        $c = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        if ($c) { $pids[[int]$c.OwningProcess] = $true }
    }
    foreach ($p in Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='node.exe' OR Name='ollama.exe' OR Name='llama-server.exe'" -ErrorAction SilentlyContinue) {
        $cmd = [string]$p.CommandLine
        if ($cmd -match 'AstrBot.*main\.py|SnowLuma.*index\.mjs|snowluma_guard\.py|ollama|llama-server') {
            $pids[[int]$p.ProcessId] = $true
        }
    }
    $rows = @()
    foreach ($processId in @($pids.Keys)) {
        $proc = Get-Process -Id ([int]$processId) -ErrorAction SilentlyContinue
        if ($proc) {
            $rows += [pscustomobject]@{
                pid = [int]$proc.Id
                name = $proc.ProcessName
                working_set_mb = [math]::Round($proc.WorkingSet64 / 1MB, 1)
                private_mb = [math]::Round($proc.PrivateMemorySize64 / 1MB, 1)
            }
        }
    }
    $snapshot = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        phase = $phase
        total_memory_gb = [math]::Round($total / 1GB, 1)
        free_memory_gb = [math]::Round($free / 1GB, 1)
        memory_percent = if ($total -gt 0) { [math]::Round((($total - $free) / $total) * 100, 1) } else { 0 }
        processes = $rows
    }
    Add-Content -LiteralPath $memoryFile -Value ($snapshot | ConvertTo-Json -Depth 4 -Compress) -Encoding UTF8
    Log ("memory snapshot " + $phase + " system=" + $snapshot.memory_percent + "% processes=" + $rows.Count)
}

function Test-GameRunning {
    if (Test-Path -LiteralPath $gameModeLog) {
        $lines = @(Get-Content -LiteralPath $gameModeLog -Tail 500 -ErrorAction SilentlyContinue)
        $lastOn = -1
        $lastOff = -1
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match 'GAME MODE ON') { $lastOn = $i }
            if ($lines[$i] -match 'GAME MODE OFF') { $lastOff = $i }
        }
        if ($lastOn -gt $lastOff) { return $true }
    }
    $names = @()
    if (Test-Path -LiteralPath $gameList) {
        $names = @(Get-Content -LiteralPath $gameList -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ -and -not $_.StartsWith('#') })
    }
    foreach ($proc in Get-Process -ErrorAction SilentlyContinue) {
        if ($names -contains $proc.ProcessName) { return $true }
    }
    return $false
}

function Get-OllamaUnavailableReason {
    try {
        Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 3 | Out-Null
        return ""
    } catch {
        $candidates = @(
            (Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'),
            'C:\Program Files\Ollama\ollama.exe'
        )
        $exe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $exe) {
            $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue
            $exe = if ($cmd) { $cmd.Source } else { $null }
        }
        if (-not $exe) { return 'not found' }
        return 'not running'
    }
}

function Stop-Model {
    if ($script:OllamaReason) {
        Log ("Skipped (Ollama {0})" -f $script:OllamaReason)
        return
    }
    try {
        $body = @{ model = 'sujinyan-chat-24k:latest'; prompt = ''; stream = $false; keep_alive = 0 } | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:11434/api/generate' -ContentType 'application/json' -Body $body -TimeoutSec 30 | Out-Null
        Log 'Ollama unload request sent'
    } catch { Log ('Ollama unload failed: ' + $_.Exception.Message) }
    Start-Sleep -Seconds 2
    try {
        $ps = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/ps' -TimeoutSec 5
        $still = @($ps.models | Where-Object { $_.name -eq 'sujinyan-chat-24k:latest' })
        Log ('Ollama model resident=' + ($still.Count -gt 0))
    } catch { Log 'Ollama ps check failed' }
}

function Stop-Stack {
    try { Stop-ScheduledTask -TaskName 'SnowLuma Startup' -ErrorAction SilentlyContinue } catch { }
    try { Stop-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue } catch { }
    Start-Sleep -Seconds 2
    $procs = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='node.exe' OR Name='powershell.exe'" -ErrorAction SilentlyContinue)
    foreach ($p in $procs) {
        $cmd = [string]$p.CommandLine
        $kill = $false
        if ($p.Name -eq 'python.exe') {
            $owner = ''
            try {
                $o = Invoke-CimMethod -InputObject $p -MethodName GetOwner -ErrorAction Stop
                $owner = "$($o.Domain)\$($o.User)"
            } catch { }
            if ($owner -eq 'YOUR_HOST\YOUR_SERVICE_USER') { $kill = $true }
        }
        if ($p.Name -eq 'python.exe' -and $cmd -match 'AstrBot.*main\.py') { $kill = $true }
        if ($p.Name -eq 'python.exe' -and $cmd -match 'snowluma_guard\.py') { $kill = $true }
        if ($p.Name -eq 'node.exe' -and $cmd -match 'SnowLuma.*index\.mjs') { $kill = $true }
        if ($p.Name -eq 'node.exe' -and $cmd -match 'playwright.*mcp.*cli\.js') { $kill = $true }
        if ($p.Name -eq 'powershell.exe' -and $cmd -match 'run-astrbot-service\.ps1') { $kill = $true }
        if ($kill) {
            try { Stop-Process -Id $p.ProcessId -Force -ErrorAction Stop; Log ('killed ' + $p.ProcessId + ' ' + $p.Name) } catch { Log ('kill failed ' + $p.ProcessId + ': ' + $_.Exception.Message) }
        }
    }
    Start-Sleep -Seconds 2
}

function Clear-Temp {
    if (-not (Test-Path -LiteralPath $tempDir)) { Log 'temp dir missing'; return }
    $files = @(Get-ChildItem -LiteralPath $tempDir -Force -ErrorAction SilentlyContinue)
    $bytes = 0
    foreach ($f in $files) { try { $bytes += [double]$f.Length } catch { } }
    foreach ($f in $files) { try { Remove-Item -LiteralPath $f.FullName -Recurse -Force -ErrorAction SilentlyContinue } catch { } }
    Log ('temp cleaned: objects=' + $files.Count + ' bytes=' + [math]::Round($bytes / 1MB, 1) + 'MB')
}

function Start-Stack {
    if ($script:OllamaReason) {
        Log ("Skipped Ollama startup (Ollama {0})" -f $script:OllamaReason)
    } else {
        try { Start-ScheduledTask -TaskName 'Ollama Startup' -ErrorAction SilentlyContinue; Log 'started Ollama task' } catch { }
    }
    Start-Sleep -Seconds 3
    try { Start-ScheduledTask -TaskName 'SnowLuma Startup' -ErrorAction SilentlyContinue; Log 'started SnowLuma task' } catch { }
    Start-Sleep -Seconds 8
    try { Start-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue; Log 'started AstrBot task' } catch { }
}

function Test-Stack {
    $api = Test-Url 'http://127.0.0.1:6185'
    $snow = Test-Url 'http://127.0.0.1:5099'
    if ($script:OllamaReason) {
        Log ('check api=' + $api + ' snow=' + $snow + ' mode=cloud (Ollama ' + $script:OllamaReason + ')')
        return ($api -and $snow)
    }
    $ollama = Test-Url 'http://127.0.0.1:11434'
    $model = $false
    try {
        $ps = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/ps' -TimeoutSec 5
        $model = @($ps.models | Where-Object { $_.name -eq 'sujinyan-chat-24k:latest' }).Count -gt 0
    } catch { }
    Log ('check api=' + $api + ' snow=' + $snow + ' ollama=' + $ollama + ' model=' + $model)
    return ($api -and $snow -and $ollama -and $model)
}

Log 'weekly self-heal started'
$script:OllamaReason = Get-OllamaUnavailableReason
if ($script:OllamaReason) {
    Log ("Skipped (Ollama {0})" -f $script:OllamaReason)
}
$before = Get-MemorySnapshot 'before'
if (Test-GameRunning) {
    Log 'game appears to be running; skipping weekly self-heal'
    Write-Output 'WEEKLY_SKIPPED_GAME'
    exit 0
}

$success = $false
for ($attempt = 1; $attempt -le 3; $attempt++) {
    Log ('attempt ' + $attempt + '/3')
    Stop-Stack
    Stop-Model
    Clear-Temp
    Log 'waiting 15 seconds before restart'
    Start-Sleep -Seconds 15
    Start-Stack
    $ready = $false
    for ($i = 0; $i -lt 40; $i++) {
        if (Test-Stack) { $ready = $true; break }
        Start-Sleep -Seconds 3
    }
    if ($ready) {
        $success = $true
        Log ('attempt ' + $attempt + ' succeeded')
        break
    }
    Log ('attempt ' + $attempt + ' failed')
    Start-Sleep -Seconds 10
}

Get-MemorySnapshot 'after'
if (-not $success) {
    Log 'weekly self-heal failed after 3 attempts'
    Write-Output 'WEEKLY_SELFHEAL_FAILED'
    exit 1
}
Write-Output 'WEEKLY_SELFHEAL_OK'
exit 0
