# One-command reference-agent demo
#
# Run from the repo root with a running CBS Broker:
#   pwsh -File examples/reference_agent/demo.ps1
#
# It creates one disposable file under the temp directory, submits one delete
# request, waits for the human approval, and prints the result. It never reads
# the TOTP secret and never bypasses the Broker.
[CmdletBinding()]
param(
    [string]$BrokerToken = '',
    [string]$BaseUrl = 'http://127.0.0.1:18090'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
if (-not $BrokerToken) {
    $candidates = @(
        'C:\CyberButler\tools\broker_token.txt',
        (Join-Path $root 'tools\broker_token.txt')
    )
    $tokenFile = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $tokenFile) { throw 'BROKER_TOKEN_NOT_FOUND: install CBS or pass -BrokerToken' }
    $BrokerToken = (Get-Content -Raw $tokenFile).Trim()
}
if (-not $BrokerToken) { throw 'BROKER_TOKEN_EMPTY' }

$demo = Join-Path $env:TEMP ('cbs-reference-demo-' + [Guid]::NewGuid().ToString('N') + '.txt')
Set-Content -Path $demo -Value 'disposable CBS reference-agent demo' -Encoding UTF8
try {
    $env:CBS_BROKER_TOKEN = $BrokerToken
    python (Join-Path $PSScriptRoot 'agent.py') $demo --base-url $BaseUrl
    if ($LASTEXITCODE -ne 0) { throw "REFERENCE_AGENT_EXIT_$LASTEXITCODE" }
} finally {
    Remove-Item -Force $demo -ErrorAction SilentlyContinue
}
