# Recover a stale game-mode state if the monitor process was terminated.
# Intended to run every minute from Task Scheduler as the desktop user.
$ErrorActionPreference = 'Continue'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$gameScript = Join-Path $PSScriptRoot 'game-mode.ps1'
$runtime = Join-Path $env:USERPROFILE 'Desktop\大肥鱼专用文件夹'
$stateFile = Join-Path $runtime 'game-mode.state.json'
$log = Join-Path $runtime 'game-mode-watchdog.log'

function Write-WatchdogLog([string]$message) {
    $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message
    try { Add-Content -LiteralPath $log -Value $line -Encoding UTF8 } catch { }
}

if (-not (Test-Path -LiteralPath $stateFile)) { exit 0 }
try {
    $state = Get-Content -LiteralPath $stateFile -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Write-WatchdogLog ('state parse failed: ' + $_.Exception.Message)
    exit 0
}
if (-not $state.active) { exit 0 }

# If the monitor is still alive, it owns recovery.
$monitors = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -like '*game-mode.ps1*' -and $_.CommandLine -notlike '*ListGames*' })
if ($monitors.Count -gt 0) { exit 0 }

# Do not restore while a game/launcher is still present.
$listOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gameScript -ListGames 2>&1 | Out-String)
if ($listOutput -notmatch 'No game processes detected') {
    Write-WatchdogLog 'game still detected; leaving active state for the next check'
    exit 0
}

Write-WatchdogLog 'monitor is gone and no game is detected; running RestoreOnly'
$restoreOutput = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $gameScript -RestoreOnly 2>&1 | Out-String)
$restoreOutput.Trim() | ForEach-Object { Write-WatchdogLog $_ }

if ($restoreOutput -notmatch 'Restore-only finished') {
    Write-WatchdogLog 'RestoreOnly did not finish; keeping state active for the next check'
    exit 1
}

try {
    @{
        active = $false
        recovered_at = (Get-Date).ToString('o')
        reason = 'monitor process was not running at game exit'
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $stateFile -Encoding UTF8
} catch {
    Write-WatchdogLog ('could not mark state inactive: ' + $_.Exception.Message)
}
