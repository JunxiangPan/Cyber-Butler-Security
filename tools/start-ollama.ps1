$ErrorActionPreference = 'Continue'
$root = 'YOUR_PROJECT_PATH'
$ollama = 'YOUR_USER_PATH\AppData\Local\Programs\Ollama\ollama.exe'
$log = Join-Path $root 'tools\start-ollama.log'
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

function Test-Ollama {
    try { return ((Invoke-WebRequest -Uri 'http://127.0.0.1:11434/api/tags' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) } catch { return $false }
}

if (Test-Ollama) {
    Log 'Ollama already listening'
} else {
    try {
        Start-Process -FilePath $ollama -ArgumentList 'serve' -WorkingDirectory (Split-Path $ollama) -WindowStyle Hidden -RedirectStandardOutput (Join-Path $root 'tools\ollama-serve.out.log') -RedirectStandardError (Join-Path $root 'tools\ollama-serve.err.log') | Out-Null
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
    try {
        $body = @{ model = 'sujinyan-chat-24k:latest'; prompt = 'hi'; stream = $false; keep_alive = '5m'; options = @{ num_predict = 1 } } | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:11434/api/generate' -ContentType 'application/json' -Body $body -TimeoutSec 180 | Out-Null
        Log 'local model loaded'
    } catch { Log ("model load failed: " + $_.Exception.Message) }
} else {
    Log 'Ollama still unavailable'
}
