$ErrorActionPreference = 'Continue'
$root = 'YOUR_PROJECT_PATH'
$ffmpeg = Join-Path $root 'tools\ffmpeg-9.0.2-essentials_build\bin'
$pythonDir = Join-Path $root 'AstrBot\.venv\Scripts'
$nodeDir = 'C:\Program Files\nodejs'
$ollamaDir = 'YOUR_USER_PATH\AppData\Local\Programs\Ollama'
$userProfile = $env:USERPROFILE
if (-not $userProfile) { $userProfile = 'YOUR_SERVICE_PATH' }
$tempDir = Join-Path $userProfile 'AppData\Local\Temp'
New-Item -ItemType Directory -Force -Path $tempDir | Out-Null
$env:PATH = "$pythonDir;$nodeDir;$ollamaDir;$ffmpeg;$env:SystemRoot\System32;$env:SystemRoot;$env:PATH"
$env:OLLAMA_HOST = 'http://127.0.0.1:11434'
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUTF8 = '1'
$env:PYTHONDONTWRITEBYTECODE = '1'
$env:TEMP = $tempDir
$env:TMP = $tempDir

$dataDir = Join-Path $root 'AstrBot\data'
$snowLogDir = Join-Path $root 'SnowLuma\logs'
$serviceLog = Join-Path $dataDir 'service-astrbot-stack.log'
New-Item -ItemType Directory -Force -Path $dataDir, $snowLogDir | Out-Null

function Write-ServiceLog([string]$message) {
    $line = "{0:yyyy-MM-dd HH:mm:ss} {1}" -f (Get-Date), $message
    try { Add-Content -LiteralPath $serviceLog -Value $line -Encoding UTF8 -ErrorAction Stop } catch { }
}

function Import-DeepSeekKey {
    $secretPath = Join-Path $root 'tools\deepseek.key.dpapi'
    if (-not (Test-Path -LiteralPath $secretPath)) {
        Write-ServiceLog 'DeepSeek secret file missing; provider key remains unset'
        return
    }
    try {
        Add-Type -AssemblyName System.Security
        $encrypted = [System.IO.File]::ReadAllBytes($secretPath)
        $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
            $encrypted, $null, [System.Security.Cryptography.DataProtectionScope]::LocalMachine
        )
        $env:DEEPSEEK_API_KEY = [System.Text.Encoding]::UTF8.GetString($plain)
        Write-ServiceLog 'DeepSeek key loaded from DPAPI secret'
    } catch {
        Write-ServiceLog ("DeepSeek key load failed: " + $_.Exception.Message)
    }
}

function Test-Process([string]$pattern) {
    try {
        $items = @(Get-CimInstance Win32_Process -Filter "Name='python.exe' OR Name='node.exe'" -ErrorAction Stop |
            Where-Object { $_.CommandLine -and $_.CommandLine -like $pattern })
        return ($items.Count -gt 0)
    } catch {
        return $false
    }
}

function Start-SnowLuma {
    try {
        $out = Join-Path $snowLogDir 'service-snowluma.out.log'
        $err = Join-Path $snowLogDir 'service-snowluma.err.log'
        Start-Process -FilePath (Join-Path $root 'SnowLuma\node.exe') `
            -ArgumentList 'index.mjs' `
            -WorkingDirectory (Join-Path $root 'SnowLuma') `
            -WindowStyle Hidden `
            -RedirectStandardOutput $out `
            -RedirectStandardError $err | Out-Null
        Write-ServiceLog 'started SnowLuma'
    } catch { Write-ServiceLog "SnowLuma start failed: $($_.Exception.Message)" }
}

function Start-AstrBot {
    try {
        $out = Join-Path $dataDir 'service-astrbot.out.log'
        $err = Join-Path $dataDir 'service-astrbot.err.log'
        Start-Process -FilePath (Join-Path $root 'AstrBot\.venv\Scripts\python.exe') `
            -ArgumentList 'main.py' `
            -WorkingDirectory (Join-Path $root 'AstrBot') `
            -WindowStyle Hidden `
            -RedirectStandardOutput $out `
            -RedirectStandardError $err | Out-Null
        Write-ServiceLog 'started AstrBot'
    } catch { Write-ServiceLog "AstrBot start failed: $($_.Exception.Message)" }
}

function Start-Guardian {
    try {
        $out = Join-Path $root 'tools\service-guardian.out.log'
        $err = Join-Path $root 'tools\service-guardian.err.log'
        Start-Process -FilePath (Join-Path $root 'AstrBot\.venv\Scripts\python.exe') `
            -ArgumentList (Join-Path $root 'tools\snowluma_guard.py') `
            -WorkingDirectory (Join-Path $root 'tools') `
            -WindowStyle Hidden `
            -RedirectStandardOutput $out `
            -RedirectStandardError $err | Out-Null
        Write-ServiceLog 'started guardian'
    } catch { Write-ServiceLog "guardian start failed: $($_.Exception.Message)" }
}

Write-ServiceLog "service supervisor started as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Import-DeepSeekKey

$probeFlag = Join-Path $root 'tools\totp_acl_probe.flag'
if (Test-Path -LiteralPath $probeFlag) {
    try {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\totp_acl_probe.ps1')
        Remove-Item -LiteralPath $probeFlag -Force -ErrorAction SilentlyContinue
        Write-ServiceLog 'TOTP ACL probe completed'
    } catch {
        Write-ServiceLog ("TOTP ACL probe failed: " + $_.Exception.Message)
    }
}

while ($true) {
    # SnowLuma must run as the same Windows user as QQ.exe: it injects the
    # QQ process through the SnowLuma hook. YOUR_SERVICE_USER cannot inject YOUR_USER_NAME's
    # QQ process, so SnowLuma and the guardian are started separately as YOUR_USER_NAME.
    if (-not (Test-Process '*AstrBot*main.py*')) { Start-AstrBot }
    Start-Sleep -Seconds 20
}
