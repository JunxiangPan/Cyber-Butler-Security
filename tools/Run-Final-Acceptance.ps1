#requires -Version 5.1
<#
Run-Final-Acceptance.ps1

Real-system acceptance only. No Mock/Stub/Fake is used:
  - real icacls
  - real curl.exe HTTP calls to 127.0.0.1:18090
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
    [switch]$SkipCapacity
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($ProofPath)) {
    $ProofPath = Join-Path (Get-Location) 'ACCEPTANCE_PROOF.md'
}
if ([string]::IsNullOrWhiteSpace($SharedRoot)) {
    $SharedRoot = Join-Path $env:USERPROFILE 'Desktop\大肥鱼专用文件夹'
}
New-Item -ItemType Directory -Path $SharedRoot -Force | Out-Null

$proof = New-Object System.Collections.Generic.List[string]
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
function Invoke-CurlJson([string]$uri, [string]$method = 'GET', [string]$json = '') {
    $bodyPath = Join-Path $env:TEMP ('cbs-evidence-' + [guid]::NewGuid().ToString('N') + '.json')
    if ($json) {
        [IO.File]::WriteAllText($bodyPath, $json, (New-Object Text.UTF8Encoding($false)))
    }
    $curlArgs = @('-sS', '-X', $method, $uri, '-H', ('X-Broker-Token: ' + (Read-Token)), '-w', "`nHTTP_STATUS:%{http_code}")
    if ($json) {
        $curlArgs += @('-H', 'Content-Type: application/json; charset=utf-8', '--data-binary', '@' + $bodyPath)
    }
    $raw = & curl.exe @curlArgs 2>&1 | Out-String
    $exit = $LASTEXITCODE
    Remove-Item -LiteralPath $bodyPath -Force -ErrorAction SilentlyContinue
    $status = ''
    if ($raw -match 'HTTP_STATUS:(\d{3})') { $status = $Matches[1] }
    $body = ($raw -replace '(?s)HTTP_STATUS:\d{3}\s*$', '').Trim()
    $raw = $raw.Trim() + [Environment]::NewLine + "EXIT:$exit"
    return [pscustomobject]@{ raw = $raw; body = $body; status = $status; exit = $exit }
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

Add-Proof ('# ACCEPTANCE_PROOF')
Add-Proof ('')
Add-Proof ('- Executed: ' + (Get-Date).ToUniversalTime().ToString('o'))
Add-Proof ('- Host: ' + $env:COMPUTERNAME)
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
$negTargetJson = ($negTarget -replace '\\', '\\\\')
$negReq = Invoke-CurlJson 'http://127.0.0.1:18090/request' 'POST' ('{"action":"delete","target":"' + $negTargetJson + '","reason":"negative test"}')
Add-Proof ('REQUEST RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $negReq.raw + [Environment]::NewLine + '```')
$negId = ''
try { $negId = ($negReq.body | ConvertFrom-Json).id } catch { }
if (-not $negId) { Record 'negative_setup' $false } else {
    $negVerify = Invoke-CurlJson 'http://127.0.0.1:18090/verify' 'POST' ('{"id":"' + $negId + '","code":"000000"}')
    Add-Proof ('VERIFY RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $negVerify.raw + [Environment]::NewLine + '```')
    Record 'negative_403' ($negVerify.status -eq '403' -and $negVerify.body -match 'invalid verification code')
    Record 'safe_after_negative' ((Restart-BrokerTask) -eq $true)
}

# 4. Positive TOTP + undo.
Add-Proof ''
Add-Proof '## Positive TOTP and two-stage undo'
$target = Join-Path $SharedRoot 'positive-totp.txt'
Set-Content -LiteralPath $target -Value 'positive' -Encoding UTF8
$targetJson = ($target -replace '\\', '\\\\')
$req = Invoke-CurlJson 'http://127.0.0.1:18090/request' 'POST' ('{"action":"delete","target":"' + $targetJson + '","reason":"positive test"}')
Add-Proof ('REQUEST RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $req.raw + [Environment]::NewLine + '```')
$id = ''
try { $id = ($req.body | ConvertFrom-Json).id } catch { }
if ($id) {
    $code = Get-NewTotp $id
    $verify = Invoke-CurlJson 'http://127.0.0.1:18090/verify' 'POST' ('{"id":"' + $id + '","code":"' + $code + '"}')
    Add-Proof ('VERIFY RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $verify.raw + [Environment]::NewLine + '```')
    Record 'positive_totp' ($verify.status -eq '200' -and -not (Test-Path $target))
    $TotpCode = ''
    $trash = Invoke-CurlJson 'http://127.0.0.1:18090/trash'
    Add-Proof ('TRASH RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $trash.raw + [Environment]::NewLine + '```')
    $undo = Invoke-CurlJson 'http://127.0.0.1:18090/trash/undo' 'POST' ('{"id":"' + $id + '"}')
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
    fsutil file createnew $big 629145600 | Out-Null
    $bigJson = ($big -replace '\\', '\\\\')
    $cap = Invoke-CurlJson 'http://127.0.0.1:18090/request' 'POST' ('{"action":"delete","target":"' + $bigJson + '","reason":"capacity"}')
    $capId = ''
    try { $capId = ($cap.body | ConvertFrom-Json).id } catch { }
    if ($capId) {
        $capCode = Get-NewTotp $capId
        $capVerify = Invoke-CurlJson 'http://127.0.0.1:18090/verify' 'POST' ('{"id":"' + $capId + '","code":"' + $capCode + '"}')
        Add-Proof ('CAPACITY RAW:' + [Environment]::NewLine + '```text' + [Environment]::NewLine + $capVerify.raw + [Environment]::NewLine + '```')
        Record 'capacity_block' ($capVerify.body -match 'quota' -and (Test-Path $big))
    } else {
        Record 'capacity_block' $false
    }
}

# 7. Overall only after real evidence.
$overall = $true
foreach ($key in $checks.Keys) { if (-not $checks[$key]) { $overall = $false } }
Add-Proof ''
Add-Proof '## Exit codes / checks'
$checksText = (($checks.GetEnumerator() | ForEach-Object { $_.Key + '=' + $_.Value }) -join [Environment]::NewLine)
Add-Proof ('```text' + [Environment]::NewLine + $checksText + [Environment]::NewLine + 'OVERALL=' + $(if ($overall) { 'PASS' } else { 'FAIL' }) + [Environment]::NewLine + '```')
Add-Proof ''
Add-Proof ('**Overall: ' + $(if ($overall) { 'PASS' } else { 'FAIL' }) + '**')
$proof | Set-Content -LiteralPath $ProofPath -Encoding UTF8
Write-Host ('PROOF=' + $ProofPath)
if ($overall) { Write-Host 'ACCEPTANCE_PASS'; exit 0 }
Write-Host 'ACCEPTANCE_FAIL'; exit 1
