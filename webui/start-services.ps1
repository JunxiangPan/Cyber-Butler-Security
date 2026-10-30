# Start the Cyber-Butler Web UI and OTP mailer idempotently.
# Run as the interactive user at logon: the OTP mailer needs the user's
# DPAPI-protected SMTP secret, which is not available to a SYSTEM task.
$ErrorActionPreference = 'Stop'
$webRoot = $PSScriptRoot
$root = Split-Path (Split-Path $webRoot -Parent) -Parent
$python = Join-Path $webRoot '.venv\Scripts\python.exe'
$config = Join-Path $root 'webui-config.json'
$dataDir = Join-Path $webRoot 'data'
$log = Join-Path $dataDir 'webui-startup.log'
$webOut = Join-Path $dataDir 'webui.out.log'
$webErr = Join-Path $dataDir 'webui.err.log'
$mailOut = Join-Path $dataDir 'otp_mailer.out.log'
$mailErr = Join-Path $dataDir 'otp_mailer.err.log'

New-Item -ItemType Directory -Path $dataDir -Force | Out-Null

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
    throw "Web UI config not found: $config"
}

Write-StartupLog 'startup check begin'

# The mailer must be listening before the browser can request an OTP.
if (Test-Http200 'http://127.0.0.1:8766/health') {
    Write-StartupLog 'OTP mailer already ready on 127.0.0.1:8766'
} else {
    Write-StartupLog 'starting OTP mailer on 127.0.0.1:8766'
    Start-Process -FilePath $python -ArgumentList 'otp_mailer.py' `
        -WorkingDirectory $webRoot -WindowStyle Hidden `
        -RedirectStandardOutput $mailOut -RedirectStandardError $mailErr | Out-Null
    if (-not (Wait-Http200 'http://127.0.0.1:8766/health' 30)) {
        throw 'OTP mailer did not become healthy within 30 seconds'
    }
    Write-StartupLog 'OTP mailer is ready on 127.0.0.1:8766'
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
