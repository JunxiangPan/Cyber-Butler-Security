[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RunnerRoot = 'C:\actions-runner',
    [string]$VmRoot = 'C:\CyberButler\Models'
)
$ErrorActionPreference = 'Stop'
if ($PSCmdlet.ShouldProcess($RunnerRoot, 'create runner root')) {
    New-Item -ItemType Directory -Path $RunnerRoot -Force | Out-Null
}
if ($PSCmdlet.ShouldProcess($VmRoot, 'verify acceptance VM root')) {
    if (-not (Test-Path $VmRoot)) { Write-Warning "VM root missing: $VmRoot" }
}
Write-Host 'SETUP_RUNNER_VM_WHATIF_OK'
