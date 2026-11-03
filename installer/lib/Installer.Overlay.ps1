# Overlay compatibility helpers.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

function Get-CyberButlerExternalAgentVersion {
    param([Parameter(Mandatory = $true)][string]$ExternalAgentPath)
    $versionFile = Join-Path $ExternalAgentPath 'VERSION'
    if (Test-Path -LiteralPath $versionFile) {
        return (Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8).Trim()
    }
    $pyproject = Join-Path $ExternalAgentPath 'pyproject.toml'
    if (Test-Path -LiteralPath $pyproject) {
        $match = [regex]::Match((Get-Content -LiteralPath $pyproject -Raw -Encoding UTF8), '(?m)^version\s*=\s*"([^"]+)"')
        if ($match.Success) { return $match.Groups[1].Value }
    }
    return ''
}

function Test-CyberButlerOverlayManifest {
    param(
        [Parameter(Mandatory = $true)][string]$ExternalAgentPath,
        [Parameter(Mandatory = $true)][string]$OverlayPath
    )

    $manifestPath = Join-Path $OverlayPath 'overlay-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) {
        throw "Overlay manifest missing: $manifestPath"
    }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $expected = [string]$manifest.based_on_astrbot_version
    $actual = Get-CyberButlerExternalAgentVersion -ExternalAgentPath $ExternalAgentPath
    if ([string]::IsNullOrWhiteSpace($expected) -or $actual -ne $expected) {
        throw ("Overlay/ExternalAgent version mismatch: manifest expects {0}, installed ExternalAgent is {1}. ExternalAgent has been upgraded; overlay must be re-adapted." -f $expected, $actual)
    }

    $warnings = New-Object System.Collections.Generic.List[string]
    foreach ($entry in @($manifest.files)) {
        $rel = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($rel)) { throw 'Overlay manifest contains an empty path.' }
        $overlayFile = Join-Path $OverlayPath $rel
        if (-not (Test-Path -LiteralPath $overlayFile)) {
            throw ("Overlay file missing: " + $rel)
        }
        $overlayHash = (Get-FileHash -LiteralPath $overlayFile -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($entry.overlay_sha256 -and [string]$entry.overlay_sha256 -ne $overlayHash) {
            throw ("Overlay file hash changed without manifest update: " + $rel)
        }
        $officialFile = Join-Path (Join-Path $ExternalAgentPath 'astrbot') ($rel -replace '^astrbot[\\/]', '')
        if ($entry.official_sha256) {
            if (-not (Test-Path -LiteralPath $officialFile)) {
                throw ("Official source file missing for overlay comparison: " + $rel)
            }
            $officialHash = (Get-FileHash -LiteralPath $officialFile -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($officialHash -ne [string]$entry.official_sha256) {
                $warnings.Add(("ExternalAgent has been upgraded; overlay needs re-adaptation: " + $rel))
            }
        }
        foreach ($dependency in @($entry.depends_on)) {
            if ([string]::IsNullOrWhiteSpace($dependency)) { continue }
            $depOverlay = Join-Path $OverlayPath $dependency
            $depOfficial = Join-Path $ExternalAgentPath $dependency
            if (-not (Test-Path -LiteralPath $depOverlay) -and -not (Test-Path -LiteralPath $depOfficial)) {
                throw ("Overlay dependency missing: " + $rel + " -> " + $dependency)
            }
        }
    }
    foreach ($warning in $warnings) { Write-Host ('WARN ' + $warning) }
    return [pscustomobject]@{
        version = $actual
        file_count = @($manifest.files).Count
        warnings = $warnings.ToArray()
    }
}
