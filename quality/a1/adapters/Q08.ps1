# A1 Q08: reparse point rejection
# Exit 0 only for a real PASS; exit 3 for blocked or failed prerequisites.
param(
    [string]$ArtifactZip = '',
    [string]$Nonce = '',
    [int]$TimeoutMinutes = 20
)
$ErrorActionPreference = 'Stop'
$InstallRoot = 'C:\CyberButler'
function Blocked([string]$reason) { Write-Output ('BLOCKED:' + $reason); exit 3 }
function Pass([string]$reason) { Write-Output ('PASS:' + $reason); exit 0 }
if (-not (Test-Path $InstallRoot)) { Blocked 'QA_VM_NOT_PROVISIONED' }
if (-not (Test-Path (Join-Path $InstallRoot 'tools\broker_token.txt'))) { Blocked 'BROKER_TOKEN_MISSING' }
$token = (Get-Content (Join-Path $InstallRoot 'tools\broker_token.txt') -Raw).Trim()
$base = 'http://127.0.0.1:18090'
function Broker([string]$method, [string]$path, [string]$json = '') {
    $headers = @{ 'X-Broker-Token' = $token }
    if ($json) { return Invoke-RestMethod -Method $method -Uri ($base + $path) -Headers $headers -ContentType 'application/json' -Body $json -TimeoutSec 20 -SkipHttpErrorCheck }
    return Invoke-RestMethod -Method $method -Uri ($base + $path) -Headers $headers -TimeoutSec 20 -SkipHttpErrorCheck
}
$link = Join-Path $env:TEMP ('cbs-a1-reparse-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Junction -Path $link -Target 'C:\Windows' -ErrorAction Stop | Out-Null
try {
    $r = Broker 'POST' '/request' ('{"action":"delete","target":"' + ($link -replace '\\','\\\\') + '"}')
    if ($r.status -eq 403 -or $r.error) { Pass 'REPARSE_REJECTED' }
    Blocked 'REPARSE_NOT_REJECTED'
} finally { Remove-Item $link -Force -ErrorAction SilentlyContinue }
