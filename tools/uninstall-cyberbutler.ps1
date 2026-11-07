#requires -Version 7.0
<#
.SYNOPSIS
    Deterministic uninstall helper used by the VM chaos harness.
.DESCRIPTION
    Stops the native broker service, deletes it, and removes the install tree.
#>
param([string]$InstallRoot = 'C:\CyberButler', [switch]$Confirm)
$ErrorActionPreference = 'Stop'
if (-not $Confirm) { throw 'Pass -Confirm to uninstall.' }
$root = [IO.Path]::GetFullPath($InstallRoot)
$serviceName = 'Cyber-Butler Broker'
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
$state = Join-Path $env:ProgramData 'CyberButler'
if (Test-Path -LiteralPath $state) { Remove-Item -LiteralPath $state -Recurse -Force -ErrorAction SilentlyContinue }
Write-Output 'UNINSTALL_OK'
