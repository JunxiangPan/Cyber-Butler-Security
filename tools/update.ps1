#Requires -RunAsAdministrator
<#
Apply a Cyber-Butler release with code-only replacement.

Safety modes:
  -TargetRoot PATH : update a disposable copy instead of the live root
  -DryRun          : download, verify, extract and report only; no writes to target

The live target also stops/restarts AstrBot and the Broker and performs health
checks. A non-live target never touches the live services.
#>
[CmdletBinding()]
param(
    [string]$Repo = 'JunxiangPan/Cyber-Butler-Security',
    [string]$AssetUrl = '',
    [string]$ExpectedSha256 = '',
    [string]$LocalZip = '',
    [string]$TargetRoot = '',
    [switch]$DryRun,
    [switch]$Yes
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
$python = Join-Path $sourceRoot 'AstrBot\.venv\Scripts\python.exe'
$core = Join-Path $root 'tools\update_core.py'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$work = Join-Path $env:TEMP ('cyber-butler-update-' + $stamp)
$zip = Join-Path $work 'release.zip'
$stage = Join-Path $work 'staging'
if ($DryRun) {
    $backup = Join-Path $env:TEMP ('cyber-butler-dryrun-' + $stamp)
} else {
    $backup = Join-Path $root ('backups\auto-update-' + $stamp)
}
$log = Join-Path $backup 'update.log'
$backupCode = Join-Path $backup 'code'

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
        'User-Agent' = 'Cyber-Butler-Updater/1.0'
        'Accept' = 'application/vnd.github+json'
    }
    if ($env:GITHUB_TOKEN) {
        $headers['Authorization'] = 'Bearer ' + $env:GITHUB_TOKEN
    }
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

function Restore-Backup {
    if (-not (Test-Path -LiteralPath $backupCode)) { return }
    $manifestPath = Join-Path $stage 'update-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { return }
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
    Write-UpdateLog ('rollback attempted from ' + $backupCode)
}

try {
    if (-not (Test-Path -LiteralPath $python)) { throw "Python not found: $python" }
    if (-not (Test-Path -LiteralPath $core)) { throw "update_core.py not found: $core" }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'AstrBot'))) {
        throw "TargetRoot does not contain AstrBot: $root"
    }
    if (-not $isLive -and -not (Test-Path -LiteralPath (Join-Path $root 'AstrBot\data'))) {
        throw "sandbox TargetRoot must contain AstrBot/data: $root"
    }

    $localZipSource = ''
    if ($LocalZip) {
        if ($isLive -and -not $DryRun) {
            throw 'LocalZip is only allowed for a non-live TargetRoot or a DryRun'
        }
        $localZipSource = (Resolve-Path -LiteralPath $LocalZip).Path
        $computed = (Get-FileHash -LiteralPath $localZipSource -Algorithm SHA256).Hash.ToLower()
        if ($ExpectedSha256 -and $ExpectedSha256.ToLower() -ne $computed) {
            throw 'LocalZip SHA-256 does not match -ExpectedSha256'
        }
        $ExpectedSha256 = $computed
    } else {
        if (-not $AssetUrl) {
            $latest = Get-LatestAsset
            $AssetUrl = $latest.Url
            if (-not $ExpectedSha256) { $ExpectedSha256 = $latest.Sha256 }
        }
        if (-not $ExpectedSha256) {
            throw 'No trusted SHA-256 available. Pass -ExpectedSha256 or use a release asset with a GitHub digest.'
        }
        $uri = [Uri]$AssetUrl
        if ($uri.Scheme -ne 'https') { throw 'asset URL must use HTTPS' }
    }

    if (-not $Yes -and -not $DryRun) {
        $answer = Read-Host ('This will replace code under ' + $root + '. Type UPDATE to continue')
        if ($answer -ne 'UPDATE') { throw 'update cancelled' }
    }

    New-Item -ItemType Directory -Path $work -Force | Out-Null
    Write-UpdateLog ('target=' + $root)
    Write-UpdateLog ('live=' + $isLive + ' dry_run=' + [bool]$DryRun)
    if ($localZipSource) {
        Write-UpdateLog ('starting update from local sandbox package: ' + $localZipSource)
        Copy-Item -LiteralPath $localZipSource -Destination $zip -Force
    } else {
        Write-UpdateLog ('starting update from ' + $AssetUrl)
        Invoke-WebRequest -Uri $AssetUrl -OutFile $zip -UseBasicParsing -TimeoutSec 300
    }
    $actual = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLower()
    if ($actual -ne $ExpectedSha256.ToLower()) {
        throw 'downloaded asset SHA-256 does not match the trusted digest'
    }
    Write-UpdateLog ('asset sha256 verified: ' + $actual)

    & $python $core extract --zip $zip --dest $stage
    if ($LASTEXITCODE -ne 0) { throw 'update_core rejected the archive' }
    $manifestPath = Join-Path $stage 'update-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'update-manifest.json missing' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $newVersion = [string]$manifest.version
    $files = @($manifest.files)
    if (-not $newVersion -or $files.Count -eq 0) { throw 'manifest has no version or files' }
    Write-UpdateLog ('manifest verified: version ' + $newVersion + ', files ' + $files.Count)

    if ($DryRun) {
        $simulated = 0
        foreach ($entry in $files) {
            $rel = ([string]$entry.path).Replace('/', '')
            $staged = Join-Path $stage $rel
            if (-not (Test-Path -LiteralPath $staged)) {
                throw ('dry-run staged file missing: ' + $entry.path)
            }
            $bytes = Get-Item -LiteralPath $staged
            if ($bytes.Length -ne [int64]$entry.size) {
                throw ('dry-run size mismatch: ' + $entry.path)
            }
            $hash = (Get-FileHash -LiteralPath $staged -Algorithm SHA256).Hash.ToLower()
            if ($hash -ne ([string]$entry.sha256).ToLower()) {
                throw ('dry-run hash mismatch: ' + $entry.path)
            }
            $simulated++
        }
        $dataBefore = Get-TreeFingerprint (Join-Path $root 'AstrBot\data')
        $dataAfter = Get-TreeFingerprint (Join-Path $root 'AstrBot\data')
        if ($dataBefore -ne $dataAfter) { throw 'data changed during dry run' }
        Write-UpdateLog ('DRY_RUN_OK version=' + $newVersion + ' would_replace=' + $simulated + ' target=' + $root)
        exit 0
    }

    if (-not (Test-Path -LiteralPath $backupCode)) {
        New-Item -ItemType Directory -Path $backupCode -Force | Out-Null
    }
    foreach ($entry in $files) {
        $rel = ([string]$entry.path).Replace('/', '\')
        $source = Join-Path $root $rel
        if (Test-Path -LiteralPath $source) {
            $destination = Join-Path $backupCode $rel
            New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $destination -Force
        }
    }
    Write-UpdateLog ('code backup: ' + $backupCode)

    $dataBefore = Get-TreeFingerprint (Join-Path $root 'AstrBot\data')
    if ($isLive) {
        Stop-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
        Stop-ScheduledTask -TaskName 'AstrBot TOTP Broker' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        Stop-LiveProcesses
        Start-Sleep -Seconds 3
    }

    & $python $core apply --staging $stage --target $root --manifest $manifestPath
    if ($LASTEXITCODE -ne 0) { throw 'update_core apply failed' }
    Write-UpdateLog 'code files applied'

    $dataAfter = Get-TreeFingerprint (Join-Path $root 'AstrBot\data')
    if ($dataBefore -ne $dataAfter) { throw 'data fingerprint changed during update' }
    Write-UpdateLog 'data untouched verified'

    if ($isLive) {
        Start-ScheduledTask -TaskName 'AstrBot TOTP Broker' -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 4
        $brokerOk = Wait-Health 'broker' 'http://127.0.0.1:18090/health'
        Start-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
        $astrbotOk = Wait-Health 'astrbot' 'http://127.0.0.1:6185' 60
        if (-not ($brokerOk -and $astrbotOk)) { throw 'post-update health check failed' }
        Write-UpdateLog ('UPDATE_OK version=' + $newVersion)
    } else {
        Write-UpdateLog ('SANDBOX_UPDATE_OK version=' + $newVersion + ' target=' + $root)
    }
    exit 0
} catch {
    Write-UpdateLog ('UPDATE_FAILED: ' + $_.Exception.Message)
    try {
        if (-not $DryRun) {
            Restore-Backup
            if ($isLive) {
                Start-ScheduledTask -TaskName 'AstrBot TOTP Broker' -ErrorAction SilentlyContinue
                Start-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 10
            }
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
