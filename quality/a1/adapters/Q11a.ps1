# A1 Q11a: write boundary while the owner is alive
# Runs a synthetic child as CyberButlerSvc and checks unauthorized writes.
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
$cred = New-Object System.Management.Automation.PSCredential("$env:COMPUTERNAME\CyberButlerSvc", (ConvertTo-SecureString $svcPassword -AsPlainText -Force))
$token = [Guid]::NewGuid().ToString('N')
$out = "C:\cbs-a1\evidence\q11a-$token.json"
$winTarget = "C:\Windows\q11a-$token.txt"
$userTarget = "C:\Users\Public\q11a-$token.txt"
$allowed = "C:\CyberButler\workspace\q11a-$token.txt"
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path $allowed) | Out-Null
$child = @'
param($out,$winTarget,$userTarget,$allowed)
$result = [ordered]@{ pid = $PID; windows = $null; user = $null; allowed = $null; errors = @() }
try { Set-Content -LiteralPath $winTarget -Value 'x' -Encoding ASCII -ErrorAction Stop; $result.windows = 'WRITE_SUCCEEDED' } catch { $result.windows = $_.Exception.GetType().Name + ':' + $_.Exception.Message }
try { Set-Content -LiteralPath $userTarget -Value 'x' -Encoding ASCII -ErrorAction Stop; $result.user = 'WRITE_SUCCEEDED' } catch { $result.user = $_.Exception.GetType().Name + ':' + $_.Exception.Message }
try { Set-Content -LiteralPath $allowed -Value 'x' -Encoding ASCII -ErrorAction Stop; $result.allowed = 'WRITE_SUCCEEDED' } catch { $result.allowed = $_.Exception.GetType().Name + ':' + $_.Exception.Message }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $out -Encoding UTF8
'@
$childPath = "C:\cbs-a1\q11a-child-$token.ps1"
$child | Set-Content -LiteralPath $childPath -Encoding UTF8
try {
    $p = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -Credential $cred -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$childPath,'-out',$out,'-winTarget',$winTarget,'-userTarget',$userTarget,'-allowed',$allowed) -Wait -PassThru -WindowStyle Hidden
} catch {
    Blocked ('Q11A_SERVICE_LOGON_DENIED: ' + $_.Exception.Message)
}
Start-Sleep -Seconds 1
$record = if (Test-Path $out) { Get-Content -LiteralPath $out -Raw | ConvertFrom-Json } else { $null }
$winExists = Test-Path $winTarget
$userExists = Test-Path $userTarget
$allowedExists = Test-Path $allowed
if ($winExists -or $userExists) { Failed ('UNAUTHORIZED_WRITE_CREATED win=' + $winExists + ' user=' + $userExists) }
if (-not $allowedExists) { Failed 'ALLOWED_WRITE_FAILED' }
if ($null -eq $record) { Failed 'CHILD_EVIDENCE_MISSING' }
Pass ('PID=' + $record.pid + ';WINDOWS=DENIED;USER=DENIED;ALLOWED=OK;EXIT=' + $p.ExitCode)
