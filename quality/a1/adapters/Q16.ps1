# A1 Q16: clean install prerequisites
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
if (-not $ArtifactZip -or -not (Test-Path $ArtifactZip)) { Blocked 'ARTIFACT_ZIP_MISSING' }
if (Get-Command python.exe -ErrorAction SilentlyContinue) { Blocked 'SYSTEM_PYTHON_PRESENT' }
$installer = Join-Path $InstallRoot 'installer\Install-CyberButler.ps1'
if (-not (Test-Path $installer)) { Blocked 'INSTALLER_MISSING' }
Pass 'CLEAN_INSTALL_PREREQUISITES_MET'
