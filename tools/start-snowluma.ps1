$ErrorActionPreference = 'Continue'
$root = 'YOUR_PROJECT_PATH'
$log = Join-Path $root 'tools\start-snowluma.log'
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

function Test-SnowLuma {
    try { return ((Invoke-WebRequest -Uri 'http://127.0.0.1:5099' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) } catch { return $false }
}

if (Test-SnowLuma) {
    Log 'SnowLuma already listening'
} else {
    try {
        Start-Process -FilePath (Join-Path $root 'SnowLuma\node.exe') `
            -ArgumentList 'index.mjs' `
            -WorkingDirectory (Join-Path $root 'SnowLuma') `
            -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $root 'SnowLuma\logs\startup-snowluma.out.log') `
            -RedirectStandardError (Join-Path $root 'SnowLuma\logs\startup-snowluma.err.log') | Out-Null
        Log 'SnowLuma start requested'
    } catch { Log ('SnowLuma start failed: ' + $_.Exception.Message) }
    for ($i=0; $i -lt 20; $i++) { if (Test-SnowLuma) { break }; Start-Sleep -Seconds 1 }
}

$guardian = @(Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*snowluma_guard.py*' })
if ($guardian.Count -eq 0) {
    try {
        Start-Process -FilePath (Join-Path $root 'AstrBot\.venv\Scripts\python.exe') `
            -ArgumentList (Join-Path $root 'tools\snowluma_guard.py') `
            -WorkingDirectory (Join-Path $root 'tools') `
            -WindowStyle Hidden `
            -RedirectStandardOutput (Join-Path $root 'tools\startup-guardian.out.log') `
            -RedirectStandardError (Join-Path $root 'tools\startup-guardian.err.log') | Out-Null
        Log 'guardian start requested'
    } catch { Log ('guardian start failed: ' + $_.Exception.Message) }
} else {
    Log 'guardian already running'
}
Log ('SnowLuma listening=' + (Test-SnowLuma))
