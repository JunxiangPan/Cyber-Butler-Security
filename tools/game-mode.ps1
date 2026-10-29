#requires -Version 5.1
<#
AstrBot Game Mode monitor.

What it does:
  - Watches for game processes (Steam/Epic/GOG library paths + a manual name list).
  - When a game starts: stops the configured Ollama model and lowers the
    priority of the AstrBot python processes to BelowNormal.
  - When the game exits: restores AstrBot priority and reloads the model
    with keep_alive=5m (so a killed monitor still lets VRAM free eventually).
  - If AstrBot's dashboard port (6185) is unreachable, starts AstrBot again
    (with ffmpeg on PATH); retries the API provider switch every 10 seconds
    while a game is running.

Run it by double-clicking "game-mode.bat" (or "游戏模式-双击运行.bat").
Edit game-list.txt to add non-Steam game process names (without .exe).
#>
param(
    [string]$Model = "sujinyan-chat-24k:latest",
    [int]$PollSeconds = 5,
    [int]$ConfirmSamples = 2,
    [switch]$DryRun,
    [switch]$ListGames,
    [switch]$ScanLibraries,
    [switch]$PrepareOnly,
    [switch]$RestoreOnly
)

$ErrorActionPreference = "SilentlyContinue"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Runtime state/logs must not live under tools/: the hardened ACL makes tools/
# read-only to the desktop account. Keep mutable game-mode state in the owner's
# shared folder instead.
$RuntimeDir = Join-Path $env:USERPROFILE "Desktop\大肥鱼专用文件夹"
if (-not (Test-Path -LiteralPath $RuntimeDir)) {
    New-Item -ItemType Directory -Path $RuntimeDir -Force | Out-Null
}
$LogFile = Join-Path $RuntimeDir "game-mode.log"
$StateFile = Join-Path $RuntimeDir "game-mode.state.json"
$MutexName = "Local\AstrBotGameMode"
$OllamaApi = "http://127.0.0.1:11434"
# After the 2026-10-28 service migration AstrBot runs as YOUR_SERVICE_USER from a
# scheduled task. This monitor must never launch it as YOUR_USER_NAME again; the task
# supervisor owns start/restart and process priority.
$AstrBotServiceMode = $true

# AstrBot dashboard / private session routing.
$AstrBotApi = "http://127.0.0.1:6185"
$AstrBotRoot = Split-Path -Parent $ScriptDir
$AstrBotDir = Join-Path $AstrBotRoot "AstrBot"
$AstrBotPython = Join-Path $AstrBotDir ".venv\Scripts\python.exe"
$AstrBotMain = Join-Path $AstrBotDir "main.py"
$FfmpegBin = Join-Path $ScriptDir "ffmpeg-9.0.2-essentials_build\bin"
$TokenFile = Join-Path $AstrBotRoot ".astrbot_token"
$PrivateUmo = "qq_sujinyan:FriendMessage:YOUR_QQ_ID"
$LocalProvider = "local_qwen36"
$ApiProvider = "deepseek"

# Epic installs are often outside "...\Epic Games\"; read the launcher manifests.
$EpicManifestDir = "C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests"
$script:EpicInstallRoots = $null

# Paths that identify a game installed by a launcher.
$GamePathPatterns = @(
    '(?i)\\steamapps\\common\\',
    '(?i)\\Epic Games\\',
    '(?i)\\GOG Games\\',
    '(?i)\\GOG Galaxy\\Games\\',
    '(?i)\\Riot Games\\',
    '(?i)\\Blizzard Entertainment\\',
    '(?i)\\Call of Duty\\',
    '(?i)\\EA Games\\',
    '(?i)\\Ubisoft\\',
    '(?i)\\World_of_Tanks',
    '(?i)\\World_of_Warships',
    '(?i)\\World_of_Warplanes',
    '(?i)\\WarThunderDev\\',
    '(?i)\\War Thunder Dev\\',
    '(?i)\\Games\\'
)

# Process names (without .exe) for games outside the launcher libraries.
$ExtraGameProcesses = @(
    'aces', 'RainbowSix', 'RainbowSix_BE', 'RainbowSixSiege',
    'cod', 'ModernWarfare', '7DaysToDie', 'GTA5', 'PlayGTAV',
    'cs2', 'RustClient', 'DayZ', 'eu4',
    # War Thunder live / test server
    'aces-min-cpu', 'aces_BE', 'WarThunder',
    'Cities2',
    # Delta Force (Tencent CN and Steam)
    'DeltaForceClient', 'DeltaForceClient-Win64-Shipping', 'BHDClient',
    # Where Winds Meet / 燕云十六声
    'yysls', 'WhereWindsMeet',
    # Escape from Tarkov + Arena
    'EscapeFromTarkov', 'EscapeFromTarkovArena',
    # Wargaming: World of Tanks / Warships / Warplanes / Blitz (EU, CN, RU)
    'WorldOfTanks', 'WorldOfWarships', 'WorldOfWarplanes',
    'wotblitz', 'WoTBlitz', 'WorldOfTanksBlitz',
    # Battle.net titles (install path is not always under "Blizzard Entertainment")
    'Overwatch', 'Wow', 'WowClassic', 'Diablo IV', 'Diablo III',
    'Hearthstone', 'StarCraft II', 'HeroesOfTheStorm', 'Warcraft III'
)

# Heavy applications: free the local model while one of these is open.
$HeavyAppProcesses = @(
    # Adobe
    'Photoshop', 'Adobe Premiere Pro', 'Premiere Pro', 'Lightroom', 'LightroomClassic',
    'AfterFX', 'Illustrator', 'InDesign', 'Audition', 'Adobe Media Encoder', 'Media Encoder',
    'Animate', 'Dreamweaver', 'Prelude', 'Character Animator',
    'Substance Painter', 'Substance Designer',
    # Sony
    'Catalyst Browse', 'Catalyst Prepare', 'Catalyst Edit', 'CatalystRenderProcess',
    # Video / 3D / audio
    'Resolve', 'Fusion', 'obs64', 'obs32', 'HandBrake', 'HandBrakeCLI',
    'Topaz Video AI', 'Topaz Gigapixel AI', 'Topaz Photo AI',
    'blender', 'Unity', 'UnrealEditor', '3dsmax', 'maya', 'Cinema 4D', 'Houdini', 'ZBrush',
    # CAD / engineering
    'acad', 'SLDWORKS', 'Fusion360', 'Inventor', 'Revit', 'Civil3D', 'MATLAB'
)

# Always-on editors: only trigger once the process really uses memory.
$EditorProcesses = @(
    'Code', 'Code - Insiders', 'devenv', 'pycharm64', 'idea64', 'webstorm64',
    'clion64', 'rider64', 'goland64', 'studio64', 'datagrip64', 'phpstorm64', 'rubymine64'
)
$EditorMinWorkingSetMB = 1500

# Launchers and helper processes that must not count as a game.
$IgnoredProcesses = @(
    'steam', 'steamwebhelper', 'steamservice', 'steamworks',
    'epicgameslauncher', 'epicwebhelper',
    'galaxyclient', 'goggalaxy',
    'battle.net', 'agent',
    'riotclientservices', 'riotclientux',
    'origin', 'eadesktop', 'ealauncher',
    'ubisoftconnect', 'upc',
    'wegame', 'gameviewer',
    'wgc', 'wgc_api', 'wgc360_api', 'wgc_service', 'wgcservice', 'wgc_launcher',
    'lesta', 'lesta_game_center', 'lgc',
    'crashpad_handler', 'easyanticheat', 'easyanticheat_eos',
    'beservice', 'battleye', 'vgc', 'vgtray',
    'gameinputredistservice', 'gameinputrawinputproxy',
    'battle.net helper', 'battle.net launcher', 'blizzardbrowser', 'blizzarderror',
    'neacloader', 'owneacclient', 'overwatch launcher',
    'conhost', 'cmd', 'powershell', 'werfault',
    'adobe creative cloud', 'creative cloud', 'creative cloud helper',
    'ccxprocess', 'coresync', 'adobe desktop service', 'adobeipcbroker',
    'adobenotificationclient', 'crwindowsclientservice', 'crlogtransport',
    'adobegenuinevalidator', 'adobe cef helper', 'qtwebengineprocess',
    'nvidia overlay',
    'wallpaper64', 'wallpaper32', 'wallpaper_engine', 'wallpaperui',
    'wallpaperengine', 'wallpaper engine',
    'steamvr', 'vrmonitor', 'vrserver', 'vrdashboard', 'vrcompositor',
    'vcredist_x64', 'vcredist_x86', 'dxsetup', 'unins000', 'setup', 'installer'
)

# GPU fallback: these processes are known desktop/browser/helper consumers and
# must not make the monitor think a game is running.
$GpuIgnoredProcesses = @(
    'deepseek harness', 'chrome', 'msedge', 'msedgewebview2', 'firefox', 'brave',
    'opera', 'ollama', 'python', 'pythonw', 'node', 'powershell', 'pwsh',
    'dwm', 'explorer', 'taskmgr', 'searchapp', 'shellexperiencehost',
    'startmenuexperiencehost', 'textinputhost', 'gameoverlayui64',
    'obs', 'obs64', 'obs32', 'code', 'devenv', 'pycharm64', 'idea64',
    'webstorm64', 'clion64', 'rider64', 'goland64', 'studio64', 'datagrip64',
    'phpstorm64', 'rubymine64', 'wallpaper64', 'wallpaper32',
    'librehardwaremonitor', 'nvidia overlay', 'amdow', 'radeonsoftware'
)
$GpuGameThreshold = 20.0
$GameOffGraceSeconds = 45

# Optional user-maintained list: one process name per line, # starts a comment.
# Prefer the writable shared folder, with a legacy tools/ file as read-only fallback.
$ExtraListFile = Join-Path $RuntimeDir "game-list.txt"
$LegacyExtraListFile = Join-Path $ScriptDir "game-list.txt"
if (-not (Test-Path -LiteralPath $ExtraListFile) -and (Test-Path -LiteralPath $LegacyExtraListFile)) {
    $ExtraListFile = $LegacyExtraListFile
}
if (Test-Path $ExtraListFile) {
    $lines = Get-Content -Path $ExtraListFile -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        $name = $line.Trim()
        if ($name -and -not $name.StartsWith("#") -and ($ExtraGameProcesses -notcontains $name)) {
            $ExtraGameProcesses += $name
        }
    }
}

# Generated by Update-GameLibraries; do not edit by hand.
$AutoListFile = Join-Path $RuntimeDir "game-list.auto.txt"
$LibraryIndexFile = Join-Path $RuntimeDir "game-library.auto.txt"
$BattleNetLauncherNames = @('Battle.net', 'Battle.net Launcher')

function Get-AutoGameNames {
    $names = @()
    if (Test-Path $AutoListFile) {
        foreach ($line in Get-Content -Path $AutoListFile -ErrorAction SilentlyContinue) {
            $name = $line.Trim()
            if ($name -and -not $name.StartsWith("#") -and ($names -notcontains $name)) {
                $names += $name
            }
        }
    }
    return $names
}

$script:AutoGameProcesses = @(Get-AutoGameNames)
# Process IDs seen as a game/launcher. Descendants of these PIDs are treated as
# the game too, which bridges Steam -> Rockstar/other launcher -> game.exe.
$script:TrackedGamePids = @{}
$script:LastGameSeen = $null

$script:LoweredPids = @{}
$script:OriginalPriorities = @{}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Write-Host $line
    try {
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch {
    }
}

function Get-EpicInstallRoots {
    $roots = @()
    if (-not (Test-Path -LiteralPath $EpicManifestDir)) { return $roots }
    $seen = @{}
    foreach ($file in @(Get-ChildItem -LiteralPath $EpicManifestDir -Filter "*.item" -File -ErrorAction SilentlyContinue)) {
        $raw = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $raw) { continue }
        if ($raw -match '"InstallLocation"\s*:\s*"((?:[^"\\]|\\.)*)"') {
            $location = $matches[1] -replace '\\\\', '\'
            if (-not $location) { continue }
            if (-not (Test-Path -LiteralPath $location)) { continue }
            $root = $location.TrimEnd('\') + '\'
            if ($root.Length -le 3) { continue }
            $key = $root.ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $roots += $root
            }
        }
    }
    return $roots
}

function Get-SteamLibraryPaths {
    $paths = @()
    $steam = (Get-ItemProperty 'HKCU:\Software\Valve\Steam' -ErrorAction SilentlyContinue).SteamPath
    if ($steam) {
        $steam = $steam -replace '/', '\'
        $paths += $steam
        $vdf = Join-Path $steam 'steamapps\libraryfolders.vdf'
        if (Test-Path -LiteralPath $vdf) {
            foreach ($line in Get-Content -LiteralPath $vdf -ErrorAction SilentlyContinue) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $paths += ($matches[1] -replace '\\\\', '\')
                }
            }
        }
    }
    $paths += @('C:\SteamLibrary', 'D:\SteamLibrary', 'E:\steam', 'F:\SteamLibrary')

    $valid = @()
    $seen = @{}
    foreach ($path in $paths) {
        if ($path -and (Test-Path -LiteralPath (Join-Path $path 'steamapps\common'))) {
            $key = $path.TrimEnd('\').ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                $valid += $path
            }
        }
    }
    return $valid
}

function Get-SteamGames {
    $games = @()
    $seen = @{}
    foreach ($library in @(Get-SteamLibraryPaths)) {
        $common = Join-Path $library 'steamapps\common'
        foreach ($dir in @(Get-ChildItem -LiteralPath $common -Directory -ErrorAction SilentlyContinue)) {
            $key = $dir.FullName.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $games += [pscustomobject]@{
                Name = $dir.Name
                Path = $dir.FullName
            }
        }
    }
    return $games
}

function Get-BattleNetProcessNames {
    $names = @()
    $roots = @()
    $uninstallRoots = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($key in $uninstallRoots) {
        foreach ($item in @(Get-ItemProperty $key -ErrorAction SilentlyContinue)) {
            $display = [string]$item.DisplayName
            if ($display -notmatch '(?i)Blizzard|暴雪|Overwatch|Diablo|Warcraft|StarCraft|Hearthstone|Heroes of the Storm') { continue }
            if ($display -match '(?i)^Battle\.net$|战网|Launcher') { continue }

            $location = [string]$item.InstallLocation
            if (-not $location) {
                $icon = [string]$item.DisplayIcon
                if ($icon) {
                    $iconPath = $icon.Trim('"').Split(',')[0]
                    if (Test-Path -LiteralPath $iconPath) {
                        $location = Split-Path -Parent $iconPath
                    }
                }
            }
            if ($location -and (Test-Path -LiteralPath $location)) {
                $roots += $location
            }
        }
    }

    $titlePattern = '(?i)^(Overwatch|Diablo|Diablo II|Diablo III|Diablo IV|World of Warcraft|Warcraft|Warcraft III|StarCraft|StarCraft II|Hearthstone|Heroes of the Storm)$'
    foreach ($drive in @('C:\', 'D:\', 'E:\', 'F:\')) {
        if (-not (Test-Path -LiteralPath $drive)) { continue }
        foreach ($dir in @(Get-ChildItem -LiteralPath $drive -Directory -ErrorAction SilentlyContinue)) {
            if ($dir.Name -match $titlePattern) {
                $roots += $dir.FullName
            }
        }
    }

    $roots = @($roots | Select-Object -Unique)
    $ignorePattern = '(?i)(unins|uninstall|setup|installer|launcher|crash|error|helper|browser|update|repair|agent|battle\.net|neac|anti|guard|webview|cef|subprocess|recorder|ffmpeg|obs|icreate|msdk|diagnostic|report)'
    foreach ($root in $roots) {
        foreach ($exe in @(Get-ChildItem -LiteralPath $root -Filter '*.exe' -Recurse -Depth 2 -File -ErrorAction SilentlyContinue)) {
            $name = [IO.Path]::GetFileNameWithoutExtension($exe.Name)
            if (-not $name) { continue }
            if ($name -match $ignorePattern) { continue }
            $names += $name
        }
    }
    return @($names | Select-Object -Unique)
}

function Update-GameLibraries {
    $steamGames = @(Get-SteamGames)
    $epicRoots = @(Get-EpicInstallRoots)
    $battleNetNames = @(Get-BattleNetProcessNames)

    $steamMap = @{}
    foreach ($game in $steamGames) {
        $steamMap[$game.Path] = $game.Name
    }
    $oldSteamMap = $script:SteamGameMap
    $oldEpicRoots = @($script:EpicInstallRoots | Where-Object { $_ })
    $oldBattleNetNames = @($script:BattleNetNames)
    $firstScan = ($oldSteamMap.Count -eq 0 -and $oldEpicRoots.Count -eq 0 -and $oldBattleNetNames.Count -eq 0)

    $addedSteam = @($steamMap.Keys | Where-Object { -not $oldSteamMap.ContainsKey($_) })
    $removedSteam = @($oldSteamMap.Keys | Where-Object { -not $steamMap.ContainsKey($_) })
    $addedEpic = @($epicRoots | Where-Object { $oldEpicRoots -notcontains $_ })
    $removedEpic = @($oldEpicRoots | Where-Object { $epicRoots -notcontains $_ })
    $addedBattleNet = @($battleNetNames | Where-Object { $oldBattleNetNames -notcontains $_ })
    $removedBattleNet = @($oldBattleNetNames | Where-Object { $battleNetNames -notcontains $_ })

    $script:SteamGameMap = $steamMap
    $script:EpicInstallRoots = $epicRoots
    $script:BattleNetNames = $battleNetNames
    $script:AutoGameProcesses = $battleNetNames

    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $autoLines = @(
        '# Auto-generated by game-mode.ps1. Do not edit by hand.',
        "# Updated: $stamp",
        '# Battle.net process names discovered from installed games.'
    ) + $battleNetNames
    Set-Content -Path $AutoListFile -Value $autoLines -Encoding UTF8

    $index = @(
        '# Auto-generated game library index by game-mode.ps1. Do not edit by hand.',
        "# Updated: $stamp",
        '',
        "[Steam] $($steamGames.Count) games"
    )
    foreach ($game in $steamGames) {
        $index += ("{0}`t{1}" -f $game.Name, $game.Path)
    }
    $index += '', "[Epic] $($epicRoots.Count) install roots"
    foreach ($root in $epicRoots) {
        $index += $root
    }
    $index += '', "[Battle.net] $($battleNetNames.Count) process names"
    foreach ($name in $battleNetNames) {
        $index += $name
    }
    Set-Content -Path $LibraryIndexFile -Value $index -Encoding UTF8

    if ($firstScan) {
        Write-Log ("Library scan: detected Steam {0} games, Epic {1} roots, Battle.net {2} names." -f $steamGames.Count, $epicRoots.Count, $battleNetNames.Count)
    } else {
        Write-Log ("Library scan: Steam {0} games, Epic {1} roots, Battle.net {2} names (+{3}/-{4} Steam, +{5}/-{6} Epic, +{7}/-{8} Battle.net)." -f `
            $steamGames.Count, $epicRoots.Count, $battleNetNames.Count, `
            $addedSteam.Count, $removedSteam.Count, $addedEpic.Count, $removedEpic.Count, $addedBattleNet.Count, $removedBattleNet.Count)
        if ($addedSteam.Count -gt 0) { Write-Log ("New Steam games: " + (($addedSteam | ForEach-Object { $steamMap[$_] }) -join ', ')) }
        if ($addedEpic.Count -gt 0) { Write-Log ("New Epic install roots: " + ($addedEpic -join ', ')) }
        if ($addedBattleNet.Count -gt 0) { Write-Log ("New Battle.net process names: " + ($addedBattleNet -join ', ')) }
    }
}

function Get-GpuHeavyPids {
    $heavy = @{}
    try {
        $samples = (Get-Counter '\GPU Engine(*)\Utilization Percentage' -ErrorAction Stop).CounterSamples
        foreach ($sample in $samples) {
            if ($sample.InstanceName -match '^pid_(\d+)_') {
                $processId = [int]$Matches[1]
                if ($sample.InstanceName -notmatch 'engtype_(3d|compute)') { continue }
                $value = [double]$sample.CookedValue
                if ($value -ge $GpuGameThreshold -and (-not $heavy.ContainsKey($processId) -or $value -gt $heavy[$processId])) {
                    $heavy[$processId] = $value
                }
            }
        }
    } catch {
        if (-not $script:GpuCounterSkipLogged) {
            Write-Log "GPU counters unavailable; skipping GPU fallback detection."
            $script:GpuCounterSkipLogged = $true
        }
    }
    return $heavy
}

function Get-GameProcesses {
    $found = @()
    $foundIds = @{}
    $procs = Get-CimInstance Win32_Process -Filter "Name IS NOT NULL"
    $procById = @{}
    foreach ($proc in $procs) {
        $procById[[int]$proc.ProcessId] = $proc
    }
    foreach ($p in $procs) {
        $name = [IO.Path]::GetFileNameWithoutExtension($p.Name)
        if (-not $name) { continue }
        if ($IgnoredProcesses -contains $name.ToLower()) { continue }

        $path = $p.ExecutablePath
        $matched = $false
        if ($path) {
            foreach ($pattern in $GamePathPatterns) {
                if ($path -match $pattern) {
                    $matched = $true
                    break
                }
            }
        }
        if (-not $matched -and $path) {
            if ($null -eq $script:EpicInstallRoots) {
                $script:EpicInstallRoots = @(Get-EpicInstallRoots)
            }
            foreach ($root in $script:EpicInstallRoots) {
                if ($path.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $matched = $true
                    break
                }
            }
        }
        if (-not $matched -and (($ExtraGameProcesses -contains $name) -or ($script:AutoGameProcesses -contains $name))) {
            $matched = $true
        }
        if (-not $matched) {
            $parentId = 0
            if ($p.ParentProcessId) { $parentId = [int]$p.ParentProcessId }
            if ($parentId -gt 0 -and $procById.ContainsKey($parentId)) {
                $parentName = [IO.Path]::GetFileNameWithoutExtension($procById[$parentId].Name)
                if ($parentName -and ($BattleNetLauncherNames -contains $parentName)) {
                    $matched = $true
                }
            }
        }
        if (-not $matched -and ($HeavyAppProcesses -contains $name)) {
            $matched = $true
        }
        if (-not $matched -and ($EditorProcesses -contains $name)) {
            $workingSetMb = 0
            if ($p.WorkingSetSize) {
                $workingSetMb = [math]::Round(([double]$p.WorkingSetSize) / 1MB)
            }
            if ($workingSetMb -ge $EditorMinWorkingSetMB) {
                $matched = $true
            }
        }
        if ($matched) {
            $pidValue = [int]$p.ProcessId
            if (-not $foundIds.ContainsKey($pidValue)) {
                $found += [pscustomobject]@{
                    Name = $name
                    Id = $pidValue
                    Path = $path
                }
                $foundIds[$pidValue] = $true
                $script:TrackedGamePids[$pidValue] = $true
            }
        }
    }

    # Include descendants of a known game/launcher. This catches the next
    # launcher stage even when its path/name is not in any list.
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($p in $procs) {
            $pidValue = [int]$p.ProcessId
            if ($foundIds.ContainsKey($pidValue)) { continue }
            $parentId = 0
            if ($p.ParentProcessId) { $parentId = [int]$p.ParentProcessId }
            if ($parentId -le 0) { continue }
            if (-not $script:TrackedGamePids.ContainsKey($parentId)) { continue }
            $name = [IO.Path]::GetFileNameWithoutExtension($p.Name)
            if (-not $name -or $IgnoredProcesses -contains $name.ToLower()) { continue }
            $found += [pscustomobject]@{
                Name = $name
                Id = $pidValue
                Path = $p.ExecutablePath
            }
            $foundIds[$pidValue] = $true
            $script:TrackedGamePids[$pidValue] = $true
            $changed = $true
        }
    }

    # GPU fallback catches games launched by an unknown launcher (Rockstar,
    # custom launchers, etc.) without relying on executable names at all.
    $gpuHeavy = Get-GpuHeavyPids
    foreach ($pidValue in @($gpuHeavy.Keys)) {
        if ($foundIds.ContainsKey([int]$pidValue)) { continue }
        if (-not $procById.ContainsKey([int]$pidValue)) { continue }
        $p = $procById[[int]$pidValue]
        $name = [IO.Path]::GetFileNameWithoutExtension($p.Name)
        if (-not $name) { continue }
        $lower = $name.ToLower()
        if ($IgnoredProcesses -contains $lower) { continue }
        if ($GpuIgnoredProcesses -contains $lower) { continue }
        $found += [pscustomobject]@{
            Name = $name
            Id = [int]$pidValue
            Path = $p.ExecutablePath
        }
        $foundIds[[int]$pidValue] = $true
        $script:TrackedGamePids[[int]$pidValue] = $true
    }

    return $found
}

function Get-AstrBotProcesses {
    $list = @()
    $procs = Get-CimInstance Win32_Process -Filter "Name='python.exe'"
    foreach ($p in $procs) {
        if (-not $p.CommandLine) { continue }
        if ($p.CommandLine -notmatch 'AstrBot.*main\.py') { continue }
        $proc = Get-Process -Id $p.ProcessId -ErrorAction SilentlyContinue
        if ($proc) { $list += $proc }
    }
    return $list
}

function Set-AstrBotPriority {
    param([bool]$Low)
    if ($DryRun) { return }
    if ($AstrBotServiceMode) { return }

    $procs = @(Get-AstrBotProcesses)
    foreach ($proc in $procs) {
        try {
            if ($Low) {
                if (-not $script:LoweredPids.ContainsKey($proc.Id)) {
                    $script:OriginalPriorities[$proc.Id] = $proc.PriorityClass
                    $script:LoweredPids[$proc.Id] = $true
                }
                $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::BelowNormal
            } else {
                $target = [System.Diagnostics.ProcessPriorityClass]::Normal
                if ($script:OriginalPriorities.ContainsKey($proc.Id)) {
                    $target = $script:OriginalPriorities[$proc.Id]
                }
                $proc.PriorityClass = $target
                $script:LoweredPids.Remove($proc.Id)
                $script:OriginalPriorities.Remove($proc.Id)
            }
        } catch {
            Write-Log ("Priority change failed for PID {0}: {1}" -f $proc.Id, $_.Exception.Message)
        }
    }

    if (-not $Low) {
        foreach ($processId in @($script:LoweredPids.Keys)) {
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($proc) {
                try {
                    $target = [System.Diagnostics.ProcessPriorityClass]::Normal
                    if ($script:OriginalPriorities.ContainsKey($processId)) {
                        $target = $script:OriginalPriorities[$processId]
                    }
                    $proc.PriorityClass = $target
                } catch {
                }
            }
            $script:LoweredPids.Remove($processId)
            $script:OriginalPriorities.Remove($processId)
        }
    }
}

function Reset-AstrBotPriority {
    if ($DryRun) { return }
    if ($AstrBotServiceMode) { return }
    foreach ($proc in @(Get-AstrBotProcesses)) {
        try {
            $proc.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::Normal
        } catch {
        }
    }
}

function Wait-AstrBotApi {
    param([int]$Seconds = 60)
    if ($DryRun) { return $true }
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-WebRequest -Uri "$AstrBotApi/" -UseBasicParsing -TimeoutSec 2 | Out-Null
            return $true
        } catch {
            Start-Sleep -Seconds 2
        }
    }
    return $false
}

function Test-AstrBotApi {
    param([int]$TimeoutSec = 2)
    if ($DryRun) { return $true }
    try {
        $response = Invoke-WebRequest -Uri "$AstrBotApi/" -UseBasicParsing -TimeoutSec $TimeoutSec
        return ($response.StatusCode -ge 200 -and $response.StatusCode -lt 500)
    } catch {
        return $false
    }
}

function Start-AstrBot {
    if ($DryRun) {
        Write-Log "[dry-run] would start AstrBot"
        return $true
    }
    if ($AstrBotServiceMode) {
        Write-Log "AstrBot is managed by the AstrBot Service task; refusing to start it as YOUR_USER_NAME."
        return $false
    }
    if (-not (Test-Path $AstrBotPython)) {
        Write-Log ("AstrBot auto-start failed: python not found at {0}" -f $AstrBotPython)
        return $false
    }
    if (-not (Test-Path $AstrBotMain)) {
        Write-Log ("AstrBot auto-start failed: main.py not found at {0}" -f $AstrBotMain)
        return $false
    }

    if (Test-Path $FfmpegBin) {
        $env:PATH = "$FfmpegBin;$env:PATH"
    }
    # UTF-8 keeps AstrBot's emoji log lines from crashing on the GBK console.
    $env:PYTHONIOENCODING = "utf-8"
    $env:PYTHONUTF8 = "1"

    $outLog = Join-Path $AstrBotDir "data\console-watchdog.out.log"
    $errLog = Join-Path $AstrBotDir "data\console-watchdog.err.log"
    try {
        Start-Process -FilePath $AstrBotPython -ArgumentList "main.py" `
            -WorkingDirectory $AstrBotDir -WindowStyle Hidden `
            -RedirectStandardOutput $outLog -RedirectStandardError $errLog
        Write-Log ("AstrBot auto-start: launched {0}" -f $AstrBotPython)
        return $true
    } catch {
        Write-Log ("AstrBot auto-start failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Ensure-AstrBot {
    param([int]$WaitSeconds = 45)
    if ($DryRun) { return $true }
    if (Test-AstrBotApi) {
        $script:AstrBotProcessWaitLogged = $false
        return $true
    }
    if ((Get-Date) -lt $script:AstrBotLaunchNotBefore) {
        return $false
    }

    # A process may already be booting (start-bot.bat); do not launch a duplicate.
    $procs = @(Get-AstrBotProcesses)
    if ($procs.Count -gt 0) {
        if (-not $script:AstrBotProcessWaitLogged) {
            $ids = ($procs | ForEach-Object { $_.Id }) -join ", "
            Write-Log ("AstrBot process(es) running but API not ready yet: {0}" -f $ids)
            $script:AstrBotProcessWaitLogged = $true
        }
        return $false
    }

    if ((Get-Date) -lt $script:NextAstrBotLaunch) {
        return $false
    }
    if ($AstrBotServiceMode) {
        if (-not $script:AstrBotProcessWaitLogged) {
            Write-Log "AstrBot is managed by the AstrBot Service task; not auto-starting it as YOUR_USER_NAME."
            $script:AstrBotProcessWaitLogged = $true
        }
        return $false
    }
    $script:NextAstrBotLaunch = (Get-Date).AddSeconds(120)
    Write-Log "AstrBot API is not reachable and no AstrBot process is running; auto-starting it."
    if (-not (Start-AstrBot)) {
        return $false
    }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 2
        if (Test-AstrBotApi) {
            $script:AstrBotProcessWaitLogged = $false
            Write-Log "AstrBot auto-start: API is ready."
            return $true
        }
    }
    Write-Log ("AstrBot auto-start: API did not become ready within {0} seconds." -f $WaitSeconds)
    return $false
}

function Set-ChatProvider {
    param([string]$ProviderId, [switch]$Quiet)
    if ($DryRun) {
        Write-Log ("[dry-run] would set chat provider to {0}" -f $ProviderId)
        return $true
    }
    if (-not (Test-Path $TokenFile)) {
        if (-not $Quiet) {
            Write-Log ("AstrBot token file not found: {0}" -f $TokenFile)
        }
        return $false
    }
    try {
        $token = (Get-Content -Path $TokenFile -Raw).Trim()
        $body = @{
            umos = @($PrivateUmo)
            provider_id = $ProviderId
            provider_type = "chat_completion"
        } | ConvertTo-Json -Depth 4
        $response = Invoke-RestMethod -Method Patch -Uri "$AstrBotApi/api/v1/sessions/provider" -Headers @{ Authorization = "Bearer $token" } -ContentType "application/json" -Body $body -TimeoutSec 15
        if ($response.status -eq "ok") {
            Write-Log ("Chat provider set to {0}" -f $ProviderId)
            return $true
        }
        if (-not $Quiet) {
            Write-Log ("Chat provider switch failed: {0}" -f ($response | ConvertTo-Json -Compress))
        }
        return $false
    } catch {
        if (-not $Quiet) {
            Write-Log ("Chat provider switch failed: {0}" -f $_.Exception.Message)
        }
        return $false
    }
}

function Get-OllamaExe {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe"),
        "C:\Program Files\Ollama\ollama.exe"
    )
    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }
    $cmd = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    return $null
}

function Get-OllamaUnavailableReason {
    try {
        Invoke-RestMethod -Uri "$OllamaApi/api/tags" -TimeoutSec 2 | Out-Null
        return ""
    } catch {
        $exe = Get-OllamaExe
        if (-not $exe) { return "not found" }
        return "not running"
    }
}

function Stop-OllamaModel {
    if ($DryRun) {
        Write-Log ("[dry-run] would run: ollama stop {0}" -f $Model)
        return
    }

    $reason = Get-OllamaUnavailableReason
    if ($reason) {
        Write-Log ("Skipped (Ollama {0})" -f $reason)
        return
    }

    # Use the HTTP API only. The old synchronous `ollama stop` child process
    # could be terminated together with the parent console (0xC000013A) and
    # leave the monitor dead after GAME MODE ON; the HTTP keep_alive=0 call is
    # sufficient to unload the model.
    Write-Log ("Stopping Ollama model via HTTP: {0}" -f $Model)

    try {
        $body = @{
            model = $Model
            prompt = ""
            stream = $false
            keep_alive = 0
        } | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Method Post -Uri "$OllamaApi/api/generate" -Body $body -ContentType "application/json" -TimeoutSec 30 | Out-Null
        Write-Log "HTTP unload request sent"
    } catch {
        Write-Log ("HTTP unload failed: {0}" -f $_.Exception.Message)
    }

    for ($i = 0; $i -lt 10; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $ps = Invoke-RestMethod -Uri "$OllamaApi/api/ps" -TimeoutSec 3
            $still = @($ps.models | Where-Object { $_.name -eq $Model -or $_.model -eq $Model })
            if ($still.Count -eq 0) {
                Write-Log "Ollama model unloaded; VRAM should be released."
                return
            }
        } catch {
            Write-Log ("Ollama ps check failed: {0}" -f $_.Exception.Message)
            return
        }
    }
    Write-Log ("WARNING: Ollama model still resident after unload: {0}" -f $Model)
}

function Start-OllamaIfNeeded {
    $reason = Get-OllamaUnavailableReason
    if ($reason) {
        Write-Log ("Skipped (Ollama {0})" -f $reason)
        return $false
    }
    return $true
}

function Wake-OllamaModel {
    if ($DryRun) {
        Write-Log ("[dry-run] would wake model: {0}" -f $Model)
        return $true
    }
    # AstrBot runs as YOUR_SERVICE_USER, so YOUR_USER_NAME cannot read its process command
    # line. Use the local HTTP API as the source of truth instead.
    if (-not (Test-AstrBotApi)) {
        Write-Log "AstrBot API is not reachable; skip model wake."
        return $false
    }
    $reason = Get-OllamaUnavailableReason
    if ($reason) {
        Write-Log ("Skipped (Ollama {0})" -f $reason)
        return $false
    }

    Write-Log ("Waking Ollama model: {0}" -f $Model)
    try {
        $body = @{
            model = $Model
            prompt = "hi"
            stream = $false
            keep_alive = '5m'
            options = @{ num_predict = 1 }
        } | ConvertTo-Json -Depth 6
        $response = Invoke-RestMethod -Method Post -Uri "$OllamaApi/api/generate" -Body $body -ContentType "application/json" -TimeoutSec 180
        Write-Log ("Model wake finished: {0}" -f $response.response)
        return $true
    } catch {
        Write-Log ("Model wake failed: {0}" -f $_.Exception.Message)
        return $false
    }
}

function Enter-GameMode {
    param($Games)
    $names = ($Games | ForEach-Object { "{0}({1})" -f $_.Name, $_.Id }) -join ", "
    Write-Log ("GAME MODE ON. Detected: {0}" -f $names)
    try {
        @{
            active = $true
            started_at = (Get-Date).ToString("o")
            games = @($Games | ForEach-Object { @{ name = $_.Name; id = $_.Id } })
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateFile -Encoding UTF8
    } catch {
        Write-Log ("State write failed: {0}" -f $_.Exception.Message)
    }
    $script:LastGameSeen = Get-Date
    $script:GameProviderActive = Set-ChatProvider -ProviderId $ApiProvider
    if (-not $script:GameProviderActive) {
        Write-Log "Chat provider could not be switched to API; local model will still be stopped."
        $script:NextGameProviderRetry = (Get-Date).AddSeconds(10)
    }
    Set-AstrBotPriority -Low $true
    Stop-OllamaModel
}

function Exit-GameMode {
    Write-Log "GAME MODE OFF. Restoring AstrBot priority and waking the model."
    try {
        @{
            active = $false
            ended_at = (Get-Date).ToString("o")
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $StateFile -Encoding UTF8
    } catch {
        Write-Log ("State write failed: {0}" -f $_.Exception.Message)
    }
    Set-AstrBotPriority -Low $false
    $woke = Wake-OllamaModel
    if ($woke) {
        if (Set-ChatProvider -ProviderId $LocalProvider) {
            $script:StartupSynced = $true
        }
    } else {
        Write-Log "Model wake unavailable (cloud mode); keeping the API provider so chat can still reply."
        Set-ChatProvider -ProviderId $ApiProvider | Out-Null
    }
    $script:GameProviderActive = $false
    $script:TrackedGamePids.Clear()
    $script:LastGameSeen = $null
}

if ($ListGames) {
    $games = @(Get-GameProcesses)
    if ($games.Count -eq 0) {
        Write-Host "No game processes detected."
    } else {
        $games | Format-Table Name, Id, Path -AutoSize
    }
    exit 0
}

if (Test-Path $LogFile) {
    if ((Get-Item $LogFile).Length -gt 1048576) {
        Move-Item -Path $LogFile -Destination ($LogFile + ".old") -Force
    }
}

$mutex = New-Object System.Threading.Mutex($false, $MutexName)
$owned = $false
$gameActive = $false
$gameStreak = 0
$idleStreak = 0
$script:StartupSynced = $false
$script:NextStartupSync = Get-Date
$script:GameProviderActive = $false
$script:NextGameProviderRetry = Get-Date
$script:NextAstrBotCheck = Get-Date
$script:NextAstrBotLaunch = Get-Date
$script:AstrBotLaunchNotBefore = (Get-Date).AddSeconds(20)
$script:AstrBotProcessWaitLogged = $false
$script:AstrBotOnline = $false
$script:LastProviderFailureLog = Get-Date
$script:SteamGameMap = @{}
$script:BattleNetNames = @()
$script:NextLibraryScan = Get-Date

# One-shot safe mode: no background monitor runs while a kernel anti-cheat game is open.
if ($ScanLibraries) {
    Update-GameLibraries
    Write-Host ("Library scan finished. Index: {0}" -f $LibraryIndexFile)
    exit 0
}

if ($PrepareOnly -or $RestoreOnly) {
    if ($PrepareOnly -and $RestoreOnly) {
        Write-Host "Choose either -PrepareOnly or -RestoreOnly, not both."
        exit 1
    }
    $otherMonitors = @(Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.ProcessId -ne $PID -and
            $_.CommandLine -like '*-File*game-mode.ps1*' -and
            $_.CommandLine -notlike '*-Command*'
        })
    if ($otherMonitors.Count -gt 0) {
        Write-Host "A game-mode monitor is already running. Close it before using -PrepareOnly / -RestoreOnly."
        exit 1
    }
    $script:AstrBotLaunchNotBefore = Get-Date

    if ($PrepareOnly) {
        Write-Log "Prepare-only: stopping the local model and switching chat to the API provider."
        if (-not (Test-AstrBotApi)) {
            Ensure-AstrBot -WaitSeconds 45 | Out-Null
            Wait-AstrBotApi -Seconds 10 | Out-Null
        }
        if (-not (Set-ChatProvider -ProviderId $ApiProvider)) {
            Write-Log "Prepare-only: provider switch failed; start AstrBot and retry if you need chat during the game."
        }
        Set-AstrBotPriority -Low $true
        Stop-OllamaModel
        Write-Log "Prepare-only finished. No monitor is running now; run -RestoreOnly after the game."
        exit 0
    }

    Write-Log "Restore-only: restoring priority, waking the model and switching chat back."
    if (-not (Test-AstrBotApi)) {
        Ensure-AstrBot -WaitSeconds 45 | Out-Null
        Wait-AstrBotApi -Seconds 10 | Out-Null
    }
    Set-AstrBotPriority -Low $false
    $woke = Wake-OllamaModel
    if ($woke) {
        Set-ChatProvider -ProviderId $LocalProvider | Out-Null
    } else {
        Write-Log "Restore-only: model wake unavailable (cloud mode); keeping the API provider so chat can still reply."
        Set-ChatProvider -ProviderId $ApiProvider | Out-Null
    }
    Write-Log "Restore-only finished."
    exit 0
}

try {
    $owned = $mutex.WaitOne(0)
    if (-not $owned) {
        Write-Host "Another game-mode monitor is already running."
        exit 1
    }

    Write-Log ("Game mode monitor started. Model={0}, poll={1}s, confirm={2} samples, dry-run={3}" -f $Model, $PollSeconds, $ConfirmSamples, $DryRun)
    Write-Log ("AstrBot API reachable at startup: {0}" -f (Test-AstrBotApi))
    Update-GameLibraries
    $script:NextLibraryScan = (Get-Date).AddHours(1)

    # Recover from a previous monitor that was closed while a game was running.
    $initialGames = @(Get-GameProcesses)
    if ($initialGames.Count -eq 0) {
        Reset-AstrBotPriority
        if (Ensure-AstrBot -WaitSeconds 45) {
            Set-ChatProvider -ProviderId $LocalProvider | Out-Null
            Wake-OllamaModel | Out-Null
            $script:StartupSynced = $true
        } else {
            Write-Log "AstrBot API not reachable at startup; watchdog will keep trying."
        }
    } else {
        $script:AstrBotLaunchNotBefore = (Get-Date).AddSeconds(10)
        $initialNames = ($initialGames | ForEach-Object { "{0}({1})" -f $_.Name, $_.Id }) -join ", "
        Write-Log ("Game already running at startup: {0}" -f $initialNames)
    }

    while ($true) {
        if ((Get-Date) -ge $script:NextLibraryScan) {
            Update-GameLibraries
            $script:NextLibraryScan = (Get-Date).AddHours(1)
        }
        $games = @(Get-GameProcesses)

        if ($games.Count -gt 0) {
            $idleStreak = 0
            $gameStreak++
            $script:LastGameSeen = Get-Date
            if (-not $gameActive -and $gameStreak -ge $ConfirmSamples) {
                Enter-GameMode -Games $games
                $gameActive = $true
            }
        } else {
            $gameStreak = 0
            $idleStreak++
            $sinceLast = 999
            if ($script:LastGameSeen) {
                $sinceLast = ((Get-Date) - $script:LastGameSeen).TotalSeconds
            }
            if ($gameActive -and $idleStreak -ge $ConfirmSamples -and $sinceLast -ge $GameOffGraceSeconds) {
                Exit-GameMode
                $gameActive = $false
            }
        }

        $astrbotReady = $false
        if ((Get-Date) -ge $script:NextAstrBotCheck) {
            $astrbotReady = Ensure-AstrBot
            $script:NextAstrBotCheck = (Get-Date).AddSeconds(15)
            if ($astrbotReady -and -not $script:AstrBotOnline) {
                $script:AstrBotOnline = $true
                $script:NextStartupSync = Get-Date
                if ($gameActive -and -not $script:GameProviderActive) {
                    # AstrBot just came up: switch the provider immediately.
                    $script:NextGameProviderRetry = Get-Date
                }
            } elseif (-not $astrbotReady) {
                $script:AstrBotOnline = $false
            }
        }

        if ($gameActive -and -not $script:GameProviderActive) {
            if ((Get-Date) -ge $script:NextGameProviderRetry) {
                if (Set-ChatProvider -ProviderId $ApiProvider -Quiet) {
                    $script:GameProviderActive = $true
                } else {
                    $now = Get-Date
                    if (($now - $script:LastProviderFailureLog).TotalSeconds -ge 60) {
                        Write-Log "Provider switch is still failing; retrying every 10 seconds."
                        $script:LastProviderFailureLog = $now
                    }
                }
                $script:NextGameProviderRetry = (Get-Date).AddSeconds(10)
            }
        }

        if (-not $gameActive -and -not $script:StartupSynced) {
            if ((Get-Date) -ge $script:NextStartupSync) {
                if (Wait-AstrBotApi -Seconds 5) {
                    Set-ChatProvider -ProviderId $LocalProvider | Out-Null
                    Wake-OllamaModel | Out-Null
                    $script:StartupSynced = $true
                }
                $script:NextStartupSync = (Get-Date).AddSeconds(60)
            }
        }

        if ($gameActive -and -not $DryRun) {
            Set-AstrBotPriority -Low $true
        }

        Start-Sleep -Seconds $PollSeconds
    }
} finally {
    if ($gameActive) {
        Exit-GameMode
    }
    if ($owned) {
        try { $mutex.ReleaseMutex() } catch {}
    }
    $mutex.Dispose()
}
