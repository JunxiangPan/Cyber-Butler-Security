# A1 Q11a: write boundary while the owner is alive
# Runs a synthetic child as CyberButlerSvc through a password-logon scheduled task.
param(
    [string]$ArtifactZip = '',
    [string]$Nonce = '',
    [int]$TimeoutMinutes = 20
)
$ErrorActionPreference = 'Stop'
$InstallRoot = 'C:\CyberButler'
function Blocked([string]$reason) { Write-Output ('BLOCKED:' + $reason); exit 3 }
function Failed([string]$reason) { Write-Output ('FAIL:' + $reason); exit 1 }
function Pass([string]$reason) { Write-Output ('PASS:' + $reason); exit 0 }
if (-not (Test-Path $InstallRoot)) { Blocked 'QA_VM_NOT_PROVISIONED' }
$svcPassword = $env:CBS_A1_SVC_PASSWORD
if ([string]::IsNullOrWhiteSpace($svcPassword)) { Blocked 'Q11A_SERVICE_CREDENTIAL_MISSING' }
$token = [Guid]::NewGuid().ToString('N')
$work = Join-Path $InstallRoot 'workspace'
$evidence = Join-Path $work "q11a-$token.json"
$childPath = Join-Path 'C:\cbs-a1' "q11a-child-$token.ps1"
$winTarget = "C:\Windows\q11a-$token.txt"
$userTarget = Join-Path $env:USERPROFILE ("q11a-$token.txt")
$allowed = Join-Path $work "q11a-allowed-$token.txt"
New-Item -ItemType Directory -Force -Path 'C:\cbs-a1' | Out-Null
New-Item -ItemType Directory -Force -Path $work | Out-Null
$child = @'
param($out,$winTarget,$userTarget,$allowed)
$result = [ordered]@{ pid = $PID; windows = $null; user = $null; allowed = $null }
try { Set-Content -LiteralPath $winTarget -Value 'x' -Encoding ASCII -ErrorAction Stop; $result.windows = 'WRITE_SUCCEEDED' } catch { $result.windows = $_.Exception.GetType().Name + ':' + $_.Exception.Message }
try { Set-Content -LiteralPath $userTarget -Value 'x' -Encoding ASCII -ErrorAction Stop; $result.user = 'WRITE_SUCCEEDED' } catch { $result.user = $_.Exception.GetType().Name + ':' + $_.Exception.Message }
try { Set-Content -LiteralPath $allowed -Value 'x' -Encoding ASCII -ErrorAction Stop; $result.allowed = 'WRITE_SUCCEEDED' } catch { $result.allowed = $_.Exception.GetType().Name + ':' + $_.Exception.Message }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $out -Encoding UTF8
'@
$child | Set-Content -LiteralPath $childPath -Encoding UTF8
$taskName = "CBS-A1-Q11A-$token"
$launchPath = Join-Path 'C:\cbs-a1' "q11a-launch-$token.ps1"
$launch = '& "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' + $childPath + '" -out "' + $evidence + '" -winTarget "' + $winTarget + '" -userTarget "' + $userTarget + '" -allowed "' + $allowed + '"'
$launch | Set-Content -LiteralPath $launchPath -Encoding UTF8
$tr = '"C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "' + $launchPath + '"'
$create = & schtasks.exe /Create /TN $taskName /TR $tr /SC ONCE /ST 23:59 /RU ("$env:COMPUTERNAME\CyberButlerSvc") /RP $svcPassword /RL LIMITED /F 2>&1
if ($LASTEXITCODE -ne 0) { Blocked ('Q11A_TASK_CREATE_FAILED: ' + (($create | Out-String).Trim())) }
try {
    & schtasks.exe /Run /TN $taskName | Out-Null
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $evidence)) { Start-Sleep -Milliseconds 250 }
    if (-not (Test-Path -LiteralPath $evidence)) { Failed 'Q11A_CHILD_EVIDENCE_MISSING' }
    $record = Get-Content -LiteralPath $evidence -Raw | ConvertFrom-Json
    $winExists = Test-Path -LiteralPath $winTarget
    $userExists = Test-Path -LiteralPath $userTarget
    $allowedExists = Test-Path -LiteralPath $allowed
    if ($winExists -or $userExists) { Failed ('UNAUTHORIZED_WRITE_CREATED win=' + $winExists + ' user=' + $userExists) }
    if (-not $allowedExists) { Failed 'ALLOWED_WRITE_FAILED' }
    Pass ('PID=' + $record.pid + ';WINDOWS=DENIED;USER=DENIED;ALLOWED=OK;TASK=OK')
} finally {
    & schtasks.exe /Delete /TN $taskName /F | Out-Null
}
