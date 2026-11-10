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
$base = 'http://127.0.0.1:18090'
$jobs = @()
1..20 | ForEach-Object {
    $jobs += Start-Job -ScriptBlock {
        param($url)
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri ($url + '/health') -TimeoutSec 10
            $body = $r.Content | ConvertFrom-Json
            return [pscustomobject]@{ status = $body.status; http = [int]$r.StatusCode }
        } catch {
            return [pscustomobject]@{ status = $null; http = 0; error = $_.Exception.Message }
        }
    } -ArgumentList $base
}
$null = Wait-Job -Job $jobs -Timeout 45
$results = @($jobs | Receive-Job -ErrorAction SilentlyContinue)
$jobs | Remove-Job -Force -ErrorAction SilentlyContinue
$bad = @($results | Where-Object { $_.status -ne 'ok' -or $_.http -ne 200 })
if ($bad.Count -gt 0) {
    Blocked ('HEALTH_NOT_STABLE_UNDER_CONCURRENCY count=' + $bad.Count + ' of 20')
}
if ($results.Count -ne 20) {
    Blocked ('CONCURRENCY_RESULT_COUNT=' + $results.Count)
}
Pass 'CONCURRENT_HEALTH_STABLE_20'
