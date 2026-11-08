[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$VMName,
    [string]$SnapshotName = 'cbs-pre-v1.7',
    [switch]$Restore,
    [switch]$Rollback
)
$ErrorActionPreference = 'Stop'
if (-not (Get-Command Checkpoint-VM -ErrorAction SilentlyContinue)) {
    throw 'Hyper-V PowerShell module not available'
}
if ($Restore -or $Rollback) {
    if ($PSCmdlet.ShouldProcess($VMName, "restore $SnapshotName")) {
        Restore-VMSnapshot -VMName $VMName -Name $SnapshotName -Confirm:$false
    }
} else {
    if ($PSCmdlet.ShouldProcess($VMName, "checkpoint $SnapshotName")) {
        Checkpoint-VM -Name $VMName -SnapshotName $SnapshotName
    }
}
Write-Host 'VM_SNAPSHOT_WHATIF_OK'
