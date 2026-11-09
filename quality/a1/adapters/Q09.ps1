# A1 Q09: concurrent request health
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
$hits = 1..20 | ForEach-Object -Parallel { (Invoke-RestMethod -Method Get -Uri ($using:base + '/health') -TimeoutSec 5).status } -ThrottleLimit 10
if (@($hits | Where-Object { $_ -ne 'ok' }).Count -gt 0) { Blocked 'HEALTH_NOT_STABLE_UNDER_CONCURRENCY' }
Pass 'CONCURRENT_HEALTH_STABLE'
