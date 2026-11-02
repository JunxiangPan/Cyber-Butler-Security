$ErrorActionPreference = 'Continue'
$root = 'YOUR_PROJECT_PATH'
if ($root -like 'YOUR_*') { Write-Error 'Cyber-Butler placeholders were not rendered; refusing to start SnowLuma.'; exit 1 }
$env:SNOWLUMA_HOOK_AUTOLOAD = 'true'
$log = Join-Path $root 'SnowLuma\logs\start-snowluma.log'
New-Item -ItemType Directory -Force -Path (Split-Path $log) | Out-Null
function Log([string]$m) { Add-Content -LiteralPath $log -Value ("{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $m) -Encoding UTF8 }

function Test-SnowLuma {
    try { return ((Invoke-WebRequest -Uri 'http://127.0.0.1:5099' -UseBasicParsing -TimeoutSec 2).StatusCode -eq 200) } catch { return $false }
}

for ($w = 0; $w -lt 30; $w++) {
    if (Get-Process QQ -ErrorAction SilentlyContinue) { break }
    Start-Sleep -Seconds 2
}
Log ('QQ present=' + [bool](Get-Process QQ -ErrorAction SilentlyContinue))

if (-not (Get-Process QQ -ErrorAction SilentlyContinue)) {
    $qqCandidates = @(
        (Join-Path $env:ProgramFiles 'Tencent\QQNT\QQ.exe'),
        (Join-Path ${env:ProgramFiles(x86)} 'Tencent\QQNT\QQ.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Tencent\QQNT\QQ.exe')
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if ($qqCandidates) {
        try {
            Start-Process -FilePath $qqCandidates
            Log ('QQ start requested: ' + $qqCandidates)
            Start-Sleep -Seconds 10
        } catch { Log ('QQ start failed: ' + $_.Exception.Message) }
    } else {
        Log 'QQNT not found; SnowLuma will start without injecting QQ'
    }
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
