[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$VMName,
    [string]$SnapshotName = 'cbs-pre-v1.7'
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Checkpoint-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not available'
}
if ($PSCmdlet.ShouldProcess($VMName, "checkpoint $SnapshotName")) {
    Checkpoint-VM -Name $VMName -SnapshotName $SnapshotName
}
if ($PSCmdlet.ShouldProcess($VMName, "restore $SnapshotName")) {
    Restore-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false
}
Write-Host 'VM_SNAPSHOT_WHATIF_OK'
