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
$pool = [runspacefactory]::CreateRunspacePool(1, 20)
$pool.Open()
$items = @()
try {
    1..20 | ForEach-Object {
        $ps = [powershell]::Create()
        $ps.RunspacePool = $pool
        [void]$ps.AddScript({
            param($url)
            try {
                $r = Invoke-WebRequest -UseBasicParsing -Uri ($url + '/health') -TimeoutSec 15
                $body = $r.Content | ConvertFrom-Json
                return [pscustomobject]@{ status = $body.status; http = [int]$r.StatusCode }
            } catch {
                return [pscustomobject]@{ status = $null; http = 0; error = $_.Exception.Message }
            }
        }).AddArgument($base)
        $items += [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
    }
    $results = @()
    foreach ($item in $items) {
        try { $results += $item.PS.EndInvoke($item.Handle) } catch { $results += [pscustomobject]@{ status = $null; http = 0; error = $_.Exception.Message } }
    }
} finally {
    foreach ($item in $items) { try { $item.PS.Dispose() } catch {} }
    $pool.Close(); $pool.Dispose()
}
$bad = @($results | Where-Object { $_.status -ne 'ok' -or $_.http -ne 200 })
if ($results.Count -ne 20) { Blocked ('CONCURRENCY_RESULT_COUNT=' + $results.Count) }
if ($bad.Count -gt 0) { Blocked ('HEALTH_NOT_STABLE_UNDER_CONCURRENCY count=' + $bad.Count + ' of 20') }
Pass 'CONCURRENT_HEALTH_STABLE_20'
