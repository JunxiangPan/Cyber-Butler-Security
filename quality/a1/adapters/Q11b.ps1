# A1 Q11b: owner termination cleans the Job Object child tree
# Owner is a synthetic process holding a KILL_ON_JOB_CLOSE job; this is not a write test.
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
$helperExe = 'C:\cbs-a1\job_owner.exe'
$helper = 'C:\cbs-a1\job_owner.ps1'
if (-not (Test-Path $helperExe) -and -not (Test-Path $helper)) { Blocked 'Q11B_JOB_OWNER_HELPER_MISSING' }
$token = [Guid]::NewGuid().ToString('N')
$evidence = Join-Path 'C:\cbs-a1\evidence' "q11b-owner-$token.json"
New-Item -ItemType Directory -Force -Path (Split-Path $evidence) | Out-Null
if (Test-Path $helperExe) {
    $owner = Start-Process -FilePath $helperExe -ArgumentList @($evidence) -PassThru -WindowStyle Hidden
} else {
    $owner = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$helper,'-Evidence',$evidence,'-ChildLog',(Join-Path 'C:\cbs-a1' "q11b-child-$token.log")) -PassThru -WindowStyle Hidden
}
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline -and -not (Test-Path $evidence)) { Start-Sleep -Milliseconds 250 }
if (-not (Test-Path $evidence)) { Stop-Process -Id $owner.Id -Force -ErrorAction SilentlyContinue; Failed 'Q11B_OWNER_EVIDENCE_MISSING' }
$record = Get-Content -LiteralPath $evidence -Raw | ConvertFrom-Json
$childPid = [int]$record.child_pid
if ($childPid -le 0) { Failed 'Q11B_CHILD_PID_INVALID' }
Stop-Process -Id $owner.Id -Force -ErrorAction Stop
$gone = $false
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500
    if (-not (Get-Process -Id $childPid -ErrorAction SilentlyContinue)) { $gone = $true; break }
}
if (-not $gone) { Failed ('Q11B_ORPHAN child=' + $childPid + ' owner=' + $owner.Id) }
Pass ('OWNER=' + $owner.Id + ';CHILD=' + $childPid + ';CLEANED=YES;WAIT_MS=' + ($i * 500))
