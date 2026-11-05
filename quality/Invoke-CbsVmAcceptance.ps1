#requires -Version 5.1
<#
One-command VM acceptance after the installer has been started/completed.
The physical phone scan is the only non-automatable step; the script prompts
once per approval and does everything else itself.

Run elevated in the VM:
  powershell -ExecutionPolicy Bypass -File .\quality\Invoke-CbsVmAcceptance.ps1
#>
[CmdletBinding()]
param(
    [string]$InstallRoot = 'C:\CyberButler',
    [string]$SharedRoot = '',
    [switch]$SkipCapacity,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$report = [ordered]@{
    started = (Get-Date).ToString('o')
    install = $false
    token_acl = $false
    totp = $false
    undo = $false
    capacity = $false
    uninstall = $false
    details = @()
}
function Add-Detail([string]$text) { $report.details += $text; Write-Host $text }
function Fail([string]$text) { Add-Detail ('FAIL: ' + $text); $report | ConvertTo-Json -Depth 5 | Set-Content 'C:\CyberButler\Public\cbs-vm-acceptance.json' -Encoding UTF8; exit 1 }
function TotpCode([string]$id) {
    $code = Read-Host "Enter current phone TOTP for $id"
    if ($code -notmatch '^[0-9]{6}$') { Fail 'TOTP must be 6 digits' }
    return $code
}
function PostJson([string]$uri, [string]$json) {
    $path = Join-Path $env:TEMP ('cbs-' + [guid]::NewGuid().ToString('N') + '.json')
    [IO.File]::WriteAllText($path, $json, (New-Object Text.UTF8Encoding($false)))
    $token = (Get-Content (Join-Path $InstallRoot 'tools\broker_token.txt') -Raw).Trim()
    $result = curl.exe -sS -X POST $uri -H "X-Broker-Token: $token" -H 'Content-Type: application/json; charset=utf-8' --data-binary "@$path"
    Remove-Item $path -Force -ErrorAction SilentlyContinue
    return $result
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'Run elevated'
}
if (-not (Test-Path (Join-Path $InstallRoot 'tools\broker_token.txt'))) { Fail 'Installation not found' }
if ([string]::IsNullOrWhiteSpace($SharedRoot)) {
    $SharedRoot = Join-Path $env:USERPROFILE 'Desktop\shared专用文件夹'
}
New-Item -ItemType Directory -Path $SharedRoot -Force | Out-Null

$version = (Get-Content (Join-Path $InstallRoot 'VERSION') -Raw).Trim()
Add-Detail ('VERSION=' + $version)
$ports = @()
foreach ($port in 18090, 8765, 8766) {
    $ports += [pscustomobject]@{ port = $port; listening = [bool](Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue) }
}
if (@($ports | Where-Object { -not $_.listening }).Count -ne 0) { Fail 'Required ports not listening' }
$report.install = $true

$acl = (& icacls.exe (Join-Path $InstallRoot 'tools\broker_token.txt') | Out-String)
if ($acl -notmatch [regex]::Escape([Security.Principal.WindowsIdentity]::GetCurrent().Name)) { Fail 'broker_token.txt is not readable by desktop user' }
$report.token_acl = $true

# TOTP delete + undo
$target = Join-Path $SharedRoot 'vm-acceptance.txt'
Set-Content -LiteralPath $target -Value 'VM acceptance' -Encoding UTF8
$targetJson = ($target -replace '\\', '\\\\')
$request = PostJson 'http://127.0.0.1:18090/request' ('{"action":"delete","target":"' + $targetJson + '","reason":"VM acceptance"}')
Add-Detail ('REQUEST=' + $request)
try { $requestObj = $request | ConvertFrom-Json } catch { Fail 'Broker request returned non-JSON' }
if (-not $requestObj.ok -or -not $requestObj.id) { Fail 'Broker did not create a pending request' }
$code = TotpCode $requestObj.id
$verify = PostJson 'http://127.0.0.1:18090/verify' ('{"id":"' + $requestObj.id + '","code":"' + $code + '"}')
Add-Detail ('VERIFY=' + $verify)
$verifyObj = $verify | ConvertFrom-Json
if (-not $verifyObj.ok) { Fail 'TOTP verification failed' }
if (Test-Path $target) { Fail 'File was not moved to two-stage trash' }
$report.totp = $true

$undo = PostJson 'http://127.0.0.1:18090/trash/undo' ('{"id":"' + $requestObj.id + '"}')
$undoObj = $undo | ConvertFrom-Json
if (-not $undoObj.ok -or -not (Test-Path $target)) { Fail 'Undo did not restore the file' }
$report.undo = $true

if (-not $SkipCapacity) {
    $big = Join-Path $SharedRoot 'vm-capacity.bin'
    fsutil file createnew $big (600 * 1024 * 1024) | Out-Null
    $bigJson = ($big -replace '\\', '\\\\')
    $cap = PostJson 'http://127.0.0.1:18090/request' ('{"action":"delete","target":"' + $bigJson + '","reason":"VM capacity"}')
    $capObj = $cap | ConvertFrom-Json
    if (-not $capObj.id) { Fail 'Capacity request was not created' }
    $capCode = TotpCode $capObj.id
    $capVerify = PostJson 'http://127.0.0.1:18090/verify' ('{"id":"' + $capObj.id + '","code":"' + $capCode + '"}')
    $capVerifyObj = $capVerify | ConvertFrom-Json
    if ($capVerifyObj.ok -or -not (Test-Path $big)) { Fail 'Capacity breaker did not block the 600MB file' }
    $report.capacity = $true
}

if ($Uninstall) {
    Add-Detail 'Uninstall must be completed in the installer GUI; verify residue manually.'
}

$report.finished = (Get-Date).ToString('o')
$report | ConvertTo-Json -Depth 5 | Set-Content 'C:\CyberButler\Public\cbs-vm-acceptance.json' -Encoding UTF8
Write-Host 'VM_ACCEPTANCE_PASS'
exit 0
