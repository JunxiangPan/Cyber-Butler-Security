$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location -LiteralPath $root

$pesterPath = 'C:\Pester34\Pester.psd1'
if (-not (Test-Path -LiteralPath $pesterPath)) {
    $found = Get-Module -ListAvailable Pester |
        Where-Object { $_.Version -eq [version]'3.4.0' } |
        Select-Object -First 1
    if ($found) { $pesterPath = $found.Path }
}
if (-not (Test-Path -LiteralPath $pesterPath)) {
    throw 'Pester 3.4.0 not installed'
}

Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module $pesterPath -Force
$pester = Get-Module Pester
if (-not $pester -or $pester.Version -ne [version]'3.4.0') {
    throw ('Pester 3.4.0 required, got ' + $(if ($pester) { $pester.Version } else { 'none' }))
}

. (Join-Path $root 'installer/lib/Installer.Common.ps1')
. (Join-Path $root 'installer/lib/Installer.Journal.ps1')
. (Join-Path $root 'installer/lib/Installer.Totp.ps1')
. (Join-Path $root 'installer/lib/Installer.Upgrade.ps1')
. (Join-Path $root 'installer/lib/Installer.Core.ps1')

$result = Invoke-Pester -Script (Join-Path $root 'installer/tests') -PassThru
if ($result.FailedCount -ne 0) {
    Write-Host ('PESTER_FAILED=' + $result.FailedCount)
    exit 1
}
Write-Host ('PESTER_OK=' + $result.PassedCount)
exit 0
