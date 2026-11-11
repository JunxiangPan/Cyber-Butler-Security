# A1 Q14: CBS Broker token / WebUI non-admin boundary (owner-approved redefinition)
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
$tokenPath = Join-Path $InstallRoot 'tools\broker_token.txt'
if (-not (Test-Path $tokenPath)) { Blocked 'BROKER_TOKEN_MISSING' }
$acl = Get-Acl -LiteralPath $tokenPath
$usersAce = @($acl.Access | Where-Object { [string]$_.IdentityReference -match 'Users|Authenticated Users' })
if ($usersAce.Count -gt 0) { Blocked 'BROKER_TOKEN_READABLE_BY_USERS' }
function PostRequest([string]$tokenValue) {
    $headers = @{}
    if ($tokenValue) { $headers['X-Broker-Token'] = $tokenValue }
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Method POST -Uri 'http://127.0.0.1:18090/request' -Headers $headers -ContentType 'application/json' -Body '{"action":"delete","target":"C:\\cbs-a1\\q14.txt"}' -TimeoutSec 10
        return [int]$r.StatusCode
    } catch [System.Net.WebException] {
        if ($null -eq $_.Exception.Response) { return 0 }
        return [int]$_.Exception.Response.StatusCode
    }
}
$noToken = PostRequest ''
if ($noToken -notin @(401, 403)) { Blocked ('NO_TOKEN_NOT_REJECTED HTTP=' + $noToken) }
$badToken = PostRequest 'invalid-token'
if ($badToken -notin @(401, 403)) { Blocked ('BAD_TOKEN_NOT_REJECTED HTTP=' + $badToken) }
$listeners = @(Get-NetTCPConnection -State Listen -LocalPort 18090,8765 -ErrorAction SilentlyContinue)
if ($listeners.Count -eq 0) { Blocked 'BROKER_WEBUI_NOT_LISTENING' }
$publicListen = @($listeners | Where-Object { $_.LocalAddress -notin @('127.0.0.1', '::1') })
if ($publicListen.Count -gt 0) { Blocked ('BROKER_WEBUI_PUBLIC_BIND=' + (($publicListen | ForEach-Object { $_.LocalAddress }) -join ',')) }
Pass ('NO_TOKEN_HTTP=' + $noToken + ';BAD_TOKEN_HTTP=' + $badToken + ';LISTENERS=' + $listeners.Count + ';BIND=LOOPBACK')
