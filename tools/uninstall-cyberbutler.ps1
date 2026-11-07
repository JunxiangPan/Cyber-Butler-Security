#requires -Version 7.0
<#
.SYNOPSIS
    Deterministic uninstall helper used by the VM chaos harness.
.DESCRIPTION
    Stops the native broker service, deletes it, and removes the install tree.
#>
param([string]$InstallRoot = 'C:\CyberButler', [string]$ServiceName = 'Cyber-Butler Broker', [string]$StatePath = (Join-Path $env:ProgramData 'CyberButler'), [switch]$Confirm)
$ErrorActionPreference = 'Stop'
if (-not $Confirm) { throw 'Pass -Confirm to uninstall.' }
$root = [IO.Path]::GetFullPath($InstallRoot)
<#
.SYNOPSIS
    Stop and delete the broker service.
#>
function Remove-BrokerService {
    $svc = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.Status -ne 'Stopped') { Stop-Service -Name $serviceName -Force -ErrorAction SilentlyContinue }
        & sc.exe delete $serviceName | Out-Null
    }
}
Remove-BrokerService
if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
if (Test-Path -LiteralPath $StatePath) { Remove-Item -LiteralPath $StatePath -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output 'UNINSTALL_OK'
