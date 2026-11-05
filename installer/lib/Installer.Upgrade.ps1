#requires -Version 5.1
# Cross-version upgrade gate for Cyber-Butler.

function Get-CyberButlerVersionValue {
    param([string]$Version)
    if ([string]::IsNullOrWhiteSpace($Version)) { return $null }
    try { return [version](($Version.Trim()) -replace '^[vV]', '') } catch { return $null }
}

function Get-CyberButlerInstalledVersion {
    param([Parameter(Mandatory = $true)][string]$InstallPath)
    $path = Join-Path $InstallPath 'VERSION'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-Content -LiteralPath $path -Raw -Encoding UTF8).Trim()
}

<#
.SYNOPSIS
    Test-CyberButlerUpgradePath performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Test-CyberButlerUpgradePath {
    param(
        [Parameter(Mandatory = $true)][string]$PackageVersion,
        [string]$InstalledVersion = ''
    )
    $package = Get-CyberButlerVersionValue $PackageVersion
    $installed = Get-CyberButlerVersionValue $InstalledVersion
    if (-not $package) { throw ('Invalid package VERSION: ' + $PackageVersion) }
    $bridge = [version]'1.6.3'
    $deep = [version]'1.7.0'
    if (-not $installed) {
        if ($package -ge $deep) {
            return [pscustomobject]@{
                status = 'blocked'
                message = 'The installed version cannot be read. Refusing a v1.7.0 upgrade; restore a valid VERSION or reinstall v1.6.3 first.'
            }
        }
        return [pscustomobject]@{ status = 'unknown_installed'; message = 'No installed VERSION found; treating this as a fresh install.' }
    }
    if ($package -ge $deep -and $installed -lt $bridge) {
        return [pscustomobject]@{
            status = 'blocked'
            message = 'Please upgrade to v1.6.3 first to complete the architecture decoupling, then upgrade to v1.7.0.'
        }
    }
    if ($package -ge $bridge -and $installed -lt $bridge) {
        return [pscustomobject]@{
            status = 'migration_required'
            message = 'v1.6.2 must be migrated to v1.6.3 before any newer overlay. Run installer/Migrate-v1.6.2-to-v1.6.3.ps1.'
        }
    }
    return [pscustomobject]@{ status = 'ok'; message = ('Upgrade path allowed: ' + $InstalledVersion + ' -> ' + $PackageVersion) }
}

function Assert-CyberButlerUpgradePath {
    param(
        [Parameter(Mandatory = $true)][string]$PackageVersion,
        [string]$InstalledVersion = ''
    )
    $result = Test-CyberButlerUpgradePath -PackageVersion $PackageVersion -InstalledVersion $InstalledVersion
    if ($result.status -eq 'blocked') { throw $result.message }
    return $result
}
