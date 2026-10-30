$ErrorActionPreference = 'Continue'

# The install root tools/ directory is read-only for the service account.
# Runtime logs must never be written there; use the per-user local app data
# (or ProgramData/TEMP when running as SYSTEM).
$root = Split-Path -Parent $PSScriptRoot
$ollama = Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'
if (-not (Test-Path -LiteralPath $ollama)) {
    $ollama = Join-Path $root 'tools\ollama.exe'
}

if ($env:LOCALAPPDATA) {
    $logDir = Join-Path $env:LOCALAPPDATA 'CyberButler\logs'
} else {
    $logDir = 'C:\ProgramData\CyberButler\logs'
}
try {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
} catch {
    $logDir = $env:TEMP
}
$log = Join-Path $logDir 'start-ollama.log'
$serveOut = Join-Path $logDir 'ollama-serve.out.log'
$serveErr = Join-Path $logDir 'ollama-serve.err.log'

function Log([string]$m) {
    try {
        Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 -ErrorAction SilentlyContinue
    } catch { }
}

function Test-Ollama {
    try { return ((Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) } catch { return $false }
}

function Get-EmbedOwner {
    $conn = Get-NetTCPConnection -LocalPort 11435 -State Listen -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $conn -or -not $conn.OwningProcess) { return $null }
    $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$($conn.OwningProcess)" -ErrorAction SilentlyContinue
    if (-not $proc -or $proc.Name -ne 'ollama.exe' -or $proc.CommandLine -notmatch 'serve') {
        return $null
    }
    return [pscustomobject]@{ Pid = [int]$conn.OwningProcess; Name = $proc.Name }
}

if (Test-Ollama) {
    Log 'Ollama already listening'
} else {
    try {
        Start-Process -FilePath $ollama -ArgumentList 'serve' -WorkingDirectory (Split-Path $ollama) -WindowStyle Hidden -RedirectStandardOutput $serveOut -RedirectStandardError $serveErr | Out-Null
        Log 'Ollama serve started'
    } catch { Log ("Ollama start failed: " + $_.Exception.Message) }
    for ($i=0; $i -lt 20; $i++) { if (Test-Ollama) { break }; Start-Sleep -Seconds 2 }
}

if (Test-Ollama) {
    try {
        $tags = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10
        $names = @($tags.models | ForEach-Object { $_.name })
        if ($names -notcontains 'sujinyan-chat-24k:latest') {
            $gguf = Join-Path $root 'tools\qwen36-base.gguf'
            $mf = Join-Path $root 'tools\Modelfile.restore-sujinyan'
            if ((Test-Path -LiteralPath $gguf) -and (Test-Path -LiteralPath $mf)) {
                Log 'local model manifest missing; recreating from local GGUF'
                $createOut = & $ollama create 'sujinyan-chat-24k:latest' -f $mf 2>&1
                Log ('ollama create exit=' + $LASTEXITCODE)
                $createOut | Select-Object -Last 5 | ForEach-Object { Log $_ }
            } else {
                Log 'local model missing and recovery GGUF/Modelfile not found'
            }
        }
    } catch { Log ("model check failed: " + $_.Exception.Message) }
    $loaded = @()
    try {
        $loadedPs = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/ps' -TimeoutSec 10
        $loaded = @($loadedPs.models | Where-Object { $_.name })
    } catch { Log ("model ps check failed: " + $_.Exception.Message) }
    if ($loaded.Count -gt 0) {
        Log 'local model already loaded; skip generate'
    } else {
        try {
            $body = @{ model = 'sujinyan-chat-24k:latest'; prompt = 'hi'; stream = $false; keep_alive = '5m'; options = @{ num_predict = 1 } } | ConvertTo-Json -Depth 5
            Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:11434/api/generate' -ContentType 'application/json' -Body $body -TimeoutSec 180 | Out-Null
            Log 'local model loaded'
        } catch { Log ("model load failed: " + $_.Exception.Message) }
    }
} else {
    Log 'Ollama still unavailable'
}


# --- embed Ollama 11435 (bge, 10m keep_alive) ---
$embedPidFile = Join-Path $PSScriptRoot 'ollama-embed-11435.pid'
$embedListening = Get-NetTCPConnection -LocalPort 11435 -State Listen -ErrorAction SilentlyContinue
if (-not $embedListening) {
    try {
        $embedEnv = @{
            OLLAMA_HOST = '127.0.0.1:11435'
            OLLAMA_KEEP_ALIVE = '10m'
            OLLAMA_MODELS = 'D:\.ollama\models'
            OLLAMA_LLM_LIBRARY = 'cpu'
        }
        $previous = @{}
        foreach ($key in $embedEnv.Keys) {
            $previous[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, $embedEnv[$key], 'Process')
        }
        $embedOut = Join-Path $logDir 'ollama-embed-11435.out.log'
        $embedErr = Join-Path $logDir 'ollama-embed-11435.err.log'
        $embedProc = Start-Process -FilePath $ollama -ArgumentList 'serve' -WorkingDirectory (Split-Path $ollama) -WindowStyle Hidden -RedirectStandardOutput $embedOut -RedirectStandardError $embedErr -PassThru
        Log ('embed Ollama 11435 wrapper pid=' + $embedProc.Id)
        foreach ($key in $previous.Keys) {
            [Environment]::SetEnvironmentVariable($key, $previous[$key], 'Process')
        }
    } catch {
        Log ('embed Ollama 11435 start failed: ' + $_.Exception.Message)
    }
    for ($i=0; $i -lt 15; $i++) {
        try {
            if ((Invoke-WebRequest -Uri 'http://127.0.0.1:11435/api/tags' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) { break }
        } catch { }
        Start-Sleep -Seconds 1
    }
    $embedOwner = Get-EmbedOwner
    if ($embedOwner) {
        Set-Content -LiteralPath $embedPidFile -Value $embedOwner.Pid -Encoding ASCII
        Log ('embed Ollama 11435 owner pid=' + $embedOwner.Pid + ' name=' + $embedOwner.Name)
    } else {
        Set-Content -LiteralPath $embedPidFile -Value '' -Encoding ASCII
        Log 'embed Ollama 11435 owner validation failed; pid file cleared'
    }
} else {
    $embedOwner = Get-EmbedOwner
    if ($embedOwner) {
        Set-Content -LiteralPath $embedPidFile -Value $embedOwner.Pid -Encoding ASCII
        Log ('embed Ollama 11435 already listening owner pid=' + $embedOwner.Pid + ' name=' + $embedOwner.Name)
    } else {
        Set-Content -LiteralPath $embedPidFile -Value '' -Encoding ASCII
        Log ('embed Ollama 11435 listener ignored: owner=' + $embedListening.OwningProcess)
    }
}
