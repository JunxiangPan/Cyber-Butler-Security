#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InstallRoot)) {
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
}
$root = (Resolve-Path -LiteralPath $InstallRoot -ErrorAction Stop).Path.TrimEnd('\')
if ($root -notmatch '^[A-Za-z]:\\CyberButler$') {
    throw "Refusing to add a Defender exclusion outside C:\\CyberButler: $root"
}

$status = Get-MpComputerStatus -ErrorAction Stop
if (-not $status.RealTimeProtectionEnabled) {
    Write-Warning 'Defender real-time protection is already disabled; this helper will not change that setting.'
}

$prefs = Get-MpPreference
if (@($prefs.ExclusionPath) -notcontains $root) {
    Add-MpPreference -ExclusionPath $root -ErrorAction Stop
}

$after = Get-MpPreference
if (@($after.ExclusionPath) -contains $root) {
    Write-Output "DEFENDER_EXCLUSION_OK $root"
    exit 0
}

throw 'Defender did not report the requested exclusion. Check Tamper Protection or group policy.'
