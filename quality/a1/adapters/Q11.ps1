# A1 Q11: audit log evidence (real broker event)
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
$audit = Join-Path $InstallRoot 'tools\logs'
if (-not (Test-Path $audit)) { Blocked 'AUDIT_DIR_MISSING' }
$probe = Join-Path $audit '.q11-write-probe'
try { Set-Content -LiteralPath $probe -Value 'probe' -Encoding ASCII; if (-not (Test-Path $probe)) { Blocked 'AUDIT_DIR_NOT_WRITABLE' } } finally { Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue }
try {
    $r = Invoke-WebRequest -UseBasicParsing -Method POST -Uri 'http://127.0.0.1:18090/request' -ContentType 'application/json' -Body '{"action":"delete","target":"C:\\cbs-a1\\q11.txt"}' -TimeoutSec 10
    $http = [int]$r.StatusCode
} catch [System.Net.WebException] {
    if ($null -eq $_.Exception.Response) { Blocked 'BROKER_NOT_RUNNING' }
    $http = [int]$_.Exception.Response.StatusCode
}
Start-Sleep -Seconds 1
$log = Join-Path $audit 'broker-startup.log'
if (-not (Test-Path $log)) { Blocked 'AUDIT_LOG_MISSING' }
$tail = @(Get-Content -LiteralPath $log -Tail 80 -ErrorAction SilentlyContinue)
$event = @($tail | Where-Object { $_ -match 'POST /request' -and $_ -match '40[13]' } | Select-Object -Last 1)
if ($event.Count -eq 0) { Blocked ('AUDIT_EVENT_NOT_FOUND HTTP=' + $http) }
Pass ('AUDIT_DIR=' + $audit + ';HTTP=' + $http + ';EVENT=' + $event[0])
