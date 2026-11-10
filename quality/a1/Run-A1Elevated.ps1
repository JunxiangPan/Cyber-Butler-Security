#Requires -RunAsAdministrator
<#
.SYNOPSIS
Fixed elevated A1 entrypoint. No arguments are accepted.
.DESCRIPTION
Provision a1-cbs-clean from the approved ISO, run adapters, write artifacts.
Only a1-* VMs under D:\HyperV\qa-clones are touched.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$artifactRoot = Join-Path $PSScriptRoot 'artifacts'
$deployMarker = Join-Path $artifactRoot 'deploy-wim-request.json'
if (Test-Path $deployMarker) {
    & (Join-Path $PSScriptRoot 'deploy_wim_vhdx.ps1')
    exit $LASTEXITCODE
}
$vmRoot = 'D:\HyperV\qa-clones'
$vmName = 'a1-cbs-clean'
$iso = 'D:\iso\Windows11_Client_x64_zh-cn_26300_9457.iso'
$snapshot = 'a1-clean-base'
$runId = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$taskJson = Join-Path $artifactRoot ('task-' + $runId + '.json')
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null

function Write-Task([string]$status, [string]$reason) {
    [ordered]@{
        task = 'CBS-A1-Elevated'
        run_id = $runId
        status = $status
        reason = $reason
        vm = $vmName
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
        artifacts = $artifactRoot
    } | ConvertTo-Json | Set-Content -Path $taskJson -Encoding UTF8
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Task 'blocked' 'ELEVATION_REQUIRED'
    exit 1
}
if ($vmName -notmatch '^a1-') {
    Write-Task 'blocked' 'VM_NAME_NOT_ALLOWED'
    exit 1
}
if (-not (Test-Path $iso)) {
    Write-Task 'blocked' 'ISO_NOT_FOUND'
    exit 1
}

$vm = Get-VM -Name $vmName -ErrorAction SilentlyContinue
if (-not $vm) {
    $provision = Join-Path $PSScriptRoot 'provision_clean_vm.ps1'
    & $provision -IsoPath $iso -VMName $vmName -VhdDirectory $vmRoot -SwitchName 'CBS-NAT' -CpuCount 4 -MemoryBytes 8GB
    if ($LASTEXITCODE -ne 0 -or -not (Get-VMSnapshot -VMName $vmName -Name $snapshot -ErrorAction SilentlyContinue)) {
        Write-Task 'blocked' 'PROVISION_FAILED'
        exit 1
    }
}
if (-not (Get-VMSnapshot -VMName $vmName -Name $snapshot -ErrorAction SilentlyContinue)) {
    Write-Task 'blocked' 'BASE_SNAPSHOT_MISSING'
    exit 1
}

$runner = Join-Path $PSScriptRoot 'run_a1.ps1'
& $runner -VMName $vmName -BaseSnapshot $snapshot -ArtifactZip '' -Nonce ('a1-' + $runId) -OutputRoot $artifactRoot
$code = $LASTEXITCODE
$summary = Get-ChildItem $artifactRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$results = @()
if ($summary) {
    $results = Get-ChildItem $summary.FullName -Filter '*.result.json' -ErrorAction SilentlyContinue |
        ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json }
}
$passed = @($results | Where-Object status -eq 'passed').Count
$blocked = @($results | Where-Object status -eq 'blocked').Count
$failed = @($results | Where-Object status -eq 'failed').Count
$status = if ($code -eq 0 -and $failed -eq 0 -and $blocked -eq 0) { 'passed' } elseif ($blocked -gt 0) { 'blocked' } else { 'failed' }
$payload = [ordered]@{
    task = 'CBS-A1-Elevated'
    run_id = $runId
    status = $status
    passed = $passed
    blocked = $blocked
    failed = $failed
    exit_code = $code
    vm = $vmName
    snapshot = $snapshot
    results = $results
}
$payload | ConvertTo-Json -Depth 8 | Set-Content -Path $taskJson -Encoding UTF8
if ($status -ne 'passed') { exit 1 }
