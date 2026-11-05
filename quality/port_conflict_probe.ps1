param([Parameter(Mandatory = $true)][string]$Root)
$ErrorActionPreference = 'Stop'
. (Join-Path $Root 'installer\lib\Installer.Preflight.ps1')
$snapshot = @(Get-CyberButlerPortSnapshot -Ports @(28090, 28765))
$snapshot | ConvertTo-Json -Compress
