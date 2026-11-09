[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$VMName,
    [string]$SnapshotName = 'cbs-acceptance-baseline',
    [switch]$Restore,
    [switch]$Rollback
)
$ErrorActionPreference = 'Stop'
if ($Restore -and $Rollback) {
    Write-Host 'ERROR: cannot specify both -Restore and -Rollback'
    exit 2
}
if (($Restore -or $Rollback) -and $SnapshotName -ne 'cbs-acceptance-baseline') {
    Write-Host 'ERROR: -Restore/-Rollback must use cbs-acceptance-baseline'
    exit 2
}
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
