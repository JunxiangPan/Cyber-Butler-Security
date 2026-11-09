#Requires -Version 5.1
<#
.SYNOPSIS
Offline dry-run for the A1 automation. Does not create a VM or elevate.
#>
[CmdletBinding()]
param(
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
$artifactRoot = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
if (-not $OutputPath) { $OutputPath = Join-Path $artifactRoot 'dry-run.json' }
$expected = @('Q05','Q06','Q07','Q08','Q09','Q10','Q11','Q12','Q13','Q14','Q15','Q16','Q17')
$checks = [System.Collections.Generic.List[object]]::new()
$failed = 0

function Add-Check([string]$name, [bool]$ok, [string]$detail) {
    $script:checks.Add([ordered]@{ name = $name; ok = $ok; detail = $detail })
    if (-not $ok) { $script:failed++ }
}

foreach ($q in $expected) {
    $path = Join-Path $PSScriptRoot ('adapters\' + $q + '.ps1')
    $exists = Test-Path $path
    Add-Check ($q + '.exists') $exists $path
    if (-not $exists) { continue }
    $text = Get-Content -Raw $path
    Add-Check ($q + '.no_scaffold') (-not ($text -match 'ADAPTER_SCAFFOLD_ONLY')) 'no scaffold marker'
    Add-Check ($q + '.params') (($text -match '\$ArtifactZip') -and ($text -match '\$Nonce') -and ($text -match '\$TimeoutMinutes')) 'required params'
    Add-Check ($q + '.blocked_exit') (($text -match 'exit 3') -and ($text -match 'BLOCKED:')) 'blocked path uses exit 3'
    $hash = (Get-FileHash $path -Algorithm SHA256).Hash
    Add-Check ($q + '.sha256') ($hash.Length -eq 64) $hash
}

$runner = Join-Path $PSScriptRoot 'Run-A1Elevated.ps1'
Add-Check 'elevated_runner.exists' (Test-Path $runner) $runner
if (Test-Path $runner) {
    $rt = Get-Content -Raw $runner
    Add-Check 'elevated_runner.fixed' (-not ($rt -match 'param\s*\([^)]*\]\$Command')) 'no generic command parameter'
    Add-Check 'elevated_runner.vm_scope' (($rt -match '\^a1-') -and (-not ($rt -match 'cbs-acceptance-vm|CBS-Test'))) 'only a1-* VMs'
}
$register = Join-Path $PSScriptRoot 'Register-A1Task.ps1'
Add-Check 'register.exists' (Test-Path $register) $register
Add-Check 'evidence.writable' (Test-Path $artifactRoot -PathType Container) $artifactRoot

$status = if ($failed -eq 0) { 'READY_TO_REGISTER' } else { 'NOT_READY' }
[ordered]@{
    status = $status
    failed = $failed
    checks = $checks
    timestamp = (Get-Date).ToUniversalTime().ToString('o')
    note = 'This is a registration readiness check, not an A1 execution result.'
} | ConvertTo-Json -Depth 5 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Output ('A1_DRY_RUN=' + $status + ' failed=' + $failed + ' output=' + $OutputPath)
if ($failed -ne 0) { exit 1 }
