param(
    [string]$Root = 'C:\CyberButler'
)

$ErrorActionPreference = 'Stop'
$logDir = Join-Path $env:SystemRoot 'System32\LogFiles\Firewall'
$logPath = Join-Path $logDir 'pfirewall.log'
$tempLog = Join-Path $env:TEMP ('cbs-wfp-tripwire-' + [guid]::NewGuid().ToString('N') + '.log')
$tempCursor = Join-Path $env:TEMP ('cbs-wfp-cursor-' + [guid]::NewGuid().ToString('N') + '.json')
$audit = Join-Path $Root 'tools\totp_broker_audit.chain.jsonl'
$python = Join-Path $Root 'AgentRuntime\.venv\Scripts\python.exe'
if (-not (Test-Path -LiteralPath $python)) { $python = 'python.exe' }

Write-Host '1) Simulated malicious egress (TEST-NET-3, no route expected)...'
try {
    $null = Test-NetConnection -ComputerName 203.0.113.1 -Port 443 -InformationLevel Quiet -WarningAction SilentlyContinue
} catch { Write-Verbose 'optional operation failed' }
Start-Sleep -Seconds 2

$source = if (Test-Path -LiteralPath $logPath) { $logPath } else { $tempLog }
if ($source -eq $tempLog) {
    Write-Host 'Firewall log not present; writing a synthetic WFP/firewall record for the parser test.'
    '2026-11-03 12:00:00 DROP TCP 10.0.0.2 203.0.113.1 50000 443 0 - - - SEND' |
        Set-Content -LiteralPath $tempLog -Encoding ASCII
}

$env:CBS_ROOT = $Root
Push-Location (Join-Path $Root 'tools')
@"
import json
from pathlib import Path
from wfp_tripwire import read_new, append_events
log = Path(r'''$source''')
cursor = Path(r'''$tempCursor''')
events = read_new(log, cursor)
append_events(Path(r'''$audit'''), events)
print(json.dumps(events, ensure_ascii=False, indent=2))
print('events=' + str(len(events)))
"@ | & $python -

Pop-Location
Remove-Item -LiteralPath $tempLog, $tempCursor -Force -ErrorAction SilentlyContinue
Write-Host ('Tripwire audit: ' + $audit)
