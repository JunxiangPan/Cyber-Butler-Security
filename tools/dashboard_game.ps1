#Requires -Version 5.1
<#
Deep local game-library scanner for the Cyber-Butler dashboard.

Read-only discovery:
  * Steam: libraryfolders.vdf + appmanifest_*.acf + install-directory exe scan
  * Epic: launcher .item JSON manifests
  * WeGame: common install roots/registry + bounded exe scan

The only write is an optional game-list.auto.txt update; game-list.txt is never
touched.
#>
param(
    [string]$ProjectRoot = '',
    [string]$StatusFile = '',
    [int]$MaxDepth = 3,
    [switch]$WriteAuto
)

$ErrorActionPreference = 'Continue'
$root = if ($ProjectRoot) { (Resolve-Path -LiteralPath $ProjectRoot).Path } else { Split-Path -Parent $PSScriptRoot }
$tools = Join-Path $root 'tools'
$autoFile = Join-Path $root 'AstrBot\data\game-list.auto.txt'
$scanLog = Join-Path $root 'logs\dashboard_game.log'
$ignore = @(
    'unins', 'uninstall', 'setup', 'installer', 'launcher', 'crash', 'error',
    'helper', 'browser', 'update', 'repair', 'agent', 'steam', 'steamwebhelper',
    'epicgameslauncher', 'epicwebhelper', 'wallpaper', 'easyanticheat',
    'battleye', 'beclient', 'behelper', 'vgc', 'vgtray', 'anticheat',
    'cef', 'webview', 'crashpad', 'report', 'diagnostic', 'obs', 'ffmpeg'
)

function Write-ScanLog([string]$message) {
    try {
        New-Item -ItemType Directory -Path (Split-Path -Parent $scanLog) -Force -ErrorAction SilentlyContinue | Out-Null
        Add-Content -LiteralPath $scanLog -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message) -Encoding UTF8
    } catch { }
}

function Write-ScanStatus([string]$stage, [int]$progress, [string]$message) {
    if (-not $StatusFile) { return }
    try {
        $parent = Split-Path -Parent $StatusFile
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $state = [ordered]@{ stage = $stage; progress = $progress; message = $message; updated_at = (Get-Date).ToString('o') }
        [IO.File]::WriteAllText($StatusFile, ($state | ConvertTo-Json -Compress), (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function Read-VdfValue([string]$line, [string]$key) {
    $m = [regex]::Match($line, '"' + [regex]::Escape($key) + '"\s+"([^"]*)"')
    if ($m.Success) { return $m.Groups[1].Value -replace '\\\\', '\' }
    return ''
}

function Get-SteamLibraries {
    $paths = New-Object System.Collections.Generic.List[string]
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if (-not $steam) {
        $steam = (Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam' -ErrorAction SilentlyContinue).InstallPath
    }
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $paths.Add($steam)
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            try {
                foreach ($line in @(Get-Content -LiteralPath $vdf -Encoding UTF8 -ErrorAction Stop)) {
                    if ($line -match '"path"') {
                        $value = Read-VdfValue $line 'path'
                        if ($value) { $paths.Add($value.Replace('\\', '\')) }
                    }
                }
            } catch { Write-ScanLog ('跳过损坏的 Steam libraryfolders.vdf：' + $vdf) }
        }
    }
    foreach ($candidate in @('C:\SteamLibrary', 'D:\SteamLibrary', 'E:\SteamLibrary', 'F:\SteamLibrary')) {
        if (Test-Path (Join-Path $candidate 'steamapps\common')) { $paths.Add($candidate) }
    }
    return @($paths | Where-Object { $_ -and (Test-Path (Join-Path $_ 'steamapps')) } | Select-Object -Unique)
}

function Get-ExeNames([string]$installPath, [string]$source) {
    $result = @()
    if (-not $installPath -or -not (Test-Path -LiteralPath $installPath)) { return @() }
    try {
        $files = @(Get-ChildItem -LiteralPath $installPath -Recurse -Depth $MaxDepth -Filter '*.exe' -File -ErrorAction SilentlyContinue)
        foreach ($file in $files) {
            $name = [IO.Path]::GetFileNameWithoutExtension($file.Name)
            if (-not $name) { continue }
            $lower = $name.ToLowerInvariant()
            if ($ignore | Where-Object { $lower -like ('*' + $_ + '*') }) { continue }
            if ($file.FullName -match '(?i)\\(_CommonRedist|EasyAntiCheat|BattlEye|AntiCheat|CrashReport|ThirdParty)\\') { continue }
            $result += [pscustomobject]@{ Name = $name; Exe = $file.FullName; Source = $source }
        }
    } catch { }
    return @($result)
}

function Get-SteamGames {
    $games = @()
    $libraries = @(Get-SteamLibraries)
    foreach ($library in $libraries) {
        $manifestDir = Join-Path $library 'steamapps'
        foreach ($manifest in @(Get-ChildItem -LiteralPath $manifestDir -Filter 'appmanifest_*.acf' -File -ErrorAction SilentlyContinue)) {
            try {
                $text = Get-Content -LiteralPath $manifest.FullName -Raw -Encoding UTF8 -ErrorAction Stop
                $appid = ([regex]::Match($text, '"appid"\s+"([^"]+)"')).Groups[1].Value
                $name = ([regex]::Match($text, '"name"\s+"([^"]+)"')).Groups[1].Value
                $folder = ([regex]::Match($text, '"installdir"\s+"([^"]+)"')).Groups[1].Value
                $install = if ($folder) { Join-Path $library ('steamapps\common\' + $folder) } else { '' }
                $exes = @(Get-ExeNames $install 'Steam')
                $games += [pscustomobject]@{ Name = $name; AppId = $appid; InstallPath = $install; ExeCandidates = @($exes) }
            } catch { }
        }
    }
    return @($games)
}

function Get-EpicGames {
    $manifests = @(Get-ChildItem -LiteralPath 'C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests' -Filter '*.item' -File -ErrorAction SilentlyContinue)
    $games = @()
    foreach ($manifest in $manifests) {
        try {
            $data = Get-Content -LiteralPath $manifest.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            if ($null -eq $data) { continue }
            $name = [string]$data.DisplayName
            $install = [string]$data.InstallLocation
            $launch = [string]$data.LaunchExecutable
            $exes = @()
            if ($launch) {
                $exeName = [IO.Path]::GetFileNameWithoutExtension($launch.Trim('"'))
                if ($exeName) { $exes += [pscustomobject]@{ Name = $exeName; Exe = (Join-Path $install $launch); Source = 'Epic' } }
            }
            if ($exes.Count -eq 0) { $exes = @(Get-ExeNames $install 'Epic') }
            $games += [pscustomobject]@{ Name = $name; AppId = [string]$data.AppName; InstallPath = $install; ExeCandidates = @($exes) }
        } catch { }
    }
    return @($games)
}

function Get-WeGameGames {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($p in @(
        'C:\Program Files (x86)\Tencent\WeGame',
        'C:\Program Files\Tencent\WeGame',
        'D:\Program Files (x86)\Tencent\WeGame',
        'D:\Program Files\Tencent\WeGame'
    )) { if (Test-Path -LiteralPath $p) { $roots.Add($p) } }
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $uninstallRoots) {
        foreach ($item in @(Get-ItemProperty $key -ErrorAction SilentlyContinue)) {
            if (([string]$item.DisplayName) -match '(?i)wegame|腾讯游戏平台' -and $item.InstallLocation) {
                $roots.Add([string]$item.InstallLocation)
            }
        }
    }
    $games = @()
    foreach ($base in @($roots | Select-Object -Unique)) {
        $exes = @(Get-ExeNames $base 'WeGame')
        if ($exes.Count -gt 0) {
            $games += [pscustomobject]@{ Name = 'WeGame 游戏'; AppId = ''; InstallPath = $base; ExeCandidates = $exes }
        }
    }
    return @($games)
}

try {
    Write-ScanStatus 'starting' 5 '正在扫描游戏库...'
    Write-ScanStatus 'steam' 20 '正在解析 Steam 库...'
    $steamGames = @(Get-SteamGames)
    Write-ScanStatus 'epic' 45 '正在解析 Epic 清单...'
    $epicGames = @(Get-EpicGames)
    Write-ScanStatus 'wegame' 65 '正在检测 WeGame...'
    $wegameGames = @(Get-WeGameGames)
    $all = @()
    foreach ($g in @($steamGames + $epicGames + $wegameGames)) {
        foreach ($x in @($g.ExeCandidates)) {
            if ($x.Name) { $all += [pscustomobject]@{ Name = $x.Name; Source = $x.Source; Game = $g.Name } }
        }
    }
    $all = @($all | Sort-Object Name -Unique)
    $autoWritten = $false
    if ($WriteAuto) {
        try {
            if (Test-Path -LiteralPath $autoFile) {
                try { Copy-Item -LiteralPath $autoFile -Destination ($autoFile + '.bak-dashboard') -Force -ErrorAction Stop }
                catch { Write-ScanLog ('跳过自动白名单备份：' + $_.Exception.Message) }
            }
            $lines = @(
                '# Auto-generated by dashboard_game.ps1. Do not edit by hand.',
                ('# Updated: ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
                ('# Steam: ' + $steamGames.Count + ' | Epic: ' + $epicGames.Count + ' | WeGame: ' + $wegameGames.Count)
            ) + @($all | ForEach-Object { $_.Name })
            $lines | Set-Content -LiteralPath $autoFile -Encoding UTF8 -ErrorAction Stop
            $autoWritten = $true
        } catch {
            Write-ScanLog ('自动白名单写入被拒绝，仅显示扫描结果：' + $_.Exception.Message)
        }
    }
    $result = [ordered]@{
        status = 'ok'
        steam = $steamGames.Count
        epic = $epicGames.Count
        wegame = $wegameGames.Count
        exeCandidates = $all.Count
        auto_written = $autoWritten
        names = @($all | ForEach-Object { $_.Name })
        games = @($steamGames + $epicGames + $wegameGames | ForEach-Object { $_.Name })
        updated_at = (Get-Date).ToString('o')
    }
    Write-ScanStatus 'done' 100 ('扫描完成：Steam ' + $steamGames.Count + ' / Epic ' + $epicGames.Count + ' / WeGame ' + $wegameGames.Count)
    if ($StatusFile) { $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatusFile -Encoding UTF8 }
    $result | ConvertTo-Json -Depth 6
    exit 0
} catch {
    $message = '扫描失败：' + $_.Exception.Message
    Write-ScanStatus 'failed' 100 $message
    $failed = [ordered]@{ status = 'failed'; error = $_.Exception.Message; message = $message }
    if ($StatusFile) {
        try { $failed | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StatusFile -Encoding UTF8 }
        catch { }
    }
    $failed | ConvertTo-Json -Depth 4
    exit 1
}
