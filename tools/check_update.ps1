#Requires -Version 5.1
<#
Read-only GitHub release checker for Cyber-Butler.

This script never downloads or applies an update. It compares VERSION with the
latest GitHub release and optionally sends a QQ notification through AstrBot.
#>
param(
    [string]$Repo = 'JunxiangPan/Cyber-Butler-Security',
    [string]$StatusFile = '',
    [string]$SkipFile = '',
    [switch]$Notify,
    [string]$Umo = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$versionFile = Join-Path $root 'VERSION'
$tokenFile = Join-Path $root '.astrbot_token'
if (-not $SkipFile) { $SkipFile = Join-Path $PSScriptRoot 'skip_version.json' }

function Get-RemoteVersion([string]$tag) {
    return ([string]$tag).Trim().TrimStart([char[]]@('v', 'V'))
}

try {
    if (-not (Test-Path -LiteralPath $versionFile)) {
        throw "VERSION file not found: $versionFile"
    }
    $current = (Get-Content -LiteralPath $versionFile -Raw).Trim()
    $headers = @{
        'User-Agent' = 'Cyber-Butler-UpdateChecker/1.0'
        'Accept' = 'application/vnd.github+json'
    }
    if ($env:GITHUB_TOKEN) {
        $headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN
    }

    $api = "https://api.github.com/repos/$Repo/releases/latest"
    $release = Invoke-RestMethod -Uri $api -Headers $headers -TimeoutSec 20
    $latest = Get-RemoteVersion ([string]$release.tag_name)
    $currentVersion = [version]$current
    $latestVersion = [version]$latest
    $skippedVersion = ''
    if (Test-Path -LiteralPath $SkipFile) {
        try {
            $skip = Get-Content -LiteralPath $SkipFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $skippedVersion = [string]$skip.version
        } catch { $skippedVersion = '' }
    }
    $skipped = ($skippedVersion -and $latest -eq $skippedVersion)
    $body = [string]$release.body
    if ($body.Length -gt 500) { $body = $body.Substring(0, 500) + '...' }

    $zipAsset = @($release.assets | Where-Object {
        $_.name -match 'public-release-v[0-9].*\.zip$'
    }) | Select-Object -First 1
    $assetUrl = ''
    $assetName = ''
    $digest = ''
    if ($zipAsset) {
        $assetUrl = [string]$zipAsset.browser_download_url
        $assetName = [string]$zipAsset.name
        $digest = [string]$zipAsset.digest
        if ($digest.StartsWith('sha256:')) {
            $digest = $digest.Substring(7)
        }
        $digest = $digest.ToLower()
    }
    $result = [ordered]@{
        current = $current
        latest = $latest
        update_available = (($latestVersion -gt $currentVersion) -and (-not $skipped))
        skipped = [bool]$skipped
        skipped_version = $skippedVersion
        body = $body
        tag = [string]$release.tag_name
        published_at = [string]$release.published_at
        zip_url = $assetUrl
        zip_name = $assetName
        asset_sha256 = $digest
        asset_available = [bool]$zipAsset
    }

    if ($StatusFile) {
        $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatusFile -Encoding UTF8
    }

    if ($Notify -and $result.update_available) {
        if (-not $Umo) {
            throw 'Notify requires -Umo qq_platform:FriendMessage:QQ_ID'
        }
        if (Test-Path -LiteralPath $tokenFile) {
            $token = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
            $message = "哥，检测到 Cyber-Butler $latest。更新说明已发布；需要管理员确认后运行 tools/update.ps1。"
            $json = @{ umo = $Umo; message = $message } | ConvertTo-Json -Compress
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($json)
            Invoke-RestMethod -Method Post -Uri 'http://127.0.0.1:6185/api/v1/im/messages' -Headers @{ Authorization = "Bearer $token" } -ContentType 'application/json; charset=utf-8' -Body $bytes -TimeoutSec 15 | Out-Null
        }
    }

    $result | ConvertTo-Json -Depth 6
    exit 0
} catch {
    $message = 'UPDATE_CHECK_FAILED: ' + $_.Exception.Message
    Write-Error $message
    exit 1
}
