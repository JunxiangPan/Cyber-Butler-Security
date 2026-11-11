# A1 Q13: TOTP replay rejection
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
    try {
        $params = @{ UseBasicParsing = $true; Method = $method; Uri = ($base + $path); Headers = $headers; TimeoutSec = 20 }
        if ($json) { $params.ContentType = 'application/json'; $params.Body = $json }
        $response = Invoke-WebRequest @params
        $obj = if ($response.Content) { $response.Content | ConvertFrom-Json } else { [pscustomobject]@{} }
        $obj | Add-Member -NotePropertyName status -NotePropertyValue ([int]$response.StatusCode) -Force
        return $obj
    } catch [System.Net.WebException] {
        $response = $_.Exception.Response
        if ($null -eq $response) { return [pscustomobject]@{ status = 0; error = 'connection failed' } }
        $reader = New-Object System.IO.StreamReader($response.GetResponseStream())
        try { $body = $reader.ReadToEnd() } finally { $reader.Dispose() }
        $obj = if ($body) { $body | ConvertFrom-Json } else { [pscustomobject]@{} }
        $obj | Add-Member -NotePropertyName status -NotePropertyValue ([int]$response.StatusCode) -Force
        return $obj
    }
}
$target = Join-Path $InstallRoot ('workspace\q13-' + [Guid]::NewGuid().ToString('N') + '.txt')
New-Item -ItemType Directory -Path (Split-Path $target) -Force | Out-Null
Set-Content -LiteralPath $target -Value 'q13' -Encoding ASCII
$body = @{ action = 'delete'; target = $target } | ConvertTo-Json -Compress
$req = Broker 'POST' '/request' $body
if (-not $req.id) { Blocked ('Q13_REQUEST_NOT_CREATED HTTP=' + [string]$req.status + ' BODY=' + ($req | ConvertTo-Json -Compress)) }
$code = $env:CBS_A1_TOTP
if (-not $code) { Blocked ('Q13_TOTP_NOT_SUPPLIED REQUEST=' + $req.id) }
$first = Broker 'POST' '/verify' ('{"id":"' + $req.id + '","code":"' + $code + '"}')
if ($first.status -ne 200) { Blocked ('Q13_FIRST_VERIFY_FAILED HTTP=' + [string]$first.status) }
$second = Broker 'POST' '/verify' ('{"id":"' + $req.id + '","code":"' + $code + '"}')
if ($second.status -in @(403, 404, 409, 410, 429)) { Pass ('TOTP_REPLAY_REJECTED FIRST=200 SECOND=' + [string]$second.status) }
Blocked ('TOTP_REPLAY_NOT_REJECTED SECOND=' + [string]$second.status)
