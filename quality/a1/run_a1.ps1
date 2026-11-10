#Requires -RunAsAdministrator
<#
.SYNOPSIS
Run the A1 Q05-Q17 suite inside a clean Hyper-V checkpoint.
.DESCRIPTION
Each item must have quality/a1/adapters/<Qxx>.ps1. Missing adapters are
recorded as blocked, never as passed. The base checkpoint is restored after
each disruptive item.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$VMName = 'a1-cbs-clean',
    [string]$BaseSnapshot = 'a1-clean-base',
    [string]$ArtifactZip = '',
    [string]$Nonce = 'a1-local',
    [string]$OutputRoot = '',
    [int]$ItemTimeoutMinutes = 20
)

$ErrorActionPreference = 'Stop'
$items = @('Q05','Q06','Q07','Q08','Q09','Q10','Q11','Q12','Q13','Q14','Q15','Q16','Q17')
$adapterRoot = Join-Path $PSScriptRoot 'adapters'
if (-not $OutputRoot) { $OutputRoot = Join-Path $PSScriptRoot 'artifacts' }
New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$runRoot = Join-Path $OutputRoot $runId
New-Item -ItemType Directory -Force -Path $runRoot | Out-Null

function Write-Result([string]$id, [string]$status, [string]$reason, [string]$log, [string]$hash) {
    $payload = [ordered]@{ id = $id; status = $status; reason = $reason; log = $log; log_sha256 = $hash; timestamp = (Get-Date).ToUniversalTime().ToString('o') }
    $payload | ConvertTo-Json | Set-Content -Path (Join-Path $runRoot ($id + '.result.json')) -Encoding UTF8
}

$snapshot = Get-VMSnapshot -VMName $VMName -Name $BaseSnapshot -ErrorAction SilentlyContinue
if (-not $snapshot) {
    foreach ($id in $items) { Write-Result $id 'blocked' 'BASE_SNAPSHOT_MISSING' '' '' }
    throw "A1_BLOCKED: base snapshot $BaseSnapshot is missing"
}
$passwordFile = Join-Path 'D:\HyperV\qa-clones' ($VMName + '-admin.txt')
if (-not (Test-Path $passwordFile)) { throw 'A1_BLOCKED: admin password evidence file missing' }
$password = (Get-Content $passwordFile -Raw).Trim()
$artifactArg = if ($ArtifactZip) { $ArtifactZip } else { 'none' }
$secure = ConvertTo-SecureString $password -AsPlainText -Force
$cred = New-Object System.Management.Automation.PSCredential('cbsadmin', $secure)

foreach ($id in $items) {
    $adapter = Join-Path $adapterRoot ($id + '.ps1')
    $log = Join-Path $runRoot ($id + '.log')
    if (-not (Test-Path $adapter)) {
        'BLOCKED: no adapter for ' + $id | Set-Content -Path $log -Encoding UTF8
        Write-Result $id 'blocked' 'NO_ADAPTER' $log (Get-FileHash $log -Algorithm SHA256).Hash
        continue
    }
    if ($PSCmdlet.ShouldProcess($VMName, "A1 $id")) {
        Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
        Restore-VMSnapshot -VMName $VMName -Name $BaseSnapshot -Confirm:$false
        Start-VM -Name $VMName | Out-Null
        try {
            $result = Invoke-Command -VMName $VMName -Credential $cred -ScriptBlock {
                param($adapterText, $artifactZip, $nonce, $timeout)
                $path = 'C:\cbs-a1-adapter.ps1'
                Set-Content -Path $path -Value $adapterText -Encoding UTF8
                & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $path -ArtifactZip $artifactZip -Nonce $nonce -TimeoutMinutes $timeout
                exit $LASTEXITCODE
            } -ArgumentList (Get-Content -Raw $adapter), $artifactArg, $Nonce, $ItemTimeoutMinutes -ErrorAction Stop
            $result | Out-File -FilePath $log -Encoding UTF8
            $text = ($result | Out-String)
            if ($text -match 'PASS:') { $status = 'passed'; $reason = 'PASS' }
            elseif ($text -match 'BLOCKED:') { $status = 'blocked'; $reason = 'BLOCKED' }
            else { $status = 'failed'; $reason = 'NO_PASS_OR_BLOCKED_MARKER' }
            Write-Result $id $status $reason $log (Get-FileHash $log -Algorithm SHA256).Hash
        } catch {
            $_.Exception.Message | Out-File -FilePath $log -Encoding UTF8
            Write-Result $id 'failed' 'EXCEPTION' $log (Get-FileHash $log -Algorithm SHA256).Hash
        }
    }
}

$summary = Get-ChildItem $runRoot -Filter '*.result.json' | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json }
$summary | ConvertTo-Json -Depth 5 | Set-Content -Path (Join-Path $runRoot 'summary.json') -Encoding UTF8
$passed = @($summary | Where-Object status -eq 'passed').Count
$blocked = @($summary | Where-Object status -eq 'blocked').Count
Write-Output "A1_RESULT passed=$passed blocked=$blocked root=$runRoot"
