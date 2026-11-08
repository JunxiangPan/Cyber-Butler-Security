[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][string]$Token,
    [string]$RunnerRoot = 'C:\actions-runner',
    [string]$Labels = 'self-hosted,windows,x64,cbs-vm-proof'
)
$ErrorActionPreference = 'Stop'
$config = Join-Path $RunnerRoot 'config.cmd'
if (-not (Test-Path $config)) { throw "runner config missing: $config" }
if ($PSCmdlet.ShouldProcess($RunnerRoot, 'register GitHub Actions runner')) {
    & $config --url $Url --token $Token --labels $Labels --unattended --replace
}
Write-Host 'REGISTER_RUNNER_WHATIF_OK'
