# CBS / personal plugin deployment helpers.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

$script:CyberButlerCbsPlugins = @(
    'astrbot_plugin_at_gate',
    'astrbot_plugin_cloud_fallback',
    'astrbot_plugin_dsh_bridge',
    'astrbot_plugin_dst_guard',
    'astrbot_plugin_mcp_readonly',
    'astrbot_plugin_router',
    'astrbot_plugin_security_gate',
    'astrbot_plugin_totp_broker',
    'astrbot_plugin_weather_tools',
    'astrbot_plugin_webui_bridge'
)

$script:CyberButlerPersonalPlugins = @(
    'astrbot_plugin_private_companion',
    'astrbot_plugin_livingmemory',
    'astrbot_plugin_memorix'
)

function Copy-CyberButlerPluginTree {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$AllowedRoot,
        $Journal = $null,
        [string]$JournalStep = 'core',
        [switch]$PreserveSchema,
        [string]$Label = 'plugin'
    )

    $sourceFull = [IO.Path]::GetFullPath($Source)
    $destFull = [IO.Path]::GetFullPath($Destination)
    if (-not (Test-Path -LiteralPath $sourceFull)) { throw ("Plugin source missing: " + $sourceFull) }
    $copied = 0
    $skipped = 0
    foreach ($file in @(Get-ChildItem -LiteralPath $sourceFull -Recurse -File -ErrorAction Stop)) {
        $relative = $file.FullName.Substring($sourceFull.Length).TrimStart('\\')
        $parts = $relative -split '[\\/]'
        if ($parts -contains 'data' -or $parts -contains '__pycache__' -or $parts -contains '.git' -or $parts -contains '.pytest_cache') { continue }
        if ($file.Extension -eq '.pyc' -or $file.Extension -eq '.log') { continue }
        if ($PreserveSchema -and $file.Name -eq '_conf_schema.json' -and (Test-Path -LiteralPath (Join-Path $destFull $relative))) { continue }
        $target = Join-Path $destFull $relative
        $parent = Split-Path -Parent $target
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $sourceHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        if (Test-Path -LiteralPath $target) {
            $targetHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            if ($sourceHash -eq $targetHash) {
                $skipped++
                continue
            }
            if ($null -ne $Journal) {
                Backup-CyberButlerFile -Journal $Journal -Step $JournalStep -Path $target -AllowedRoot $AllowedRoot | Out-Null
            }
        } elseif ($null -ne $Journal) {
            Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                type = 'delete-created-file'
                path = [IO.Path]::GetFullPath($target)
                allowed_root = [IO.Path]::GetFullPath($AllowedRoot)
            })
        }
        Copy-Item -LiteralPath $file.FullName -Destination $target -Force
        $copied++
    }
    return [pscustomobject]@{ label = $Label; copied = $copied; skipped = $skipped; path = $destFull }
}

function Copy-CyberButlerCbsPlugins {
    param(
        [Parameter(Mandatory = $true)][string]$ExternalAgentPath,
        [Parameter(Mandatory = $true)][string]$ReleasePluginsPath,
        $Journal = $null,
        [string]$JournalStep = 'core'
    )
    if (-not (Test-Path -LiteralPath $ReleasePluginsPath)) { throw ("CBS plugins source missing: " + $ReleasePluginsPath) }
    $targetRoot = Join-Path $ExternalAgentPath 'data\plugins'
    New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
    $installed = New-Object System.Collections.Generic.List[object]
    foreach ($name in $script:CyberButlerCbsPlugins) {
        $source = Join-Path $ReleasePluginsPath $name
        if (-not (Test-Path -LiteralPath (Join-Path $source 'main.py'))) {
            throw ("CBS plugin missing main.py: " + $name)
        }
        $result = Copy-CyberButlerPluginTree -Source $source -Destination (Join-Path $targetRoot $name) `
            -AllowedRoot $ExternalAgentPath -Journal $Journal -JournalStep $JournalStep -Label $name
        $installed.Add([pscustomobject]@{ name = $name; status = 'installed'; copied = $result.copied; skipped = $result.skipped; path = $result.path })
    }
    return [pscustomobject]@{ status = 'installed'; path = $targetRoot; plugins = $installed.ToArray() }
}

function Copy-CyberButlerPersonalPlugins {
    param(
        [Parameter(Mandatory = $true)][string]$ExternalAgentPath,
        [string]$PersonalPluginsPath = '',
        [switch]$Repair,
        $Journal = $null,
        [string]$JournalStep = 'core'
    )
    $targetRoot = Join-Path $ExternalAgentPath 'data\plugins'
    if ([string]::IsNullOrWhiteSpace($PersonalPluginsPath)) {
        return [pscustomobject]@{ status = 'skipped'; path = ''; plugins = @(); reason = 'personal plugins path not supplied' }
    }
    $sourceRoot = [IO.Path]::GetFullPath($PersonalPluginsPath)
    if (-not (Test-Path -LiteralPath $sourceRoot)) { throw ("Personal plugins path missing: " + $sourceRoot) }

    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($dir in @(Get-ChildItem -LiteralPath $sourceRoot -Directory -ErrorAction SilentlyContinue)) {
        if ($script:CyberButlerPersonalPlugins -contains $dir.Name -and $script:CyberButlerCbsPlugins -contains $dir.Name) {
            throw ("Personal plugin name collides with CBS plugin: " + $dir.Name)
        }
        if ($script:CyberButlerPersonalPlugins -notcontains $dir.Name) {
            Write-Host ('WARN ignored non-personal plugin: ' + $dir.Name)
            continue
        }
        $selected.Add($dir.Name)
    }
    foreach ($name in $script:CyberButlerPersonalPlugins) {
        if ($selected -notcontains $name) { throw ("Personal plugin source missing: " + $name) }
        $pluginSource = Join-Path $sourceRoot $name
        foreach ($required in @('main.py', 'metadata.yaml')) {
            if (-not (Test-Path -LiteralPath (Join-Path $pluginSource $required))) {
                throw ("Plugin " + $name + " is missing required file(s): " + $required)
            }
        }
        if ($Repair) {
            $targetPlugin = Join-Path $targetRoot $name
            foreach ($requiredTarget in @('main.py', 'metadata.yaml')) {
                if (-not (Test-Path -LiteralPath (Join-Path $targetPlugin $requiredTarget))) {
                    throw ("Plugin " + $name + " is missing " + $requiredTarget + " in target")
                }
            }
        }
    }

    if ($Repair) {
        return [pscustomobject]@{ status = 'preserved'; path = $targetRoot; plugins = @($selected | ForEach-Object { [pscustomobject]@{ name = $_; status = 'preserved' } }); reason = 'repair checks only' }
    }

    $installed = New-Object System.Collections.Generic.List[object]
    $anyUpdated = $false
    foreach ($name in $selected) {
        $result = Copy-CyberButlerPluginTree -Source (Join-Path $sourceRoot $name) -Destination (Join-Path $targetRoot $name) `
            -AllowedRoot $ExternalAgentPath -Journal $Journal -JournalStep $JournalStep -PreserveSchema -Label $name
        $status = if ($result.copied -gt 0) { 'updated'; $anyUpdated = $true } else { 'preserved' }
        $installed.Add([pscustomobject]@{ name = $name; status = $status; copied = $result.copied; skipped = $result.skipped; path = $result.path })
    }
    return [pscustomobject]@{ status = $(if ($anyUpdated) { 'updated' } else { 'preserved' }); path = $targetRoot; plugins = $installed.ToArray(); reason = '' }
}
