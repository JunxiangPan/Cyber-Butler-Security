#Requires -RunAsAdministrator
<#
.SYNOPSIS
Remove an A1 VM only when explicitly requested; keep evidence by default.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$VMName = 'cbs-a1-clean',
    [switch]$RemoveVM,
    [switch]$RemoveSnapshots
)

$ErrorActionPreference = 'Stop'
$evidence = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $evidence | Out-Null

if ($RemoveSnapshots) {
    Get-VMSnapshot -VMName $VMName -ErrorAction SilentlyContinue |
        Where-Object Name -like 'a1-*' |
        ForEach-Object { Remove-VMSnapshot -VMName $VMName -Name $_.Name -Confirm:$false }
}

if ($RemoveVM) {
    if ($PSCmdlet.ShouldProcess($VMName, 'remove A1 VM')) {
        Stop-VM -Name $VMName -Force -ErrorAction SilentlyContinue
        Remove-VM -Name $VMName -Force
        $vhd = Join-Path 'D:\HyperV\qa-clones' ($VMName + '.vhdx')
        if (Test-Path $vhd) { Remove-Item -Force $vhd }
        $password = Join-Path 'D:\HyperV\qa-clones' ($VMName + '-admin.txt')
        if (Test-Path $password) { Remove-Item -Force $password }
    }
}

[ordered]@{
    vm = $VMName
    vm_removed = [bool]$RemoveVM
    snapshots_removed = [bool]$RemoveSnapshots
    evidence_retained = $evidence
} | ConvertTo-Json | Set-Content -Path (Join-Path $evidence 'teardown-result.json') -Encoding UTF8
