#Requires -Version 5.1
<#
Cyber-Butler plugin market backend.

Two sources:
  official  - AstrBot official registry JSON (cached for one hour)
  github    - GitHub code search for repositories with astrbot_plugin in the name

Downloads are extracted into a temporary directory and must pass the static
security scanner and the AstrBot version check before the installer copies them
into AstrBot/data/plugins or tools/dashboard_plugins.
#>

$script:MarketRegistryUrl = 'https://api.soulter.top/astrbot/plugins'
$script:MarketFallbackUrl = 'https://github.com/AstrBotDevs/AstrBot_Plugins_Collection/raw/refs/heads/main/plugin_cache_original.json'
$script:MarketMaxArchiveBytes = 64MB
$script:MarketMaxExpandedBytes = 256MB
$script:MarketMaxEntries = 5000

function Get-PluginMarketCachePath {
    $dir = Join-Path $env:LOCALAPPDATA 'CyberButler'
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    return (Join-Path $dir 'market-cache.json')
}

function Get-PluginMarketEntries {
    param(
        [ValidateSet('official', 'github')][string]$Source = 'official',
        [string]$Query = '',
        [switch]$ForceRefresh,
        [int]$Limit = 60
    )

    if ($Source -eq 'github') {
        return Get-PluginMarketGithub -Query $Query -Limit $Limit
    }

    $cachePath = Get-PluginMarketCachePath
    $payload = $null
    if (-not $ForceRefresh -and (Test-Path -LiteralPath $cachePath)) {
        try {
            $cached = Get-Content -LiteralPath $cachePath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($cached -and $cached.fetched_at -and $cached.payload) {
                $age = (Get-Date) - [datetime]$cached.fetched_at
                if ($age.TotalSeconds -lt 3600) { $payload = $cached.payload }
            }
        } catch { }
    }

    if (-not $payload) {
        $raw = $null
        foreach ($url in @($script:MarketRegistryUrl, $script:MarketFallbackUrl)) {
            try {
                $response = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30 -Headers @{ 'User-Agent' = 'Cyber-Butler-Dashboard' }
                $raw = $response.Content
                if ($raw) { break }
            } catch { }
        }
        if (-not $raw) { throw '无法读取 AstrBot 官方插件市场，请检查网络。' }
        $payload = $raw | ConvertFrom-Json
        try {
            [pscustomobject]@{ fetched_at = (Get-Date).ToString('o'); payload = $payload } |
                ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $cachePath -Encoding UTF8
        } catch { }
    }

    $entries = New-Object System.Collections.ArrayList
    $needle = $Query.Trim()
    foreach ($property in $payload.PSObject.Properties) {
        if ($property.Name -eq '$meta') { continue }
        $item = $property.Value
        if (-not $item) { continue }
        $name = [string]$item.name
        $display = [string]$item.display_name
        $desc = [string]$item.desc
        $author = [string]$item.author
        if ($needle) {
            $haystack = ($name + ' ' + $display + ' ' + $desc + ' ' + $author).ToLowerInvariant()
            if ($haystack.IndexOf($needle.ToLowerInvariant()) -lt 0) { continue }
        }
        [void]$entries.Add([pscustomobject]@{
            Name           = $name
            DisplayName    = $display
            Version        = [string]$item.version
            Author         = $author
            Desc           = $desc
            Repo           = [string]$item.repo
            DownloadUrl    = [string]$item.download_url
            AstrBotVersion = [string]$item.astrbot_version
            Stars          = [int]$item.stars
            Downloads      = [int]$item.download_count
            Category       = [string]$item.category
            Source         = 'official'
            RepoKey        = $property.Name
        })
    }

    return @($entries | Sort-Object @{ Expression = 'Stars'; Descending = $true }, Name | Select-Object -First $Limit)
}

function Get-PluginMarketGithub {
    param([string]$Query = '', [int]$Limit = 30)

    $terms = 'astrbot_plugin in:name,description'
    if ($Query.Trim()) { $terms = $Query.Trim() + ' ' + $terms }
    $encoded = [uri]::EscapeDataString($terms)
    $uri = 'https://api.github.com/search/repositories?q=' + $encoded + '&sort=stars&order=desc&per_page=' + $Limit
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers @{ 'User-Agent' = 'Cyber-Butler-Dashboard'; 'Accept' = 'application/vnd.github+json' } -TimeoutSec 30
    } catch {
        throw ('GitHub 搜索失败：' + $_.Exception.Message + '（未登录调用有频率限制，可稍后重试）')
    }

    $entries = New-Object System.Collections.ArrayList
    foreach ($repo in @($response.items)) {
        if (-not $repo) { continue }
        $branch = [string]$repo.default_branch
        if (-not $branch) { $branch = 'main' }
        [void]$entries.Add([pscustomobject]@{
            Name           = [string]$repo.name
            DisplayName    = [string]$repo.full_name
            Version        = ''
            Author         = [string]$repo.owner.login
            Desc           = [string]$repo.description
            Repo           = [string]$repo.html_url
            DownloadUrl    = ('https://codeload.github.com/' + $repo.full_name + '/zip/refs/heads/' + $branch)
            AstrBotVersion = ''
            Stars          = [int]$repo.stargazers_count
            Downloads      = 0
            Category       = 'github'
            Source         = 'github'
            RepoKey        = [string]$repo.full_name
        })
    }
    return @($entries)
}

function Save-PluginArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Url,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    if ($Url -notmatch '^https://') { throw '仅允许 https 下载地址。' }
    $parent = Split-Path -Parent $Destination
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    try {
        Invoke-WebRequest -Uri $Url -OutFile $Destination -UseBasicParsing -TimeoutSec 120 -Headers @{ 'User-Agent' = 'Cyber-Butler-Dashboard' }
    } catch {
        throw ('下载失败：' + $_.Exception.Message)
    }
    $file = Get-Item -LiteralPath $Destination -ErrorAction Stop
    if ($file.Length -lt 64) { throw '下载的文件为空或不是有效压缩包。' }
    if ($file.Length -gt $script:MarketMaxArchiveBytes) {
        throw ('压缩包过大（{0:N1} MB，上限 {1} MB）。' -f ($file.Length / 1MB), ($script:MarketMaxArchiveBytes / 1MB))
    }
    return $file
}

function Expand-PluginArchive {
    param(
        [Parameter(Mandatory = $true)][string]$ArchivePath,
        [Parameter(Mandatory = $true)][string]$Destination
    )

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    $destinationFull = [IO.Path]::GetFullPath($Destination)
    $separator = [IO.Path]::DirectorySeparatorChar

    $zip = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
    try {
        if ($zip.Entries.Count -gt $script:MarketMaxEntries) {
            throw ('压缩包条目过多（{0}），已拒绝。' -f $zip.Entries.Count)
        }
        $expanded = [long]0
        foreach ($entry in $zip.Entries) {
            $expanded += [long]$entry.Length
            if ($expanded -gt $script:MarketMaxExpandedBytes) {
                throw '解压后体积过大，已拒绝（疑似压缩炸弹）。'
            }
            $target = [IO.Path]::GetFullPath((Join-Path $destinationFull $entry.FullName))
            if (-not $target.StartsWith($destinationFull + $separator, [StringComparison]::OrdinalIgnoreCase)) {
                throw ('压缩包包含非法路径：' + $entry.FullName)
            }
        }
    } finally {
        $zip.Dispose()
    }

    [IO.Compression.ZipFile]::ExtractToDirectory($ArchivePath, $destinationFull)
    return $destinationFull
}

function Find-PluginPackageRoot {
    param([Parameter(Mandatory = $true)][string]$Directory)

    if (Test-Path -LiteralPath (Join-Path $Directory 'metadata.yaml')) { return $Directory }
    if (Test-Path -LiteralPath (Join-Path $Directory 'manifest.json')) { return $Directory }

    $children = @(Get-ChildItem -LiteralPath $Directory -Directory -ErrorAction SilentlyContinue)
    if ($children.Count -eq 1) {
        if (Test-Path -LiteralPath (Join-Path $children[0].FullName 'metadata.yaml')) { return $children[0].FullName }
        if (Test-Path -LiteralPath (Join-Path $children[0].FullName 'manifest.json')) { return $children[0].FullName }
    }
    foreach ($child in $children) {
        if (Test-Path -LiteralPath (Join-Path $child.FullName 'metadata.yaml')) { return $child.FullName }
    }
    foreach ($child in $children) {
        $nested = @(Get-ChildItem -LiteralPath $child.FullName -Directory -ErrorAction SilentlyContinue)
        foreach ($inner in $nested) {
            if (Test-Path -LiteralPath (Join-Path $inner.FullName 'metadata.yaml')) { return $inner.FullName }
        }
    }
    throw '压缩包里没有找到 metadata.yaml，无法确认这是一个 AstrBot 插件。'
}

function Install-PluginPackage {
    param(
        [string]$ProjectRoot,
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [ValidateSet('agent', 'dashboard')][string]$TargetKind = 'agent',
        [string]$ExpectedId = ''
    )

    $root = (Resolve-Path -LiteralPath $PackageRoot).Path

    if ($TargetKind -eq 'dashboard') {
        $manifestPath = Join-Path $root 'manifest.json'
        if (-not (Test-Path -LiteralPath $manifestPath)) { throw '控制台模块缺少 manifest.json。' }
        $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $id = [string]$manifest.id
        if (-not $id) { $id = [string]$manifest.name }
        if ($id -notmatch '^[A-Za-z0-9_\-]{2,64}$') { throw '模块 id 非法。' }
        if ($ExpectedId -and $id -ne $ExpectedId) { throw ('模块 id 不匹配：{0} != {1}' -f $id, $ExpectedId) }
        $targetRoot = Join-Path $ProjectRoot 'public-release\tools\dashboard_plugins'
        if (-not (Test-Path -LiteralPath $targetRoot)) { $targetRoot = Join-Path $ProjectRoot 'tools\dashboard_plugins' }
        New-Item -ItemType Directory -Path $targetRoot -Force | Out-Null
        $target = Join-Path $targetRoot $id
        if (Test-Path -LiteralPath $target) { throw ('控制台模块 {0} 已存在。' -f $id) }
        Copy-Item -LiteralPath $root -Destination $target -Recurse -Force
        return [pscustomobject]@{ Id = $id; Path = $target; Kind = 'dashboard' }
    }

    $metadata = Read-PluginMetadataYaml (Join-Path $root 'metadata.yaml')
    $id = [string]$metadata.name
    if (-not $id) { $id = Split-Path -Leaf $root }
    if ($id -notmatch '^[A-Za-z0-9_\-]{2,128}$') { throw '插件名称非法。' }
    if ($ExpectedId -and $id -ne $ExpectedId) { throw ('插件名称不匹配：{0} != {1}' -f $id, $ExpectedId) }

    $pluginsRoot = Join-Path $ProjectRoot 'AstrBot\data\plugins'
    if (-not (Test-Path -LiteralPath $pluginsRoot)) { throw 'AstrBot 插件目录不存在。' }
    $target = Join-Path $pluginsRoot $id
    if (Test-Path -LiteralPath $target) { throw ('插件 {0} 已安装。' -f $id) }

    Copy-Item -LiteralPath $root -Destination $target -Recurse -Force
    return [pscustomobject]@{ Id = $id; Path = $target; Kind = 'agent'; Metadata = $metadata }
}

function Get-PluginReviewSummary {
    param(
        [Parameter(Mandatory = $true)][string]$PackageRoot,
        [string]$LocalVersion = ''
    )

    $metadata = Read-PluginMetadataYaml (Join-Path $PackageRoot 'metadata.yaml')
    $compat = Test-AstrBotVersionSpec -Spec ([string]$metadata.astrbot_version) -Version $LocalVersion
    $scan = Invoke-PluginSecurityScan -Path $PackageRoot
    return [pscustomobject]@{
        Metadata   = $metadata
        Compat     = $compat
        Scan       = $scan
        PackageRoot = $PackageRoot
    }
}
