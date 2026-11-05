#requires -RunAsAdministrator
param(
    [string]$InstallPath = 'C:\CyberButler',
    [string]$ConfigPath = ''
)

$ErrorActionPreference = 'Stop'
$root = if ($ConfigPath) { Split-Path -Parent (Resolve-Path $ConfigPath) } else { $PSScriptRoot }
$configPath = if ($ConfigPath) { $ConfigPath } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'docs\_data\clean-vm-expected.json' }
$expected = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$result = [ordered]@{
    host = $env:COMPUTERNAME
    checked_at = (Get-Date).ToString('o')
    install_path = $InstallPath
    expected_version = $expected.version
    version = $null
    service = $null
    ports = @()
    acl_probe = $null
    wfp = $null
    installer_report = $null
    game_mode = $null
    ok = $false
    problems = @()
}

$versionPath = Join-Path $InstallPath 'VERSION'
if (Test-Path -LiteralPath $versionPath) {
    $result.version = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
    if ($result.version -ne $expected.version) { $result.problems += ('VERSION mismatch: ' + $result.version) }
} else { $result.problems += 'VERSION missing' }

$svc = Get-CimInstance Win32_Service -Filter "Name='CyberButlerAgentRuntime'" -ErrorAction SilentlyContinue
if ($svc) {
    $result.service = [ordered]@{ state = $svc.State; start_name = $svc.StartName; path = $svc.PathName }
    if ($svc.State -ne 'Running') { $result.problems += 'CyberButlerAgentRuntime is not Running' }
} else { $result.problems += 'CyberButlerAgentRuntime service missing' }

foreach ($port in @($expected.ports)) {
    $listen = @(Get-NetTCPConnection -LocalPort ([int]$port) -State Listen -ErrorAction SilentlyContinue)
    $result.ports += [ordered]@{ port = [int]$port; listening = ($listen.Count -gt 0); pid = if ($listen.Count) { $listen[0].OwningProcess } else { $null } }
    if ($listen.Count -eq 0) { $result.problems += ('port ' + $port + ' not listening') }
}

$probeCandidates = @(
    (Join-Path (Split-Path -Parent $PSScriptRoot) 'installer\Repair-AgentRuntimeACL.ps1'),
    (Join-Path $InstallPath 'installer\Repair-AgentRuntimeACL.ps1'),
    (Join-Path $InstallPath 'tools\Repair-AgentRuntimeACL.ps1')
)
$probe = $probeCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if ($probe) {
    try {
        & $probe -Root $InstallPath -ServiceAccount $svc.StartName.TrimStart('.\') -ProbeOnly
        $result.acl_probe = 'passed'
    } catch {
        $result.acl_probe = 'failed: ' + $_.Exception.Message
        $result.problems += 'service account ACL read probe failed'
    }
} else {
    $result.problems += 'Repair-AgentRuntimeACL.ps1 missing'
}

$wfp = Join-Path $InstallPath 'webui\data\wfp-guard-status.json'
if (Test-Path -LiteralPath $wfp) {
    $result.wfp = Get-Content -LiteralPath $wfp -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $result.wfp.ok) { $result.problems += 'WFP status not ok' }
} else { $result.problems += 'wfp-guard-status.json missing' }

$report = Join-Path $env:ProgramData 'CyberButler\installer-report\install-report.json'
if (Test-Path -LiteralPath $report) {
    $r = Get-Content -LiteralPath $report -Raw -Encoding UTF8 | ConvertFrom-Json
    $result.installer_report = [ordered]@{ status = $r.status; tier = $r.tier; message = $r.message }
    if ($r.status -ne 'success') { $result.problems += ('installer report status: ' + $r.status) }
} else { $result.problems += 'installer report missing' }

$gameMode = Join-Path $env:LOCALAPPDATA 'CyberButler\game-mode'
$result.game_mode = [ordered]@{ path = $gameMode; exists = (Test-Path -LiteralPath $gameMode) }
if (Test-Path -LiteralPath (Join-Path $env:USERPROFILE 'Desktop\game-mode.log')) {
    $result.problems += 'legacy desktop game-mode.log still exists'
}

$result.ok = ($result.problems.Count -eq 0)
$result | ConvertTo-Json -Depth 8
if (-not $result.ok) { exit 1 }
