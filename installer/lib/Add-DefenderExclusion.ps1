#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallRoot,
    [switch]$AllowCustomRoot
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $InstallRoot)) {
    New-Item -ItemType Directory -Path $InstallRoot -Force | Out-Null
}
$root = (Resolve-Path -LiteralPath $InstallRoot -ErrorAction Stop).Path.TrimEnd([char]92)
$isDefaultRoot = ($root -ieq 'C:\CyberButler')
if (-not $isDefaultRoot) {
    if (-not $AllowCustomRoot) {
        throw "Refusing to add a Defender exclusion outside C:\\CyberButler: $root"
    }
    $driveRoot = [IO.Path]::GetPathRoot($root)
    if ($root -ieq $driveRoot) {
        throw "Refusing to exclude a drive root: $root"
    }
    $forbidden = @(
        [IO.Path]::GetFullPath($env:SystemRoot),
        [IO.Path]::GetFullPath($env:ProgramFiles),
        [IO.Path]::GetFullPath($env:ProgramData),
        [IO.Path]::GetFullPath([Environment]::GetFolderPath('UserProfile'))
    )
    foreach ($bad in $forbidden) {
        if ([string]::IsNullOrWhiteSpace($bad)) { continue }
        $bad = $bad.TrimEnd([char]92)
        if ($root -ieq $bad -or $root.StartsWith($bad + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to exclude a protected Windows/user directory: $root"
        }
    }
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
