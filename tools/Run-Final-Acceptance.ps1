#requires -Version 5.1
<#
Run-Final-Acceptance.ps1

Real-system acceptance only. No Mock/Stub/Fake is used:
  - real icacls
  - real Python urllib HTTP calls to 127.0.0.1:18090
  - real Test-Path / Get-Content / Get-CimInstance
  - real negative test with an invalid TOTP (must return 403)
  - real audit.jsonl and process evidence

The physical phone TOTP is the only prompt. The script writes
ACCEPTANCE_PROOF.md only after execution; it never embeds a PASS constant.
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\CyberButler',
    [string]$SharedRoot = '',
    [string]$ProofPath = '',
    [string]$TotpCode = '',
    [string]$Nonce = '',
    [string]$Challenge = '',
    [string]$PackageZip = '',
    [string]$CommitSha = '',
    [switch]$SkipCapacity
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProofPath)) {
    $ProofPath = Join-Path (Get-Location) 'ACCEPTANCE_PROOF.md'
}
if ([string]::IsNullOrWhiteSpace($CommitSha)) { $CommitSha = $env:GITHUB_SHA }
if ($CommitSha -and $CommitSha -notmatch '^[0-9a-fA-F]{40}$') { throw 'CommitSha must be 40 hex characters' }
if ([string]::IsNullOrWhiteSpace($SharedRoot)) {
    $SharedRoot = Join-Path $InstallRoot 'workspace'
}
New-Item -ItemType Directory -Path $SharedRoot -Force | Out-Null

$proof = New-Object System.Collections.Generic.List[string]
$scriptPath = $PSCommandPath
$scriptHashStart = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
Set-ItemProperty -LiteralPath $scriptPath -Name IsReadOnly -Value $true
if ([string]::IsNullOrWhiteSpace($Nonce)) { $Nonce = Read-Host 'Enter a random nonce for this run' }
if ($Challenge -and $Nonce -cne $Challenge) { throw 'Nonce must equal the challenge passed to Run-ReleasePipeline' }
if ($Nonce.Length -lt 16) { throw 'Nonce must be at least 16 characters' }
$hasDigit = $Nonce -match '[0-9]'
$hasLetter = $Nonce -match '[A-Za-z]'
$hasSymbol = $Nonce -match '[^A-Za-z0-9]'
if (([int]$hasDigit + [int]$hasLetter + [int]$hasSymbol) -lt 2) { throw 'Nonce must contain at least two character classes' }
$historyDir = Join-Path $env:ProgramData 'CyberButler'
if (-not (Test-Path -LiteralPath $historyDir)) { $historyDir = Join-Path $env:LOCALAPPDATA 'CyberButler' }
New-Item -ItemType Directory -Path $historyDir -Force | Out-Null
$historyPath = Join-Path $historyDir 'nonce_history.txt'
if (Test-Path -LiteralPath $historyPath) {
    $recent = @(Get-Content -LiteralPath $historyPath -Encoding UTF8 | Select-Object -Last 30)
    foreach ($entry in $recent) {
        if ($entry.Split([char]124)[0] -ceq $Nonce) { throw 'Nonce was already used in the last 30 runs' }
    }
}
$checks = [ordered]@{}
function Add-Proof([string]$text) {
    $proof.Add($text)
    Write-Host $text
}
function Record([string]$name, [bool]$ok) {
    $checks[$name] = $ok
}
function Read-Token() {
    return (Get-Content -LiteralPath (Join-Path $InstallRoot 'tools\broker_token.txt') -Raw).Trim()
}
<#
.SYNOPSIS
    Sends a JSON request to the local Broker with UTF-8 bytes and no temp file.
#>
function Invoke-BrokerJson([string]$uri, [string]$method = 'GET', [string]$json = '', [string]$token = '') {
    if ([string]::IsNullOrWhiteSpace($token)) { $token = Read-Token }
    $python = Join-Path $InstallRoot 'webui\.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $python)) { $python = (Get-Command python.exe -ErrorAction Stop).Source }
    $helper = Join-Path $PSScriptRoot 'acceptance_http.py'
    if (-not (Test-Path -LiteralPath $helper)) { throw 'acceptance_http.py is missing' }
    $oldUrl = $env:CBS_ACCEPTANCE_URL
    $oldMethod = $env:CBS_ACCEPTANCE_METHOD
    $oldBody = $env:CBS_ACCEPTANCE_BODY
    $oldToken = $env:CBS_ACCEPTANCE_TOKEN
    try {
        $env:CBS_ACCEPTANCE_URL = $uri
        $env:CBS_ACCEPTANCE_METHOD = $method
        $env:CBS_ACCEPTANCE_BODY = $json
        $env:CBS_ACCEPTANCE_TOKEN = $token
        $output = (& $python $helper 2>&1 | Out-String).Trim()
    } finally {
        $env:CBS_ACCEPTANCE_URL = $oldUrl
        $env:CBS_ACCEPTANCE_METHOD = $oldMethod
        $env:CBS_ACCEPTANCE_BODY = $oldBody
        $env:CBS_ACCEPTANCE_TOKEN = $oldToken
    }
    try {
        $parsed = $output | ConvertFrom-Json
    } catch {
        return [pscustomobject]@{ raw = $output; body = $output; status = '0'; exit = 1 }
    }
    return [pscustomobject]@{
        raw = [string]$parsed.raw
        body = [string]$parsed.body
        status = [string]$parsed.status
        exit = [int]$parsed.exit
    }
}
function Restart-BrokerTask() {
    $listener = Get-NetTCPConnection -LocalPort 18090 -State Listen -ErrorAction SilentlyContinue
    Stop-ScheduledTask -TaskName 'Cyber-Butler Broker' -ErrorAction SilentlyContinue
    if ($listener) { Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue }
    Start-Sleep -Seconds 3
    Start-ScheduledTask -TaskName 'Cyber-Butler Broker'
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (Get-NetTCPConnection -LocalPort 18090 -State Listen -ErrorAction SilentlyContinue) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}
function Get-NewTotp([string]$id) {
    if (-not $TotpCode) {
        $TotpCode = Read-Host "Enter current phone TOTP for request $id"
    }
    return $TotpCode
}

<#
.SYNOPSIS
    Verify one TOTP, retrying after the broker's replay-protection window.
.DESCRIPTION
    A 429 or "replay rejected" is expected when the same 30-second code is reused.
    Wait 35 seconds, ask for the new phone code, and retry; never count the 429 as
    a capacity or positive-test failure.
#>
function Invoke-TotpVerifyWithRetry {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [string]$Label = 'TOTP'
    )
    $code = ''
    $response = $null
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        if (-not $code) { $code = Read-Host "Enter current phone TOTP for $Label request $Id" }
        $payload = [ordered]@{ id = $Id; code = $code } | ConvertTo-Json -Compress
        $response = Invoke-BrokerJson 'http://127.0.0.1:18090/verify' 'POST' $payload
        Add-Proof ("$Label VERIFY RAW (attempt $attempt):" + [Environment]::NewLine + '```text' + [Environment]::NewLine + $response.raw + [Environment]::NewLine + '```')
        if ($response.status -eq '429' -or $response.body -match 'replay rejected') {
            Add-Proof ("$Label TOTP replay guard: HTTP 429; waiting 35 seconds for a fresh code")
            Write-Host 'TOTP 已被防重放机制拦截，等待 35 秒获取新码...'
            Start-Sleep -Seconds 35
            $code = ''
            continue
        }
        return $response
    }
    return $response
}

Add-Proof ('# ACCEPTANCE_PROOF')
Add-Proof ('')
Add-Proof ('- Executed: ' + (Get-Date).ToUniversalTime().ToString('o'))
Add-Proof ('- Host: ' + $env:COMPUTERNAME)
Add-Proof ('- Commit SHA: ' + $CommitSha)
Add-Proof ('- Nonce: ' + $Nonce)
Add-Proof ('- Acceptance script SHA256 (start): ' + $scriptHashStart)
$macs = @(Get-NetAdapter | Select-Object -ExpandProperty MacAddress)
Add-Proof ('- MAC: ' + ($macs -join ', '))
$version = (Get-Content (Join-Path $InstallRoot 'VERSION') -Raw).Trim()
Add-Proof ('- VERSION: ' + $version)
$package = Get-ChildItem -Path (Join-Path $env:USERPROFILE 'Downloads') -Filter 'public-release-v1.6.3.zip' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($package) {
    Add-Proof ('- Package SHA256: ' + (Get-FileHash $package.FullName -Algorithm SHA256).Hash)
}
$reportPath = 'C:\ProgramData\CyberButler\installer-report\install-report.json'
if (Test-Path $reportPath) {
    $report = Get-Content $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Proof ('- Install report: ' + $report.status)
    Record 'install_report' ($report.status -eq 'success')
} else {
    Add-Proof '- Install report: MISSING'
    Record 'install_report' $false
}

# 1. Real icacls evidence.
Add-Proof ''
Add-Proof '## icacls broker_token.txt'
$tokenPath = Join-Path $InstallRoot 'tools\broker_token.txt'
$acl = & icacls.exe $tokenPath 2>&1 | Out-String
Add-Proof ('```text' + [Environment]::NewLine + $acl.Trim() + [Environment]::NewLine + '```')
Record 'icacls_token' ($LASTEXITCODE -eq 0 -and $acl -match [regex]::Escape([Security.Principal.WindowsIdentity]::GetCurrent().Name))
try {
    $tokenLength = (Read-Token).Length
    Record 'token_readback' ($tokenLength -gt 0)
    Add-Proof ('- Token readback length: ' + $tokenLength)
} catch {
    Record 'token_readback' $false
    Add-Proof ('- Token readback error: ' + $_.Exception.Message)
}

# 2. Real process evidence.
Add-Proof ''
Add-Proof '## Win32_Process evidence'
$processes = @(Get-CimInstance Win32_Process | Where-Object {
    $_.CommandLine -and ($_.CommandLine -match 'broker\.py|webui|wfp_guard')
} | Select-Object ProcessId,Name,CommandLine)
foreach ($p in $processes) {
    Add-Proof ('- PID=' + $p.ProcessId + ' NAME=' + $p.Name + ' CMD=' + $p.CommandLine)
}
Record 'process_evidence' ($processes.Count -ge 1)

# 3. Negative test: wrong TOTP must be 403.
Add-Proof ''
Add-Proof '## Negative test: wrong TOTP must be rejected'
$negTarget = Join-Path $SharedRoot 'negative-totp.txt'
Set-Content -LiteralPath $negTarget -Value 'negative' -Encoding UTF8
$negRequest = [ordered]@{ action = 'delete'; target = $negTarget; reason = 'negative test' } | ConvertTo-Json -Compress
$negReq = Invoke-BrokerJson 'http://127.0.0.1:18090/request' 'POST' $negRequest
Add-Proof ('REQUEST RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $negReq.raw + [Environment]::NewLine + '```')
$negId = ''
try { $negId = ($negReq.body | ConvertFrom-Json).id } catch { Write-Verbose 'response had no id' }
if (-not $negId) { Record 'negative_setup' $false } else {
    $negVerifyJson = [ordered]@{ id = $negId; code = '000000' } | ConvertTo-Json -Compress
    $negVerify = Invoke-BrokerJson 'http://127.0.0.1:18090/verify' 'POST' $negVerifyJson
    Add-Proof ('VERIFY RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $negVerify.raw + [Environment]::NewLine + '```')
    Record 'negative_403' ($negVerify.status -eq '403' -and $negVerify.body -match 'invalid verification code')
    $forgedJson = [ordered]@{ action = 'delete'; target = 'C:\Windows\System32\drivers\etc\hosts' } | ConvertTo-Json -Compress
    $forgedReq = Invoke-BrokerJson 'http://127.0.0.1:18090/request' 'POST' $forgedJson 'deadbeef'
    $forgedRaw = $forgedReq.raw
    Add-Proof ('FORGED TOKEN RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $forgedRaw.Trim() + [Environment]::NewLine + '```')
    Record 'negative_token' ($forgedRaw -match 'HTTP_STATUS:403')
    Record 'safe_after_negative' ((Restart-BrokerTask) -eq $true)

# Wrong-path negative test: must be denied, never 200.
$badJson = [ordered]@{ action = 'delete'; target = 'C:\Windows\System32\drivers\etc\hosts'; reason = 'negative path' } | ConvertTo-Json -Compress
$bad = Invoke-BrokerJson 'http://127.0.0.1:18090/request' 'POST' $badJson
Add-Proof ('WRONG_PATH RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $bad.raw + [Environment]::NewLine + '```')
Record 'negative_path' ($bad.status -ne '200' -and $bad.body -notmatch '"ok"\s*:\s*true')
}

# 4. Positive TOTP + undo.
Add-Proof ''
Add-Proof '## Positive TOTP and two-stage undo'
$target = Join-Path $SharedRoot 'positive-totp.txt'
Set-Content -LiteralPath $target -Value 'positive' -Encoding UTF8
$targetRequest = [ordered]@{ action = 'delete'; target = $target; reason = 'positive test' } | ConvertTo-Json -Compress
$req = Invoke-BrokerJson 'http://127.0.0.1:18090/request' 'POST' $targetRequest
Add-Proof ('REQUEST RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $req.raw + [Environment]::NewLine + '```')
$id = ''
try { $id = ($req.body | ConvertFrom-Json).id } catch { Write-Verbose 'response had no id' }
if ($id) {
    $verify = Invoke-TotpVerifyWithRetry -Id $id -Label 'positive'
    Add-Proof ('VERIFY RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $verify.raw + [Environment]::NewLine + '```')
    Record 'positive_totp' ($verify.status -eq '200' -and -not (Test-Path $target))
    $TotpCode = ''
    $trash = Invoke-BrokerJson 'http://127.0.0.1:18090/trash'
    Add-Proof ('TRASH RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $trash.raw + [Environment]::NewLine + '```')
    $undoJson = [ordered]@{ id = $id } | ConvertTo-Json -Compress
    $undo = Invoke-BrokerJson 'http://127.0.0.1:18090/trash/undo' 'POST' $undoJson
    Add-Proof ('UNDO RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $undo.raw + [Environment]::NewLine + '```')
    Record 'undo' ($undo.status -eq '200' -and (Test-Path $target))
}

# 5. Real audit evidence.
Add-Proof ''
Add-Proof '## audit.jsonl evidence'
$auditPath = Join-Path $InstallRoot 'tools\totp_broker_audit.jsonl'
if (Test-Path $auditPath) {
    $audit = Get-Content $auditPath -Tail 5 -Encoding UTF8
    Add-Proof ('```jsonl' + [Environment]::NewLine + (($audit -join [Environment]::NewLine)) + [Environment]::NewLine + '```')
    Record 'audit_evidence' ($audit.Count -gt 0)
} else {
    Record 'audit_evidence' $false
}

# 6. Capacity negative test (optional).
if (-not $SkipCapacity) {
    Add-Proof ''
    Add-Proof '## Capacity breaker'
    $big = Join-Path $SharedRoot 'capacity-600mb.bin'
    fsutil file createnew $big (600 * 1024 * 1024) | Out-Null
$capJson = [ordered]@{ action = 'delete'; target = $big; reason = 'capacity' } | ConvertTo-Json -Compress
$cap = Invoke-BrokerJson 'http://127.0.0.1:18090/request' 'POST' $capJson
    $capId = ''
    try { $capId = ($cap.body | ConvertFrom-Json).id } catch { Write-Verbose 'response had no id' }
    if ($capId) {
        $capVerify = Invoke-TotpVerifyWithRetry -Id $capId -Label 'capacity'
        Add-Proof ('CAPACITY RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $capVerify.raw + [Environment]::NewLine + '```')
        Record 'capacity_block' ($capVerify.body -match 'quota' -and (Test-Path $big))
    } else {
        Record 'capacity_block' $false
    }
}

# Cleanup test artifacts so no 600 MB file is left on disk.
foreach ($cleanupPath in @($big, $negTarget, $target)) {
    if ($cleanupPath -and (Test-Path -LiteralPath $cleanupPath)) {
        Remove-Item -LiteralPath $cleanupPath -Force -ErrorAction SilentlyContinue
    }
}

# 7. Validate this script was not modified while running.
$scriptHashEnd = (Get-FileHash -LiteralPath $scriptPath -Algorithm SHA256).Hash
Record 'script_immutable' ($scriptHashStart -eq $scriptHashEnd)
Add-Proof ('- Acceptance script SHA256 (end): ' + $scriptHashEnd)

# 8. Overall only after real evidence.
$overall = $true
foreach ($key in $checks.Keys) { if (-not $checks[$key]) { $overall = $false } }
Add-Proof ''
Add-Proof '## Exit codes / checks'
$checksText = (($checks.GetEnumerator() | ForEach-Object { $_.Key + '=' + $_.Value }) -join [Environment]::NewLine)
Add-Proof ('```text' + [Environment]::NewLine + $checksText + [Environment]::NewLine + 'OVERALL=' + $(if ($overall) { 'PASS' } else { 'FAIL' }) + [Environment]::NewLine + '```')
Add-Proof ''
Add-Proof ('**Overall: ' + $(if ($overall) { 'PASS' } else { 'FAIL' }) + '**')
$proof | Set-Content -LiteralPath $ProofPath -Encoding UTF8
$proofHash = (Get-FileHash -LiteralPath $ProofPath -Algorithm SHA256).Hash
Write-Host ('PROOF=' + $ProofPath)
Write-Host ('PROOF_SHA256=' + $proofHash)
$packageHash = 'N/A'
if ([string]::IsNullOrWhiteSpace($PackageZip)) {
    $candidate = Join-Path (Get-Location) 'public-release-v1.6.3.zip'
    if (Test-Path -LiteralPath $candidate) { $PackageZip = $candidate }
}
if ($PackageZip -and (Test-Path -LiteralPath $PackageZip)) {
    $packageHash = (Get-FileHash -LiteralPath $PackageZip -Algorithm SHA256).Hash
}
Add-Content -LiteralPath $historyPath -Value ($Nonce + '|' + (Get-Date).ToUniversalTime().ToString('o') + '|' + $packageHash) -Encoding UTF8
$buildReport = Join-Path (Get-Location) 'BUILD_REPORT.md'
if (Test-Path -LiteralPath $buildReport) {
    $seal = [Environment]::NewLine + '## PROOF SEAL' + [Environment]::NewLine + '- PROOF_SHA256: `' + $proofHash + '`' + [Environment]::NewLine
    Add-Content -LiteralPath $buildReport -Value $seal -Encoding UTF8
}
if ($overall) { Write-Host 'ACCEPTANCE_PASS'; exit 0 }
Write-Host 'ACCEPTANCE_FAIL'; exit 1
