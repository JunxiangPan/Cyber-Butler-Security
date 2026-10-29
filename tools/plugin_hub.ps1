#Requires -Version 5.1
<#
Cyber-Butler AstrBot plugin hub backend.

Reads the live plugin list from the AstrBot dashboard API (authoritative for
enabled/disabled state) and falls back to parsing metadata.yaml files when the
service is offline. All write operations go through the local AstrBot API so a
running instance reloads the plugin without restarting the whole stack.

Deletion is deliberately softer than AstrBot's own uninstall: the plugin
directory is moved into backups/deleted_plugins/ and never removed.
#>

$script:AstrBotApiBase = 'http://127.0.0.1:6185'

function Get-CyberButlerToken {
    param([string]$ProjectRoot)
    $file = Join-Path $ProjectRoot '.astrbot_token'
    if (-not (Test-Path -LiteralPath $file)) { return '' }
    try { return (Get-Content -LiteralPath $file -Raw -Encoding UTF8).Trim() } catch { return '' }
}

function Invoke-AstrBotApi {
    param(
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')][string]$Method = 'GET',
        [Parameter(Mandatory = $true)][string]$ApiPath,
        $Body = $null,
        [int]$TimeoutSec = 20
    )

    $token = Get-CyberButlerToken $script:ProjectRoot
    if (-not $token) { throw 'AstrBot token not found; open the dashboard once to create it.' }

    $parameters = @{
        Uri         = ($script:AstrBotApiBase + $ApiPath)
        Method      = $Method
        Headers     = @{ Authorization = 'Bearer ' + $token; 'User-Agent' = 'Cyber-Butler-Dashboard' }
        TimeoutSec  = $TimeoutSec
        UseBasicParsing = $true
    }
    if ($null -ne $Body) {
        $parameters.Body = ($Body | ConvertTo-Json -Depth 8 -Compress)
        $parameters.ContentType = 'application/json; charset=utf-8'
    }
    try {
        # PS 5.1 Invoke-RestMethod mis-decodes UTF-8 JSON when the response has
        # no charset parameter, which corrupts Chinese plugin names. Read the
        # raw bytes and decode explicitly instead.
        $response = Invoke-WebRequest @parameters
        $stream = $response.RawContentStream
        try { $stream.Position = 0 } catch { }
        $text = [Text.Encoding]::UTF8.GetString($stream.ToArray())
        if (-not $text.Trim()) { return $null }
        return ($text | ConvertFrom-Json)
    } catch {
        $message = $_.Exception.Message
        throw ('AstrBot API ' + $ApiPath + ' failed: ' + $message)
    }
}

function Read-PluginMetadataYaml {
    param([Parameter(Mandatory = $true)][string]$Path)

    $data = @{
        name = [IO.Path]::GetFileName((Split-Path -Parent $Path))
        display_name = ''
        desc = ''
        short_desc = ''
        version = ''
        author = ''
        repo = ''
        astrbot_version = ''
        support_platforms = @()
    }
    if (-not (Test-Path -LiteralPath $Path)) { return $data }

    $lines = @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue)
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($line -match '^\s*#' -or $line.Trim() -eq '---' -or -not $line.Trim()) { continue }
        if ($line -notmatch '^([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$') { continue }
        $key = $Matches[1]
        $value = $Matches[2].Trim()
        $value = $value -replace '\s{2,}#.*$', ''
        $value = $value.Trim()

        if ($value -eq '|' -or $value -eq '>' -or $value -eq '|-' -or $value -eq '>-') {
            $block = New-Object System.Collections.ArrayList
            $j = $i + 1
            while ($j -lt $lines.Count -and ($lines[$j] -match '^\s{2,}\S' -or -not $lines[$j].Trim())) {
                [void]$block.Add($lines[$j].Trim())
                $j++
            }
            $joined = if ($value.StartsWith('|')) { $block -join "`n" } else { $block -join ' ' }
            $data[$key] = $joined.Trim()
            $i = $j - 1
            continue
        }

        if (-not $value) {
            $items = New-Object System.Collections.ArrayList
            $j = $i + 1
            while ($j -lt $lines.Count -and $lines[$j] -match '^\s{2,}-\s+(.+)$') {
                [void]$items.Add($Matches[1].Trim().Trim('"').Trim("'"))
                $j++
            }
            if ($items.Count -gt 0) {
                $data[$key] = @($items)
                $i = $j - 1
            }
            continue
        }

        $data[$key] = $value.Trim('"').Trim("'")
    }
    return $data
}

function Get-AstrBotPluginFolders {
    param([string]$ProjectRoot)
    $pluginsRoot = Join-Path $ProjectRoot 'AstrBot\data\plugins'
    if (-not (Test-Path -LiteralPath $pluginsRoot)) { return @() }
    return @(Get-ChildItem -LiteralPath $pluginsRoot -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
}

function Get-AstrBotPluginList {
    param(
        [string]$ProjectRoot,
        [switch]$FilesOnly
    )

    $version = Get-LocalAstrBotVersion $ProjectRoot
    $byDir = @{}
    $apiError = ''

    if (-not $FilesOnly) {
        try {
            $response = Invoke-AstrBotApi -Method GET -ApiPath '/api/plugin/get'
            if ($response -and $response.status -ne 'error') {
                foreach ($item in @($response.data)) {
                    if (-not $item) { continue }
                    $dirName = [string]$item.root_dir_name
                    if (-not $dirName) { $dirName = [string]$item.name }
                    $byDir[$dirName] = [pscustomobject]@{
                        Name           = [string]$item.name
                        DisplayName    = [string]$item.display_name
                        Version        = [string]$item.version
                        Author         = [string]$item.author
                        Desc           = [string]$item.desc
                        Repo           = [string]$item.repo
                        AstrBotVersion = [string]$item.astrbot_version
                        Platforms      = @($item.support_platforms)
                        Activated      = [bool]$item.activated
                        Reserved       = [bool]$item.reserved
                        RootDirName    = $dirName
                        InstalledAt    = [string]$item.installed_at
                        Source         = 'api'
                    }
                }
            }
        } catch {
            $apiError = $_.Exception.Message
        }
    }

    foreach ($folder in (Get-AstrBotPluginFolders $ProjectRoot)) {
        if ($byDir.ContainsKey($folder.Name)) { continue }
        $metadata = Read-PluginMetadataYaml (Join-Path $folder.FullName 'metadata.yaml')
        $byDir[$folder.Name] = [pscustomobject]@{
            Name           = [string]$metadata.name
            DisplayName    = [string]$metadata.display_name
            Version        = [string]$metadata.version
            Author         = [string]$metadata.author
            Desc           = [string]$metadata.desc
            Repo           = [string]$metadata.repo
            AstrBotVersion = [string]$metadata.astrbot_version
            Platforms      = @($metadata.support_platforms)
            Activated      = $null
            Reserved       = $false
            RootDirName    = $folder.Name
            InstalledAt    = ''
            Source         = 'filesystem'
        }
    }

    $list = New-Object System.Collections.ArrayList
    foreach ($entry in $byDir.Values) {
        $compat = Test-AstrBotVersionSpec -Spec $entry.AstrBotVersion -Version $version
        $entry | Add-Member -NotePropertyName Compat -NotePropertyValue ([bool]$compat.Ok) -Force
        $entry | Add-Member -NotePropertyName CompatReason -NotePropertyValue ([string]$compat.Reason) -Force
        $entry | Add-Member -NotePropertyName ConfigPath -NotePropertyValue (Get-AstrBotPluginConfigPath $ProjectRoot $entry.RootDirName) -Force
        [void]$list.Add($entry)
    }

    return [pscustomobject]@{
        Version  = $version
        ApiError = $apiError
        Plugins  = @($list | Sort-Object Name)
    }
}

function Set-AstrBotPluginEnabled {
    param(
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$PluginId,
        [Parameter(Mandatory = $true)][bool]$Enabled
    )
    $endpoint = if ($Enabled) { '/api/plugin/on' } else { '/api/plugin/off' }
    $response = Invoke-AstrBotApi -Method POST -ApiPath $endpoint -Body @{ name = $PluginId }
    if (-not $response -or $response.status -eq 'error') {
        throw ('AstrBot rejected the change: ' + [string]$response.message)
    }
    return [string]$response.message
}

function Reload-AstrBotPlugins {
    param([string]$ProjectRoot)
    $response = Invoke-AstrBotApi -Method POST -ApiPath '/api/plugin/reload' -Body @{}
    if (-not $response -or $response.status -eq 'error') {
        throw ('AstrBot reload failed: ' + [string]$response.message)
    }
    return [string]$response.message
}

function Reload-AstrBotPlugin {
    param([string]$ProjectRoot, [Parameter(Mandatory = $true)][string]$PluginId)
    $response = Invoke-AstrBotApi -Method POST -ApiPath '/api/plugin/reload' -Body @{ name = $PluginId }
    if (-not $response -or $response.status -eq 'error') {
        throw ('AstrBot reload failed: ' + [string]$response.message)
    }
    return [string]$response.message
}

function Get-AstrBotPluginConfigPath {
    param([string]$ProjectRoot, [string]$RootDirName)
    if (-not $RootDirName) { return '' }
    return (Join-Path $ProjectRoot ('AstrBot\data\config\' + $RootDirName + '_config.json'))
}

function Move-AstrBotPluginToRecycleBin {
    param(
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$RootDirName
    )

    $pluginsRoot = (Resolve-Path -LiteralPath (Join-Path $ProjectRoot 'AstrBot\data\plugins')).Path
    $source = (Resolve-Path -LiteralPath (Join-Path $pluginsRoot $RootDirName) -ErrorAction Stop).Path
    if (-not $source.StartsWith($pluginsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'refusing to move a path outside AstrBot/data/plugins'
    }
    if ($RootDirName -match '[\\/]' -or $RootDirName -eq '.' -or $RootDirName -eq '..') {
        throw 'invalid plugin directory name'
    }

    $backupDir = Join-Path $ProjectRoot 'backups\deleted_plugins'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $destination = Join-Path $backupDir ($RootDirName + '-' + $stamp)
    Move-Item -LiteralPath $source -Destination $destination -Force -ErrorAction Stop

    $record = [pscustomobject]@{
        plugin       = $RootDirName
        moved_at     = (Get-Date).ToString('o')
        source       = $source
        destination  = $destination
        restored_by  = 'move the directory back into AstrBot/data/plugins and reload'
    }
    Add-Content -LiteralPath (Join-Path $backupDir 'deleted.log') -Value ($record | ConvertTo-Json -Compress) -Encoding UTF8
    return $record
}

function Restore-AstrBotPluginDefaults {
    param(
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$PluginId,
        [Parameter(Mandatory = $true)][string]$RootDirName
    )

    $configPath = Get-AstrBotPluginConfigPath $ProjectRoot $RootDirName
    $backupPath = ''
    if (Test-Path -LiteralPath $configPath) {
        $backupDir = Join-Path $ProjectRoot 'backups\plugin-config-defaults'
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $backupPath = Join-Path $backupDir ($RootDirName + '-' + $stamp + '.json')
        Copy-Item -LiteralPath $configPath -Destination $backupPath -Force
        Remove-Item -LiteralPath $configPath -Force
    }

    $message = Set-AstrBotPluginEnabled -ProjectRoot $ProjectRoot -PluginId $PluginId -Enabled $true
    return [pscustomobject]@{
        HadConfig  = [bool]$backupPath
        BackupPath = $backupPath
        Message    = $message
    }
}

function Get-AstrBotRuntimeInfo {
    param([string]$ProjectRoot)
    $token = Get-CyberButlerToken $ProjectRoot
    $version = Get-LocalAstrBotVersion $ProjectRoot
    $online = $false
    try {
        $client = New-Object Net.Sockets.TcpClient
        $client.Connect('127.0.0.1', 6185)
        $online = $client.Connected
        $client.Close()
    } catch { $online = $false }
    return [pscustomobject]@{ Online = $online; HasToken = [bool]$token; Version = $version }
}
