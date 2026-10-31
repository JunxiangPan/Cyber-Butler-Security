# Start the Cyber-Butler Web UI and OTP mailer idempotently.
# Run as the interactive user at logon: the OTP mailer needs the user's
# DPAPI-protected SMTP secret, which is not available to a SYSTEM task.
$ErrorActionPreference = 'Stop'
$webRoot = $PSScriptRoot
$parent = Split-Path $webRoot -Parent
if (Test-Path -LiteralPath (Join-Path $parent 'webui-config.json')) {
    $root = $parent
} else {
    $root = Split-Path $parent -Parent
}
$python = Join-Path $webRoot '.venv\Scripts\python.exe'
$config = Join-Path $root 'webui-config.json'
# settings.py also accepts webui\config.json; keep the older layout working.
if (-not (Test-Path -LiteralPath $config) -and (Test-Path -LiteralPath (Join-Path $webRoot 'config.json'))) {
    $config = Join-Path $webRoot 'config.json'
}
$dataDir = Join-Path $webRoot 'data'
$log = Join-Path $dataDir 'webui-startup.log'
$webOut = Join-Path $dataDir 'webui.out.log'
$webErr = Join-Path $dataDir 'webui.err.log'
$mailOut = Join-Path $dataDir 'otp_mailer.out.log'
$mailErr = Join-Path $dataDir 'otp_mailer.err.log'

New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

function Initialize-MailerToken {
    $tokenPath = Join-Path $dataDir 'mailer_token'
    if (Test-Path -LiteralPath $tokenPath) { return }
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $token = -join ($bytes | ForEach-Object { $_.ToString('x2') })
    Set-Content -LiteralPath $tokenPath -Value $token -Encoding ASCII -NoNewline
    Write-StartupLog 'generated webui\data\mailer_token'
}

function Write-StartupLog([string]$message) {
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message
    Add-Content -LiteralPath $log -Value $line -Encoding UTF8
}

function Test-Http200([string]$url) {
    try {
        return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 3).StatusCode -eq 200
    } catch {
        return $false
    }
}

function Wait-Http200([string]$url, [int]$seconds = 30) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Http200 $url) { return $true }
        Start-Sleep -Milliseconds 800
    }
    return $false
}

if (-not (Test-Path -LiteralPath $python)) {
    throw "Web UI Python not found: $python"
}
if (-not (Test-Path -LiteralPath $config)) {
    Write-StartupLog ("Web UI config not found: webRoot=$webRoot root=$root config=$config")
    Write-StartupLog ("Test-Path webRoot={0} root={1} config={2}" -f (Test-Path -LiteralPath $webRoot), (Test-Path -LiteralPath $root), (Test-Path -LiteralPath $config))
    throw "Web UI config not found: $config"
}

Write-StartupLog 'startup check begin'
Write-StartupLog ("paths webRoot=$webRoot root=$root config=$config")

# The mailer is optional for Web UI availability; do not block the UI on it.
Initialize-MailerToken
if (Test-Http200 'http://127.0.0.1:8766/health') {
    Write-StartupLog 'OTP mailer already ready on 127.0.0.1:8766'
} else {
    try {
        Write-StartupLog 'starting OTP mailer on 127.0.0.1:8766'
        Start-Process -FilePath $python -ArgumentList 'otp_mailer.py' `
            -WorkingDirectory $webRoot -WindowStyle Hidden `
            -RedirectStandardOutput $mailOut -RedirectStandardError $mailErr | Out-Null
        if (-not (Wait-Http200 'http://127.0.0.1:8766/health' 30)) {
            Write-StartupLog 'WARN: OTP mailer did not become healthy within 30 seconds; continuing without it'
        } else {
            Write-StartupLog 'OTP mailer is ready on 127.0.0.1:8766'
        }
    } catch {
        Write-StartupLog ('WARN: OTP mailer failed to start: ' + $_.Exception.Message)
    }
}

# Web UI: bind 0.0.0.0:8765 from webui-config.json.
if (Test-Http200 'http://127.0.0.1:8765/') {
    Write-StartupLog 'Web UI already ready on 0.0.0.0:8765'
} else {
    Write-StartupLog 'starting Web UI on 0.0.0.0:8765'
    $env:WEBUI_CONFIG = $config
    Start-Process -FilePath $python -ArgumentList 'run.py' `
        -WorkingDirectory $webRoot -WindowStyle Hidden `
        -RedirectStandardOutput $webOut -RedirectStandardError $webErr | Out-Null
    if (-not (Wait-Http200 'http://127.0.0.1:8765/' 30)) {
        throw 'Web UI did not become healthy within 30 seconds'
    }
    Write-StartupLog 'Web UI is ready on 0.0.0.0:8765'
}

Write-StartupLog 'startup check finished'
