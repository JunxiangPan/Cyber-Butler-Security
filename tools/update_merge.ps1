#Requires -RunAsAdministrator
<#
Production-safe updater with local overlay rendering.

The public package is sanitized. Runtime files are rendered with values from
local-overlay.json before any live file is replaced. Protected data/config/token
paths cause the whole package to be rejected.
#>
[CmdletBinding()]
param(
    [string]$Repo = 'JunxiangPan/Cyber-Butler-Security',
    [string]$AssetUrl = '',
    [string]$ExpectedSha256 = '',
    [string]$LocalZip = '',
    [string]$TargetRoot = '',
    [string]$OverlayPath = '',
    [string]$OverlayValuesPath = '',
    [string]$ConfirmationText = '',
    [string]$StatusFile = '',
    [string]$PythonPath = '',
    [switch]$BootstrapOverlay,
    [switch]$DryRun,
    [switch]$Yes,
    [switch]$AllowLocalCodeChanges
)

$ErrorActionPreference = 'Stop'
$sourceRoot = Split-Path -Parent $PSScriptRoot
if ($TargetRoot) {
    $root = (Resolve-Path -LiteralPath $TargetRoot).Path
} else {
    $root = $sourceRoot
}
$root = $root.TrimEnd('\')
$sourceRoot = $sourceRoot.TrimEnd('\')
$isLive = [string]::Equals($root, $sourceRoot, [StringComparison]::OrdinalIgnoreCase)
if (-not $OverlayPath) { $OverlayPath = Join-Path $root 'local-overlay.json' }
$OverlayPath = [IO.Path]::GetFullPath($OverlayPath)
if ($PythonPath) {
    $python = (Resolve-Path -LiteralPath $PythonPath).Path
} else {
    $python = Join-Path $sourceRoot 'AstrBot\.venv\Scripts\python.exe'
}
$updateCore = Join-Path $root 'tools\update_core.py'
$mergeCore = Join-Path $sourceRoot 'tools\update_merge_core.py'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path $env:TEMP ('cyber-butler-merge-' + $stamp)
$zip = Join-Path $work 'release.zip'
$stage = Join-Path $work 'staging'
$renderedManifest = Join-Path $work 'rendered-manifest.json'
if ($DryRun) {
    $backup = Join-Path $env:TEMP ('cyber-butler-merge-dry-' + $stamp)
} else {
    $backup = Join-Path $root ('backups\auto-merge-' + $stamp)
}
$log = Join-Path $backup 'update.log'
$backupCode = Join-Path $backup 'code'
$backupOverlay = Join-Path $backup 'local-overlay.json'

function Write-Status([string]$stage, [int]$progress, [string]$message) {
    if (-not $StatusFile) { return }
    try {
        $parent = Split-Path -Parent $StatusFile
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        $state = [ordered]@{
            stage = $stage
            progress = $progress
            message = $message
            updated_at = (Get-Date).ToString('o')
        }
        $json = $state | ConvertTo-Json -Compress
        [IO.File]::WriteAllText($StatusFile, $json, (New-Object Text.UTF8Encoding($false)))
    } catch { }
}

function Write-UpdateLog([string]$message) {
    try {
        New-Item -ItemType Directory -Path $backup -Force | Out-Null
        $line = '[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $message
        Add-Content -LiteralPath $log -Value $line -Encoding UTF8
        Write-Host $line
    } catch { }
}

function Test-Health([string]$url) {
    try {
        return (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 5).StatusCode -eq 200
    } catch { return $false }
}

function Wait-Health([string]$name, [string]$url, [int]$seconds = 45) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Health $url) {
            Write-UpdateLog ($name + ' health OK')
            return $true
        }
        Start-Sleep -Seconds 2
    }
    Write-UpdateLog ($name + ' health FAILED: ' + $url)
    return $false
}

function Get-LatestAsset {
    $headers = @{
        'User-Agent' = 'Cyber-Butler-Merge/1.0'
        'Accept' = 'application/vnd.github+json'
    }
    if ($env:GITHUB_TOKEN) { $headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN }
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $headers -TimeoutSec 20
    $asset = @($release.assets | Where-Object { $_.name -match 'public-release-v[0-9].*\.zip$' }) |
        Select-Object -First 1
    if (-not $asset) { throw 'latest release has no public-release-v*.zip asset' }
    $digest = [string]$asset.digest
    if ($digest.StartsWith('sha256:')) { $digest = $digest.Substring(7) }
    return [pscustomobject]@{
        Url = [string]$asset.browser_download_url
        Sha256 = $digest.ToLower()
        Tag = [string]$release.tag_name
    }
}

function Get-TreeFingerprint([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return 'MISSING' }
    $parts = Get-ChildItem -LiteralPath $path -Recurse -File | Sort-Object FullName | ForEach-Object {
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        $_.FullName.Substring($path.Length) + '|' + $_.Length + '|' + $hash
    }
    return ($parts -join "`n")
}

function Stop-LiveProcesses {
    Get-CimInstance Win32_Process -Filter "Name='python.exe'" -ErrorAction SilentlyContinue |
        Where-Object {
            $_.CommandLine -and (
                $_.CommandLine -match 'AstrBot.*main\.py' -or
                $_.CommandLine -match 'tools[\\/]broker\.py'
            )
        } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
}

function Set-OverlayAcl {
    $serviceUser = 'AstrBot_User'
    try {
        $overlay = Get-Content -LiteralPath $OverlayPath -Raw | ConvertFrom-Json
        if ($overlay.values.YOUR_SERVICE_USER) { $serviceUser = [string]$overlay.values.YOUR_SERVICE_USER }
    } catch { }
    try {
        & icacls $OverlayPath /inheritance:r /grant:r "${env:USERNAME}:(F)" "SYSTEM:(F)" "*S-1-5-32-544:(F)" /deny "${serviceUser}:(F)" | Out-Null
        Write-UpdateLog ('overlay ACL restricted; denied=' + $serviceUser)
    } catch {
        Write-UpdateLog ('overlay ACL failed: ' + $_.Exception.Message)
    }
}

function Get-BootstrapValues {
    $qq = ''
    $gate = Join-Path $root 'AstrBot\data\config\astrbot_plugin_at_gate_config.json'
    if (Test-Path -LiteralPath $gate) {
        try {
            $cfg = Get-Content -LiteralPath $gate -Raw | ConvertFrom-Json
            if ($cfg.owner_ids) { $qq = ([string]$cfg.owner_ids).Split(',')[0].Trim() }
        } catch { }
    }
    $broker = Join-Path $root 'tools\broker.py'
    $serviceUser = 'AstrBot_User'
    $shared = Join-Path $env:USERPROFILE 'Desktop\大肥鱼专用文件夹'
    $platform = 'qq_sujinyan'
    if (Test-Path -LiteralPath $broker) {
        $text = Get-Content -LiteralPath $broker -Raw
        $m = [regex]::Match($text, 'UMO\s*=\s*"qq_([^:]+):')
        if ($m.Success) { $platform = 'qq_' + $m.Groups[1].Value }
        $m = [regex]::Match($text, 'SHARED\s*=\s*Path\(r"(.*?)"\)')
        if ($m.Success) { $shared = $m.Groups[1].Value }
        $m = [regex]::Match($text, 'SYSTEM:\(F\)",\s*"([^"(]+):\(R\)')
        if ($m.Success) { $serviceUser = $m.Groups[1].Value }
    }
    return [ordered]@{
        YOUR_PROJECT_PATH = $root
        YOUR_USER_PATH = $env:USERPROFILE
        YOUR_USER_NAME = $env:USERNAME
        YOUR_QQ_ID = $qq
        YOUR_SERVICE_USER = $serviceUser
        YOUR_SERVICE_PATH = $env:SystemRoot
        YOUR_HOST = '127.0.0.1'
        YOUR_PLATFORM_ID = $platform
        YOUR_SHARED_FOLDER = $shared
        YOUR_TOTP_VAULT = (Join-Path $env:USERPROFILE 'Documents\苏瑾言TOTP保险箱')
        YOUR_LOCAL_MODEL = 'sujinyan-chat-24k:latest'
        YOUR_AGENT_NAME = '苏瑾言'
        YOUR_NAME = '苏瑾言'
    }
}

try {
    if (-not (Test-Path -LiteralPath $python)) { throw "Python not found: $python" }
    if (-not (Test-Path -LiteralPath $updateCore)) { throw "update_core.py not found: $updateCore" }
    if (-not (Test-Path -LiteralPath $mergeCore)) { throw "update_merge_core.py not found: $mergeCore" }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'AstrBot'))) { throw "TargetRoot does not contain AstrBot: $root" }
    if (-not $isLive -and -not (Test-Path -LiteralPath (Join-Path $root 'AstrBot\data'))) {
        throw "non-live TargetRoot must contain AstrBot/data: $root"
    }

    if ($BootstrapOverlay) {
        $values = $null
        if ($OverlayValuesPath) {
            $values = Get-Content -LiteralPath $OverlayValuesPath -Raw | ConvertFrom-Json
        } else {
            $values = Get-BootstrapValues
        }
        $valuesPath = Join-Path $work 'overlay-values.json'
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        $values | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $valuesPath -Encoding UTF8
        & $python $mergeCore bootstrap --target $root --out $OverlayPath --values $valuesPath
        if ($LASTEXITCODE -ne 0) { throw 'overlay bootstrap failed' }
        Set-OverlayAcl
        Write-UpdateLog ('LOCAL_OVERLAY_READY ' + $OverlayPath)
        exit 0
    }

    if ($isLive -and -not $DryRun) {
        if ($ConfirmationText) {
            if ($ConfirmationText -cne 'UPDATE PRODUCTION') { throw 'production confirmation rejected' }
            Write-UpdateLog 'production confirmation accepted'
        } else {
            $answer = Read-Host 'This will replace PRODUCTION code. Type UPDATE PRODUCTION to continue'
            if ($answer -cne 'UPDATE PRODUCTION') { throw 'production confirmation rejected' }
        }
    } elseif (-not $DryRun -and -not $Yes) {
        $answer = Read-Host ('This will replace code under ' + $root + '. Type UPDATE to continue')
        if ($answer -ne 'UPDATE') { throw 'update cancelled' }
    }

    $localZipSource = ''
    if ($LocalZip) {
        if ($isLive -and -not $DryRun) { throw 'LocalZip is only allowed for a non-live TargetRoot or a DryRun' }
        $localZipSource = (Resolve-Path -LiteralPath $LocalZip).Path
        $ExpectedSha256 = (Get-FileHash -LiteralPath $localZipSource -Algorithm SHA256).Hash.ToLower()
    } else {
        if (-not $AssetUrl) {
            $latest = Get-LatestAsset
            $AssetUrl = $latest.Url
            if (-not $ExpectedSha256) { $ExpectedSha256 = $latest.Sha256 }
        }
        if (-not $ExpectedSha256) { throw 'No trusted SHA-256 available' }
        $uri = [Uri]$AssetUrl
        if ($uri.Scheme -ne 'https') { throw 'asset URL must use HTTPS' }
    }

    if (-not (Test-Path -LiteralPath $OverlayPath)) { throw "local-overlay.json missing; run -BootstrapOverlay first: $OverlayPath" }
    New-Item -ItemType Directory -Path $work -Force | Out-Null
    Write-Status 'starting' 5 '正在准备更新...'
    Write-UpdateLog ('target=' + $root)
    Write-UpdateLog ('live=' + $isLive + ' dry_run=' + [bool]$DryRun)
    Write-Status 'downloading' 15 '正在下载更新包...'
    if ($localZipSource) {
        Write-UpdateLog 'source=local-sandbox-package'
        Copy-Item -LiteralPath $localZipSource -Destination $zip -Force
    } else {
        Write-UpdateLog 'source=github-release'
        Invoke-WebRequest -Uri $AssetUrl -OutFile $zip -UseBasicParsing -TimeoutSec 300
    }
    Write-Status 'verifying' 30 '正在校验 SHA-256...'
    $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $ExpectedSha256.ToLower()) { throw 'downloaded asset SHA-256 mismatch' }
    Write-UpdateLog ('asset sha256 verified: ' + $actual)

    Write-Status 'extracting' 40 '正在解压并校验清单...'
    & $python $updateCore extract --zip $zip --dest $stage
    if ($LASTEXITCODE -ne 0) { throw 'update_core rejected the archive' }
    $manifestPath = Join-Path $stage 'update-manifest.json'
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $newVersion = [string]$manifest.version
    $files = @($manifest.files)
    if (-not $newVersion -or $files.Count -eq 0) { throw 'manifest has no version or files' }
    Write-UpdateLog ('manifest verified: version ' + $newVersion + ', files ' + $files.Count)

    & $python $mergeCore verify-protected --manifest $manifestPath
    if ($LASTEXITCODE -ne 0) { throw 'package contains protected paths' }

    & $python $mergeCore check-baseline --target $root --overlay $OverlayPath
    $baselineCode = $LASTEXITCODE
    if ($baselineCode -eq 2) {
        if (-not $AllowLocalCodeChanges) { throw 'local code changes detected; pass -AllowLocalCodeChanges to overwrite' }
        Write-UpdateLog 'local code changes explicitly allowed'
    } elseif ($baselineCode -ne 0) {
        throw 'overlay baseline verification failed'
    }

    Write-Status 'rendering' 55 '正在渲染本地配置...'
    & $python $mergeCore render --staging $stage --manifest $manifestPath --overlay $OverlayPath --out $renderedManifest
    if ($LASTEXITCODE -ne 0) { throw 'overlay rendering failed' }
    if (-not (Test-Path -LiteralPath $renderedManifest)) { throw 'rendered manifest missing' }
    Write-UpdateLog 'overlay rendered in staging'

    & $python -m compileall -q $stage
    if ($LASTEXITCODE -ne 0) { throw 'rendered Python syntax check failed' }
    Get-ChildItem -LiteralPath $stage -Recurse -Filter '*.ps1' | ForEach-Object {
        $err = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$err) | Out-Null
        if ($err) { throw ('rendered PowerShell syntax error: ' + $_.Name) }
    }
    Write-UpdateLog 'runtime syntax checks passed'
    Write-Status 'syntax' 65 '代码语法检查通过'
    $dataBefore = Get-TreeFingerprint (Join-Path $root 'AstrBot\data')
    if ($DryRun) {
        $dataAfter = Get-TreeFingerprint (Join-Path $root 'AstrBot\data')
        if ($dataBefore -ne $dataAfter) { throw 'data changed during dry run' }
        Write-UpdateLog ('MERGE_DRY_RUN_OK version=' + $newVersion + ' files=' + $files.Count)
        exit 0
    }

    New-Item -ItemType Directory -Path $backupCode -Force | Out-Null
    foreach ($entry in $files) {
        $rel = ([string]$entry.path).Replace('/', '\')
        $source = Join-Path $root $rel
        if (Test-Path -LiteralPath $source) {
            $destination = Join-Path $backupCode $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    if (Test-Path -LiteralPath $OverlayPath) { Copy-Item -LiteralPath $OverlayPath -Destination $backupOverlay -Force }
    Write-UpdateLog ('code backup: ' + $backupCode)
    Write-Status 'backing_up' 70 '已备份代码和配置...'
    if ($isLive) {
        Write-Status 'stopping' 72 '正在停止服务...'
        Stop-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
        Stop-ScheduledTask -TaskName 'AstrBot TOTP Broker' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Stop-LiveProcesses
        Start-Sleep -Seconds 3
    }

    Write-Status 'applying' 80 '正在替换代码...'
    & $python $updateCore apply --staging $stage --target $root --manifest $renderedManifest
    if ($LASTEXITCODE -ne 0) { throw 'rendered apply failed' }
    Write-UpdateLog 'rendered code applied'

    & $python $mergeCore refresh-baseline --target $root --overlay $OverlayPath
    if ($LASTEXITCODE -ne 0) { throw 'overlay baseline refresh failed' }

    $dataAfter = Get-TreeFingerprint (Join-Path $root 'AstrBot\data')
    if ($dataBefore -ne $dataAfter) { throw 'data fingerprint changed during update' }
    Write-UpdateLog 'data untouched verified'
    Write-Status 'data_check' 88 '数据目录未发生变化'
    if ($isLive) {
        Write-Status 'restarting' 92 '正在重启苏瑾言...'
        Start-ScheduledTask -TaskName 'AstrBot TOTP Broker' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 4
        $brokerOk = Wait-Health 'broker' 'http://127.0.0.1:18090/health'
        Start-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
        $astrbotOk = Wait-Health 'astrbot' 'http://127.0.0.1:6185' 60
        if (-not ($brokerOk -and $astrbotOk)) { throw 'post-update health check failed' }
        Write-Status 'done' 100 '更新完成，苏瑾言已重启。'
        Write-UpdateLog ('PRODUCTION_UPDATE_OK version=' + $newVersion)
    } else {
        Write-Status 'done' 100 '沙盒更新完成。'
        Write-UpdateLog ('SANDBOX_MERGE_OK version=' + $newVersion + ' target=' + $root)
    }
    exit 0
} catch {
    Write-Status 'failed' 100 ('更新失败：' + $_.Exception.Message)
    Write-UpdateLog ('MERGE_FAILED: ' + $_.Exception.Message)
    try {
        if (-not $DryRun) {
            if (Test-Path -LiteralPath $backupCode) {
                $manifestPath = Join-Path $stage 'update-manifest.json'
                if (Test-Path -LiteralPath $manifestPath) {
                    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
                    foreach ($entry in @($manifest.files)) {
                        $rel = ([string]$entry.path).Replace('/', '\')
                        $source = Join-Path $backupCode $rel
                        if (Test-Path -LiteralPath $source) {
                            $destination = Join-Path $root $rel
                            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
                            Copy-Item -LiteralPath $source -Destination $destination -Force
                        }
                    }
                }
            }
            if (Test-Path -LiteralPath $backupOverlay) { Copy-Item -LiteralPath $backupOverlay -Destination $OverlayPath -Force }
            if ($isLive) {
                Start-ScheduledTask -TaskName 'AstrBot TOTP Broker' -ErrorAction SilentlyContinue
                Start-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 10
            }
            Write-UpdateLog 'rollback attempted'
        }
    } catch {
        Write-UpdateLog ('ROLLBACK_FAILED: ' + $_.Exception.Message)
    }
    exit 1
} finally {
    if (Test-Path -LiteralPath $work) {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}
