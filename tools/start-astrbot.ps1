# Start AstrBot with a one-time, installer-supplied dashboard password.
# The password is written by the installer under AstrBot\data\logs and is
# shown in the post-install window. After the first successful startup a marker
# prevents the password from being reset on every service restart.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$astrbot = Join-Path $root 'AstrBot'
$python = Join-Path $astrbot '.venv\Scripts\python.exe'
$passwordFile = Join-Path $astrbot 'data\logs\initial-admin-password.txt'
$marker = Join-Path $astrbot 'data\.cbs-dashboard-password-initialized'
$logDir = Split-Path -Parent $passwordFile
New-Item -ItemType Directory -Path $logDir -Force | Out-Null

if (-not (Test-Path -LiteralPath $python)) {
    throw "AstrBot Python not found: $python"
}
if (-not (Test-Path -LiteralPath $passwordFile)) {
    throw "AstrBot initial password file missing: $passwordFile"
}

$password = (Get-Content -LiteralPath $passwordFile -Raw -Encoding UTF8).Trim()
if ([string]::IsNullOrWhiteSpace($password)) {
    throw "AstrBot initial password file is empty: $passwordFile"
}

$configPath = Join-Path $astrbot 'data\cmd_config.json'
$resetPassword = $false
if (-not (Test-Path -LiteralPath $configPath)) {
    # Fresh install: let AstrBot generate the config with our known password.
    # --reset-password is parsed before AstrBot imports its config modules.
    $env:ASTRBOT_DASHBOARD_INITIAL_PASSWORD = $password
    $resetPassword = $true
    Set-Content -LiteralPath $marker -Value (Get-Date -Format o) -Encoding UTF8
}

Push-Location $astrbot
try {
    if ($resetPassword) { & $python main.py --reset-password }
    else { & $python main.py }
    $code = $LASTEXITCODE
    if ($code -ne 0 -and (Test-Path -LiteralPath $marker)) {
        # A one-time password/env failure must not leave AstrBot unusable.
        # Retry without the reset hint; the existing config is authoritative.
        Write-Host ("AstrBot first start failed with exit " + $code + "; retrying without password reset")
        Remove-Item Env:ASTRBOT_DASHBOARD_INITIAL_PASSWORD -ErrorAction SilentlyContinue
        Remove-Item Env:ASTRBOT_RESET_DASHBOARD_PASSWORD -ErrorAction SilentlyContinue
        & $python main.py
        $code = $LASTEXITCODE
    }
    exit $code
} finally {
    Pop-Location
}
