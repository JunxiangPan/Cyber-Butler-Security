# Launch the local Cyber-Butler dashboard with a diagnostic log.
# The WPF dashboard runs hidden from the shortcut; if it fails, show a visible
# error instead of leaving the user with a shortcut that does nothing.
param(
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $env:LOCALAPPDATA 'CyberButler'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$log = Join-Path $logDir 'dashboard-launch.log'
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $PSScriptRoot }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path

function Write-LaunchLog([string]$message) {
    try {
        Add-Content -LiteralPath $log -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message) -Encoding UTF8
    } catch { Write-Verbose 'optional operation failed' }
}

Write-LaunchLog ('launch begin root=' + $ProjectRoot)
try {
    $dashboard = Join-Path $PSScriptRoot 'cyber_butler_dashboard.ps1'
    if (-not (Test-Path -LiteralPath $dashboard)) { throw ('Dashboard script missing: ' + $dashboard) }
    & $dashboard -ProjectRoot $ProjectRoot *> $log
    Write-LaunchLog ('dashboard exit=' + $LASTEXITCODE)
} catch {
    Write-LaunchLog ('dashboard failure: ' + $_.Exception.ToString())
    try {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show(
            ("Cyber-Butler dashboard failed to open.`n`nLog: " + $log + "`n`n" + $_.Exception.Message),
            'Cyber-Butler',
            'OK',
            'Error') | Out-Null
    } catch { Write-Verbose 'optional operation failed' }
}
