# Real core deployment: download, verify, extract, venv, overlay.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

function Get-CyberButlerCoreSourceConfig {
    param(
        [string]$CoreSourcesPath = ''
    )
    if ([string]::IsNullOrWhiteSpace($CoreSourcesPath)) {
        $CoreSourcesPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core-sources.json'
    }
    if (-not (Test-Path -LiteralPath $CoreSourcesPath)) {
        throw "Core source config not found: $CoreSourcesPath"
    }
    return (Get-Content -LiteralPath $CoreSourcesPath -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Resolve-CyberButlerCoreSource {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$PackagePath = '',
        [string]$Sha256 = '',
        $Config
    )

    $entry = $Config.$Name
    if ($null -eq $entry) { throw "Core source entry missing: $Name" }
    $url = if ($PackagePath) { $PackagePath } else { [string]$entry.url }
    $hash = if ($Sha256) { $Sha256 } else { [string]$entry.sha256 }
    if ([string]::IsNullOrWhiteSpace($url)) { throw "Core source URL missing: $Name" }
    if ([string]::IsNullOrWhiteSpace($hash)) { throw "Core source SHA-256 missing: $Name" }
    return [pscustomobject]@{
        name = $Name
        url = $url
        sha256 = $hash.ToLowerInvariant()
        version = [string]$entry.version
        size_bytes = if ($entry.size_bytes) { [long]$entry.size_bytes } else { 0 }
    }
}

function Get-CyberButlerCorePython {
    param(
        [string]$PreferredPath = '',
        [string]$ServiceRoot = '',
        [bool]$Isolation = $false
    )
    if ($PreferredPath -and (Test-Path -LiteralPath $PreferredPath -PathType Leaf)) {
        $preferred = [IO.Path]::GetFullPath($PreferredPath)
        if ($Isolation -and $ServiceRoot -and $preferred -match '^[A-Za-z]:\\Users\\') {
            # A standard service account cannot read a per-user Python install.
            # Materialize the base runtime under the service-readable install
            # root, then create the venv from that copy.
            $sourceRoot = Split-Path -Parent $preferred
            $servicePythonRoot = Join-Path $ServiceRoot '.python'
            $servicePython = Join-Path $servicePythonRoot 'python.exe'
            if (-not (Test-Path -LiteralPath $servicePython)) {
                if (Test-Path -LiteralPath $servicePythonRoot) {
                    Remove-Item -LiteralPath $servicePythonRoot -Recurse -Force -ErrorAction SilentlyContinue
                }
                Copy-Item -LiteralPath $sourceRoot -Destination $servicePythonRoot -Recurse -Force
            }
            if (Test-Path -LiteralPath $servicePython) { return [IO.Path]::GetFullPath($servicePython) }
        }
        return $preferred
    }
    $command = Get-Command python.exe -ErrorAction SilentlyContinue
    if (-not $command) { $command = Get-Command py.exe -ErrorAction SilentlyContinue }
    if (-not $command) { throw 'Python was not found.' }
    return [string]$command.Source
}

function Invoke-CyberButlerCoreDownload {
    param(
        [Parameter(Mandatory = $true)]
        $Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination,
        [int]$TimeoutSeconds = 300,
        [int]$RetryCount = 3,
        [switch]$Resume
    )
    $parent = Split-Path -Parent $Destination
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if ($Source.url -match '^https?://') {
        $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
        $lastError = $null
        for ($attempt = 1; $attempt -le [Math]::Max(1, $RetryCount); $attempt++) {
            try {
                if ($curl) {
                    $curlArgs = @('-L', '--fail', '--progress-bar', '--connect-timeout', '30', '--max-time', [string]$TimeoutSeconds, '-o', $Destination)
                    if ($Resume -and (Test-Path -LiteralPath $Destination)) { $curlArgs += @('-C', '-') }
                    $curlArgs += $Source.url
                    & $curl.Source @curlArgs
                    if ($LASTEXITCODE -ne 0) { throw "curl exit code $LASTEXITCODE" }
                } else {
                    if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue }
                    Invoke-WebRequest -Uri $Source.url -OutFile $Destination -UseBasicParsing -TimeoutSec ([Math]::Max(1, $TimeoutSeconds)) -ErrorAction Stop
                }
                $lastError = $null
                break
            } catch {
                $lastError = $_
                if (Test-Path -LiteralPath $Destination) { Remove-Item -LiteralPath $Destination -Force -ErrorAction SilentlyContinue }
                if ($attempt -lt $RetryCount) { Start-Sleep -Seconds ([Math]::Min(8, $attempt * 2)) }
            }
        }
        if ($null -ne $lastError -or -not (Test-Path -LiteralPath $Destination)) {
            $hint = if ($Source.url -match 'github\.com') {
                ' GitHub is unreachable or returned an error. Check network, DNS, proxy/VPN, and firewall; or pass a local package with -AstrBotPackage / -SnowLumaPackage.'
            } else { '' }
            throw ("Download failed for {0} after {1} attempt(s): {2}.{3}" -f $Source.name, $RetryCount, $lastError.Exception.Message, $hint)
        }
    } elseif (Test-Path -LiteralPath $Source.url -PathType Leaf) {
        Copy-Item -LiteralPath $Source.url -Destination $Destination -Force
    } else {
        throw "Core source is not a reachable URL or local file: $($Source.url)"
    }
    $actual = (Get-FileHash -LiteralPath $Destination -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actual -ne $Source.sha256) {
        throw "SHA-256 mismatch for $($Source.name): expected $($Source.sha256), got $actual"
    }
    return $Destination
}

function Expand-CyberButlerCoreArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Archive,
        [Parameter(Mandatory = $true)]
        [string]$Destination
    )
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    Expand-Archive -LiteralPath $Archive -DestinationPath $Destination -Force -ErrorAction Stop
    return $Destination
}

function Find-CyberButlerCoreRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Marker
    )
    if (Test-Path -LiteralPath (Join-Path $Path $Marker)) { return $Path }
    foreach ($dir in @(Get-ChildItem -LiteralPath $Path -Directory -ErrorAction SilentlyContinue)) {
        if (Test-Path -LiteralPath (Join-Path $dir.FullName $Marker)) { return $dir.FullName }
    }
    return $null
}

function Get-CyberButlerCoreFileList {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source
    )
    $files = New-Object System.Collections.Generic.List[string]
    $stack = New-Object System.Collections.Generic.Stack[string]
    $stack.Push([IO.Path]::GetFullPath($Source))
    while ($stack.Count -gt 0) {
        $dir = $stack.Pop()
        try {
            $entries = [IO.Directory]::EnumerateFileSystemEntries($dir)
        } catch {
            throw ("CORE cannot enumerate directory " + $dir + ": " + $_.Exception.Message)
        }
        foreach ($entry in $entries) {
            $attributes = [IO.File]::GetAttributes($entry)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                Write-Host ('CORE skipping reparse point ' + $entry)
                continue
            }
            if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                $stack.Push($entry)
            } else {
                $files.Add($entry)
            }
        }
    }
    return $files.ToArray()
}

function Copy-CyberButlerCoreTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Source,
        [Parameter(Mandatory = $true)]
        [string]$Destination,
        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot,
        $Journal = $null,
        [string]$JournalStep = 'core',
        [string[]]$ExcludeTop = @(),
        [string[]]$ExcludePatterns = @(),
        [string]$Label = 'files'
    )

    $sourceFull = [IO.Path]::GetFullPath($Source)
    $destFull = [IO.Path]::GetFullPath($Destination)
    if (-not [IO.Directory]::Exists($sourceFull)) { throw "Source tree missing: $sourceFull" }

    Write-Host ('CORE scanning ' + $Label + ' source...')
    $allFiles = @(Get-CyberButlerCoreFileList -Source $sourceFull)
    $selected = New-Object System.Collections.Generic.List[string]
    foreach ($file in $allFiles) {
        $relative = $file.Substring($sourceFull.Length).TrimStart('\')
        $parts = $relative -split '[\/]'
        if ($parts.Count -gt 0 -and $ExcludeTop -contains $parts[0]) { continue }
        $skip = $false
        foreach ($pattern in @($ExcludePatterns)) {
            if ($relative -like $pattern) { $skip = $true; break }
        }
        if ($skip) { continue }
        $selected.Add($file)
    }

    Write-Host ('CORE copying ' + $Label + ' (' + $selected.Count + ' files)...')
    $index = 0
    foreach ($file in $selected) {
        $index++
        $relative = $file.Substring($sourceFull.Length).TrimStart('\')
        $target = Join-Path $destFull $relative
        $parent = Split-Path -Parent $target
        if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
        if ([IO.File]::Exists($target)) {
            if ($null -ne $Journal) {
                Backup-CyberButlerFile -Journal $Journal -Step $JournalStep -Path $target -AllowedRoot $AllowedRoot | Out-Null
            }
            [IO.File]::SetAttributes($target, [IO.FileAttributes]::Normal)
        } elseif ($null -ne $Journal) {
            Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                type = 'delete-created-file'
                path = [IO.Path]::GetFullPath($target)
                allowed_root = [IO.Path]::GetFullPath($AllowedRoot)
            })
        }
        [IO.File]::Copy($file, $target, $true)
        if (($index % 50) -eq 0 -or $index -eq $selected.Count) {
            Write-Host ('CORE ' + $Label + ' ' + $index + '/' + $selected.Count)
        }
    }
}

function Invoke-CyberButlerPipInstall {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PythonPath,
        [Parameter(Mandatory = $true)]
        [string]$Requirements,
        [Parameter(Mandatory = $true)]
        [string]$LogPath,
        [string]$SitePackagesPath = '',
        [int]$HeartbeatSeconds = 30,
        [int]$PollMilliseconds = 1000,
        [scriptblock]$Clock = $null
    )

    if ($HeartbeatSeconds -lt 15) { $HeartbeatSeconds = 15 }
    $parent = Split-Path -Parent $LogPath
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $stderrPath = $LogPath + '.stderr'
    Set-Content -LiteralPath $LogPath -Value '' -Encoding UTF8
    Set-Content -LiteralPath $stderrPath -Value '' -Encoding UTF8

    $sbomPath = [IO.Path]::Combine(
        (Split-Path -Parent $Requirements),
        [IO.Path]::GetFileNameWithoutExtension($Requirements) + '.sbom.json'
    )
    $packageRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $bundlePath = Join-Path $packageRoot 'dependencies.sbom.json'
    $sbomTool = Join-Path $packageRoot 'tools\sbom.py'
    if ((Test-Path -LiteralPath $bundlePath) -and (Test-Path -LiteralPath $sbomTool)) {
        & $PythonPath $sbomTool verify-bundle --root $packageRoot --manifest $bundlePath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw ('dependency bundle SBOM verification failed: ' + $bundlePath)
        }
    }
    if ((Test-Path -LiteralPath $sbomPath) -and (Test-Path -LiteralPath $sbomTool)) {
        & $PythonPath $sbomTool verify --requirements $Requirements --manifest $sbomPath | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw ('dependency SBOM verification failed: ' + $sbomPath)
        }
    }
    $quote = { param($value) '"' + ([string]$value).Replace('"', '""') + '"' }
    $command = (& $quote $PythonPath) + ' -m pip install --disable-pip-version-check --progress-bar on -r ' + (& $quote $Requirements)
    $argumentLine = '/d /s /c "' + $command + '"'
    $process = Start-Process -FilePath $env:ComSpec -ArgumentList $argumentLine `
        -RedirectStandardOutput $LogPath -RedirectStandardError $stderrPath `
        -WindowStyle Hidden -PassThru
    if ($null -eq $process) { throw 'failed to start pip' }

    $lines = New-Object System.Collections.Generic.List[string]
    $stdoutOffset = 0
    $stderrOffset = 0
    $heartbeats = 0
    $nowProvider = { if ($null -ne $Clock) { [datetime](& $Clock) } else { Get-Date } }
    $started = [datetime](& $nowProvider)
    $lastOutput = $started

    $readNew = {
        param([string]$path, [int]$offset)
        if (-not (Test-Path -LiteralPath $path)) { return @{ lines = @(); count = $offset } }
        $all = @(Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction SilentlyContinue)
        $new = @()
        for ($i = $offset; $i -lt $all.Count; $i++) {
            $new += [string]$all[$i]
        }
        return @{ lines = $new; count = $all.Count }
    }

    while (-not $process.HasExited) {
        Start-Sleep -Milliseconds ([Math]::Max(50, $PollMilliseconds))
        $stdout = & $readNew $LogPath $stdoutOffset
        $stdoutOffset = [int]$stdout.count
        foreach ($line in @($stdout.lines)) {
            $lines.Add($line)
            Write-Host $line
            $lastOutput = [datetime](& $nowProvider)
        }
        $stderr = & $readNew $stderrPath $stderrOffset
        $stderrOffset = [int]$stderr.count
        foreach ($line in @($stderr.lines)) {
            $lines.Add($line)
            Write-Host $line
            $lastOutput = [datetime](& $nowProvider)
        }
        if ($process.HasExited) { break }
        $now = [datetime](& $nowProvider)
        if (($now - $lastOutput).TotalSeconds -ge $HeartbeatSeconds) {
            $packages = 0
            if ($SitePackagesPath -and (Test-Path -LiteralPath $SitePackagesPath)) {
                $packages = @(Get-ChildItem -LiteralPath $SitePackagesPath -Directory -ErrorAction SilentlyContinue).Count
            }
            $elapsed = [Math]::Max(0, [int](($now - $started).TotalSeconds))
            Write-Host ('CORE pip still running... (elapsed: {0}s, packages: {1})' -f $elapsed, $packages)
            $heartbeats++
            $lastOutput = $now
        }
    }

    $process.WaitForExit()
    $stdout = & $readNew $LogPath $stdoutOffset
    $stdoutOffset = [int]$stdout.count
    foreach ($line in @($stdout.lines)) {
        $lines.Add($line)
        Write-Host $line
    }
    $stderr = & $readNew $stderrPath $stderrOffset
    $stderrOffset = [int]$stderr.count
    if (@($stderr.lines).Count -gt 0) {
        Add-Content -LiteralPath $LogPath -Value '--- pip stderr ---' -Encoding UTF8
        foreach ($line in @($stderr.lines)) {
            $lines.Add($line)
            Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
        }
    }
    Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{
        exit_code = [int]$process.ExitCode
        output = $lines.ToArray()
        log_path = $LogPath
        heartbeats = $heartbeats
    }
}

function Test-CyberButlerCoreDeploy {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        $Handlers = @{}
    )
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'core.test') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'core.test' -Context ([pscustomobject]@{ InstallPath = $InstallPath }))
    }
    $root = [IO.Path]::GetFullPath($InstallPath)
    $astrbot = Join-Path $root 'AstrBot'
    $venvPython = Join-Path $astrbot '.venv\Scripts\python.exe'
    $overlayProbe = Join-Path $astrbot 'astrbot\core\tools\message_tools.py'
    $missing = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path -LiteralPath (Join-Path $astrbot 'main.py'))) { $missing.Add('AstrBot/main.py') }
    if (-not (Test-Path -LiteralPath $venvPython)) { $missing.Add('AstrBot/.venv/Scripts/python.exe') }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'SnowLuma\index.mjs'))) { $missing.Add('SnowLuma/index.mjs') }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'tools'))) { $missing.Add('tools') }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'tools\broker.py'))) { $missing.Add('tools/broker.py') }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'tools\email_approval.py'))) { $missing.Add('tools/email_approval.py') }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'webui\run.py'))) { $missing.Add('webui/run.py') }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'webui\.venv\Scripts\python.exe'))) { $missing.Add('webui/.venv/Scripts/python.exe') }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'AstrBot\data'))) { $missing.Add('AstrBot/data') }
    foreach ($cbsName in @('astrbot_plugin_at_gate','astrbot_plugin_cloud_fallback','astrbot_plugin_dsh_bridge','astrbot_plugin_dst_guard','astrbot_plugin_mcp_readonly','astrbot_plugin_router','astrbot_plugin_security_gate','astrbot_plugin_totp_broker','astrbot_plugin_weather_tools','astrbot_plugin_webui_bridge')) {
        $cbsMain = Join-Path (Join-Path (Join-Path $astrbot 'data') 'plugins') ($cbsName + '\main.py')
        if (-not (Test-Path -LiteralPath $cbsMain)) { $missing.Add('AstrBot/data/plugins/' + $cbsName) }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'workspace'))) { $missing.Add('workspace') }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'data'))) { $missing.Add('data') }
    if (-not (Test-Path -LiteralPath $overlayProbe)) { $missing.Add('overlay probe') }
    $satisfied = $missing.Count -eq 0
    return [pscustomobject]@{
        satisfied = [bool]$satisfied
        install_path = $root
        astrbot = $astrbot
        venv_python = $venvPython
        missing = $missing.ToArray()
        reason = if ($satisfied) { 'core tree present' } else { 'core tree incomplete: ' + ($missing -join ', ') }
    }
}

function Test-CyberButlerCoreImportSmoke {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [Parameter(Mandatory = $true)]
        [string]$PythonPath,
        $Handlers = @{}
    )
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'core.import') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'core.import' -Context ([pscustomobject]@{ InstallPath = $InstallPath }))
    }
    $astrbot = Join-Path ([IO.Path]::GetFullPath($InstallPath)) 'AstrBot'
    Push-Location $astrbot
    try {
        $output = @((& $PythonPath -c 'import astrbot.core' 2>&1 | Out-String))
        $code = [int]$LASTEXITCODE
    } finally {
        Pop-Location
    }
    return [pscustomobject]@{
        ok = ($code -eq 0)
        exit_code = $code
        output = @($output | ForEach-Object { [string]$_ })
    }
}

function Invoke-CyberButlerCoreDeploy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [string]$ExistingState = 'None',
        [string]$Tier = 'Medium',
        [string]$AstrBotPackage = '',
        [string]$SnowLumaPackage = '',
        [string]$AstrBotSha256 = '',
        [string]$SnowLumaSha256 = '',
        [string]$CoreSourcesPath = '',
        [switch]$SkipDependencyInstall,
        [int]$DownloadTimeoutSeconds = 300,
        [int]$DownloadRetryCount = 3,
        [switch]$ResumeDownload,
        [string]$PythonPath = '',
        [string]$PythonSource = 'system',
        [string]$PythonVersion = '',
        [string]$WebUIAdminEmail = 'owner@example.com',
        [string]$PersonalPluginsPath = '',
        [switch]$Repair,
        [string]$OwnerQQ = '',
        [string]$ToolServiceAccount = '',
        [string]$ToolDesktopAccount = '',
        [string]$PipLogPath = '',
        [switch]$SkipOverlayManifest,
        [string]$JournalStep = 'core',
        $Journal = $null,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'core.deploy') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'core.deploy' -Context ([pscustomobject]@{
            Root = $InstallPath; ExistingState = $ExistingState; Tier = $Tier
        }))
    }

    $test = Test-CyberButlerCoreDeploy -InstallPath $InstallPath -Handlers $Handlers
    $packageVersionFile = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'VERSION'
    $installedVersionFile = Join-Path ([IO.Path]::GetFullPath($InstallPath)) 'VERSION'
    if ($test.satisfied -and (Test-Path -LiteralPath $packageVersionFile) -and (Test-Path -LiteralPath $installedVersionFile)) {
        $wantedVersion = (Get-Content -LiteralPath $packageVersionFile -Raw -Encoding UTF8).Trim()
        $installedVersion = (Get-Content -LiteralPath $installedVersionFile -Raw -Encoding UTF8).Trim()
        if ($wantedVersion -ne $installedVersion) {
            Write-Host ('CORE version differs: installed=' + $installedVersion + ' package=' + $wantedVersion + '; forcing deploy')
            $test.satisfied = $false
            $test.reason = 'version-mismatch'
        }
    }
    if ($test.satisfied) {
        $reason = 'core deployment already satisfied: ' + [string]$test.reason
        return [pscustomobject]@{
            status = 'skipped'; changed = $false; exit_code = 0; test = $test
            reason = $reason; python_source = $PythonSource; python_path = $PythonPath; python_version = $PythonVersion
            paths = [pscustomobject]@{
                astrbot = Join-Path $test.install_path 'AstrBot'
                snowluma = Join-Path $test.install_path 'SnowLuma'
                tools = Join-Path $test.install_path 'tools'
                workspace = Join-Path $test.install_path 'workspace'
                data = Join-Path $test.install_path 'data'
            }
        }
    }

    $root = [IO.Path]::GetFullPath($InstallPath)
    $createdDirs = New-Object System.Collections.Generic.List[string]
    $staging = Join-Path $root ('.installer-staging-' + [guid]::NewGuid().ToString('N'))
    $stepStarted = $false
    if ($null -ne $Journal) {
        Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status in_progress | Out-Null
        $stepStarted = $true
        New-CyberButlerTrackedDirectory -Journal $Journal -Step $JournalStep -Path $staging -AllowedRoot $root | Out-Null
    } else {
        New-Item -ItemType Directory -Path $staging -Force | Out-Null
    }
    $createdDirs.Add($staging)

    try {
        $config = Get-CyberButlerCoreSourceConfig -CoreSourcesPath $CoreSourcesPath
        $astrbotSource = Resolve-CyberButlerCoreSource -Name 'astrbot' -PackagePath $AstrBotPackage -Sha256 $AstrBotSha256 -Config $config
        $snowSource = Resolve-CyberButlerCoreSource -Name 'snowluma' -PackagePath $SnowLumaPackage -Sha256 $SnowLumaSha256 -Config $config

        $astrbotArchive = Join-Path $staging 'astrbot.zip'
        $snowArchive = Join-Path $staging 'snowluma.zip'
        $astrbotSize = if ($astrbotSource.size_bytes -gt 0) { '{0:N1} MB' -f ($astrbotSource.size_bytes / 1MB) } else { 'unknown size' }
        $snowSize = if ($snowSource.size_bytes -gt 0) { '{0:N1} MB' -f ($snowSource.size_bytes / 1MB) } else { 'unknown size' }
        Write-Host ('CORE downloading ' + $astrbotSource.name + ' ' + $astrbotSource.version + ' (' + $astrbotSize + ')...')
        Invoke-CyberButlerCoreDownload -Source $astrbotSource -Destination $astrbotArchive -TimeoutSeconds $DownloadTimeoutSeconds -RetryCount $DownloadRetryCount -Resume:$ResumeDownload | Out-Null
        Write-Host ('CORE downloaded ' + $astrbotSource.name + '.')
        Write-Host ('CORE downloading ' + $snowSource.name + ' ' + $snowSource.version + ' (' + $snowSize + ')...')
        Invoke-CyberButlerCoreDownload -Source $snowSource -Destination $snowArchive -TimeoutSeconds $DownloadTimeoutSeconds -RetryCount $DownloadRetryCount -Resume:$ResumeDownload | Out-Null
        Write-Host ('CORE downloaded ' + $snowSource.name + '.')
        Write-Host 'CORE extracting AstrBot archive...'
        $rawAstrbot = Expand-CyberButlerCoreArchive -Archive $astrbotArchive -Destination (Join-Path $staging 'astrbot-raw')
        Write-Host 'CORE extracting SnowLuma archive...'
        $rawSnow = Expand-CyberButlerCoreArchive -Archive $snowArchive -Destination (Join-Path $staging 'snow-raw')
        Write-Host 'CORE archives extracted.'
        $astrbotRoot = Find-CyberButlerCoreRoot -Path $rawAstrbot -Marker 'main.py'
        $snowRoot = Find-CyberButlerCoreRoot -Path $rawSnow -Marker 'index.mjs'
        if (-not $astrbotRoot) { throw 'AstrBot archive does not contain main.py.' }
        if (-not $snowRoot) { throw 'SnowLuma archive does not contain index.mjs.' }

        Write-Host 'CORE creating target directories...'
        $astrbotTarget = Join-Path $root 'AstrBot'
        $snowTarget = Join-Path $root 'SnowLuma'
        $toolsTarget = Join-Path $root 'tools'
        $workspaceTarget = Join-Path $root 'workspace'
        $dataTarget = Join-Path $root 'data'
        $webTarget = Join-Path $root 'webui'
        $astrbotDataTarget = Join-Path $astrbotTarget 'data'

        foreach ($path in @($astrbotTarget, $snowTarget, $toolsTarget, $workspaceTarget, $dataTarget, $webTarget, $astrbotDataTarget)) {
            if (-not (Test-Path -LiteralPath $path)) {
                if ($null -ne $Journal) {
                    New-CyberButlerTrackedDirectory -Journal $Journal -Step $JournalStep -Path $path -AllowedRoot $root | Out-Null
                } else {
                    New-Item -ItemType Directory -Path $path -Force | Out-Null
                }
                $createdDirs.Add($path)
            }
        }

        Copy-CyberButlerCoreTree -Source $astrbotRoot -Destination $astrbotTarget -AllowedRoot $astrbotTarget -Journal $Journal -JournalStep $JournalStep -ExcludeTop @('data', '.venv') -Label 'AstrBot'
        Copy-CyberButlerCoreTree -Source $snowRoot -Destination $snowTarget -AllowedRoot $snowTarget -Journal $Journal -JournalStep $JournalStep -ExcludeTop @('data', 'config', 'logs') -Label 'SnowLuma'

        $overlay = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'overlay'
        if (Test-Path -LiteralPath $overlay) {
            $astrbotVersion = [string]$config.astrbot.version
            if ($astrbotVersion) {
                Set-Content -LiteralPath (Join-Path $astrbotTarget 'VERSION') -Value $astrbotVersion -Encoding ASCII
            }
            if (-not $SkipOverlayManifest) {
                Write-Host 'CORE validating overlay manifest...'
                $overlayCheck = Test-CyberButlerOverlayManifest -AstrBotPath $astrbotTarget -OverlayPath $overlay
                Write-Host ('CORE overlay manifest ok for AstrBot ' + $overlayCheck.version)
            }
            Write-Host 'CORE applying overlay...'
            Copy-CyberButlerCoreTree -Source $overlay -Destination $astrbotTarget -AllowedRoot $astrbotTarget -Journal $Journal -JournalStep $JournalStep `
                -ExcludePatterns @('overlay-manifest.json') -Label 'overlay'
            Write-Host 'CORE overlay applied.'
        } else {
            throw "Overlay tree missing: $overlay"
        }

        $releaseRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $toolsSource = Join-Path $releaseRoot 'tools'
        $webSource = Join-Path $releaseRoot 'webui'
        if (-not (Test-Path -LiteralPath $toolsSource)) { throw "Tools tree missing: $toolsSource" }
        if (-not (Test-Path -LiteralPath $webSource)) { throw "Web UI tree missing: $webSource" }
        Copy-CyberButlerCoreTree -Source $toolsSource -Destination $toolsTarget -AllowedRoot $root -Journal $Journal -JournalStep $JournalStep `
            -ExcludeTop @('__pycache__') -ExcludePatterns @('__pycache__\*','*.pyc','*.log','tmp-*','*.dpapi','broker_token.txt','totp_recovery.json') -Label 'tools'
        Copy-CyberButlerCoreTree -Source $webSource -Destination $webTarget -AllowedRoot $root -Journal $Journal -JournalStep $JournalStep `
            -ExcludeTop @('.venv', 'data', 'tests', '__pycache__') -ExcludePatterns @('.venv\*','data\*','tests\*','__pycache__\*','tmp-*','*.pyc','config.json') -Label 'webui'

        $releasePlugins = Join-Path $releaseRoot 'plugins'
        Write-Host 'CORE installing CBS security plugins...'
        $cbsResult = Copy-CyberButlerCbsPlugins -AstrBotPath $astrbotTarget -ReleasePluginsPath $releasePlugins -Journal $Journal -JournalStep $JournalStep
        Write-Host ('CORE CBS plugins: ' + $cbsResult.status + ' (' + @($cbsResult.plugins).Count + ')')
        try {
            $personalResult = Copy-CyberButlerPersonalPlugins -AstrBotPath $astrbotTarget -PersonalPluginsPath $PersonalPluginsPath -Repair:$Repair -Journal $Journal -JournalStep $JournalStep
            Write-Host ('CORE personal plugins: ' + $personalResult.status)
        } catch {
            $personalResult = [pscustomobject]@{ status = 'failed'; path = ''; plugins = @(); reason = $_.Exception.Message }
            Write-Host ('CORE personal plugins: failed - ' + $_.Exception.Message)
        }

        $toolReplacements = [ordered]@{
            'YOUR_PROJECT_PATH' = $root
            'YOUR_USER_PATH' = $env:USERPROFILE
            'YOUR_USER_NAME' = $env:USERNAME
            'YOUR_QQ_ID' = $OwnerQQ
            'YOUR_SERVICE_USER' = $ToolServiceAccount
        }
        # Plugins are copied by Copy-CyberButlerCbsPlugins before this point.
        # They are not under tools/, so they need the same placeholder pass.
        $pluginRoot = Join-Path $astrbotTarget 'data\plugins'
        foreach ($pluginFile in @(Get-ChildItem -LiteralPath $pluginRoot -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.py', '.yaml', '.yml', '.json') })) {
            $pluginText = [IO.File]::ReadAllText($pluginFile.FullName)
            $pluginChanged = $false
            foreach ($key in $toolReplacements.Keys) {
                $value = [string]$toolReplacements[$key]
                if ($value -and $pluginText.Contains($key)) {
                    $pluginText = $pluginText.Replace($key, $value)
                    $pluginChanged = $true
                }
            }
            if ($pluginChanged) { [IO.File]::WriteAllText($pluginFile.FullName, $pluginText, (New-Object Text.UTF8Encoding($false))) }
        }
        foreach ($toolFile in @(Get-ChildItem -LiteralPath $toolsTarget -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @('.ps1', '.py', '.json', '.psm1', '.cmd', '.bat') })) {
            $relativeTool = $toolFile.FullName.Substring($toolsTarget.Length).TrimStart([char]92)
            # The dashboard and its official modules use YOUR_QQ_ID as an
            # overlay JSON property name, not as an installer placeholder.
            # Rewriting them changes the source text and breaks the official
            # module SHA-256 trust check.
            if ($relativeTool -eq 'cyber_butler_dashboard.ps1' -or $relativeTool -like 'dashboard_plugins\*') {
                continue
            }
            $toolText = [IO.File]::ReadAllText($toolFile.FullName)
            $changed = $false
            foreach ($key in $toolReplacements.Keys) {
                $value = [string]$toolReplacements[$key]
                if ($value -and $toolText.Contains($key)) {
                    $toolText = $toolText.Replace($key, $value)
                    $changed = $true
                }
            }
            if ($changed) { [IO.File]::WriteAllText($toolFile.FullName, $toolText, (New-Object Text.UTF8Encoding($false))) }
        }

        # The dashboard is a large PowerShell script. A stale or hand-edited
        # copy can leave the shortcut opening a parser error instead of the UI.
        $dashboardScript = Join-Path $toolsTarget 'cyber_butler_dashboard.ps1'
        if (Test-Path -LiteralPath $dashboardScript) {
            $parseTokens = $null
            $parseErrors = $null
            [System.Management.Automation.Language.Parser]::ParseFile(
                $dashboardScript,
                [ref]$parseTokens,
                [ref]$parseErrors
            ) | Out-Null
            if ($parseErrors -and $parseErrors.Count -gt 0) {
                $first = $parseErrors[0]
                throw ('dashboard syntax error at line ' + $first.Extent.StartLineNumber + ': ' + $first.Message)
            }
        }

        $webConfigPath = Join-Path $webTarget 'config.json'
        $desktopRoot = [Environment]::GetFolderPath('Desktop')
        if ([string]::IsNullOrWhiteSpace($desktopRoot)) {
            $desktopRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Desktop'
        }
        $bigFishRoot = Join-Path $desktopRoot '大肥鱼专用文件夹'
        New-Item -ItemType Directory -Path $bigFishRoot -Force | Out-Null
        if (-not (Test-Path -LiteralPath $webConfigPath)) {
            $templatePath = Join-Path $webTarget 'example-config.json'
            if (Test-Path -LiteralPath $templatePath) {
                $webConfig = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $webConfig.admin_email = $WebUIAdminEmail
                $webConfig.project_root = $root
                $webConfig.file_root = $bigFishRoot
                Write-InstallerJson -Path $webConfigPath -Value $webConfig
            }
        } else {
            try {
                $webConfig = Get-Content -LiteralPath $webConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]::IsNullOrWhiteSpace([string]$webConfig.file_root)) {
                    $webConfig.file_root = $bigFishRoot
                    Write-InstallerJson -Path $webConfigPath -Value $webConfig
                }
            } catch { }
        }

        $brokerConfigPath = Join-Path $toolsTarget 'broker_config.json'
        try {
            if (Test-Path -LiteralPath $brokerConfigPath) {
                $brokerConfig = Get-Content -LiteralPath $brokerConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
            } else {
                $brokerConfig = [pscustomobject]@{
                    approval_channel = 'qq'
                    admin_email = ''
                }
                Write-Host 'CORE broker_config: creating first-run configuration'
            }
            $brokerConfig | Add-Member -NotePropertyName admin_email -NotePropertyValue $WebUIAdminEmail -Force
            if ($WebUIAdminEmail) { $brokerConfig | Add-Member -NotePropertyName approval_channel -NotePropertyValue 'email' -Force }
            Write-InstallerJson -Path $brokerConfigPath -Value $brokerConfig
        } catch {
            throw ('CORE broker_config initialization failed: ' + $_.Exception.Message)
        }

        if (-not $SkipDependencyInstall) {
            $python = Get-CyberButlerCorePython -PreferredPath $PythonPath -ServiceRoot $root -Isolation:($Tier -eq 'High')
            Write-Host ('CORE creating virtual environment with ' + $python + '...')
            $venvDir = Join-Path $astrbotTarget '.venv'
            & $python -m venv $venvDir
            if ($LASTEXITCODE -ne 0) { throw 'python -m venv failed.' }
            $venvPython = Join-Path $venvDir 'Scripts\python.exe'
            $webVenv = Join-Path $webTarget '.venv'
            & $python -m venv $webVenv
            if ($LASTEXITCODE -ne 0) { throw 'webui python -m venv failed.' }
            $webRequirements = Join-Path $webTarget 'requirements.txt'
            if ((Test-Path -LiteralPath $webRequirements) -and (Get-Item -LiteralPath $webRequirements).Length -gt 0) {
                $webPipLog = Join-Path $root 'installer-report\webui-pip-install.log'
                Write-Host 'CORE installing Web UI dependencies (this may take several minutes)...'
                Write-Host ('CORE Web UI pip log: ' + $webPipLog)
                $webPipRun = Invoke-CyberButlerPipInstall -PythonPath (Join-Path $webVenv 'Scripts\python.exe') -Requirements $webRequirements -LogPath $webPipLog -SitePackagesPath (Join-Path $webVenv 'Lib\site-packages')
                if ($webPipRun.exit_code -ne 0) { throw ("Web UI pip install failed. pip log: " + $webPipLog) }
                Write-Host 'CORE Web UI dependencies installed.'
            }
            $requirements = Join-Path $astrbotTarget 'requirements.txt'
            if ((Test-Path -LiteralPath $requirements) -and (Get-Item -LiteralPath $requirements).Length -gt 0) {
                # Deprecated 3.0.0 uses PEP 695 ``type`` syntax and fails on
                # Python 3.10, which is the bundled runtime on existing installs.
                $reqText = [IO.File]::ReadAllText($requirements)
                if ($reqText -notmatch '(?im)^\s*deprecated\s*<') {
                    $reqText = $reqText.TrimEnd() + [Environment]::NewLine + 'deprecated<3' + [Environment]::NewLine
                }
                if ([string]$PythonVersion -match 'Python\s+3\.(10|11)' -and $reqText -notmatch '(?im)^\s*greenlet\s*<') {
                    $reqText = $reqText.TrimEnd() + [Environment]::NewLine + 'greenlet<3.2' + [Environment]::NewLine
                }
                [IO.File]::WriteAllText($requirements, $reqText, (New-Object Text.UTF8Encoding($false)))
                $pipLog = if ($PipLogPath) { $PipLogPath } else { Join-Path $root 'installer-report\pip-install.log' }
                Write-Host 'CORE installing dependencies (this may take several minutes)...'
                Write-Host ('CORE pip log: ' + $pipLog)
                $pipRun = Invoke-CyberButlerPipInstall -PythonPath $venvPython -Requirements $requirements -LogPath $pipLog -SitePackagesPath (Join-Path $venvDir 'Lib\site-packages')
                if ($pipRun.exit_code -ne 0) {
                    $pipOutput = ($pipRun.output -join "`n")
                    $excerpt = (($pipRun.output | Select-Object -Last 12) -join "`n")
                    if ($pipOutput -match 'Requires-Python|No matching distribution|Could not find a version') {
                        throw ("pip dependency resolution failed. AstrBot supports Python 3.10-3.13; Python 3.14+ is not supported by faiss-cpu. Install Python 3.13 and retry. pip log: " + $pipLog + ". Tail: " + $excerpt)
                    }
                    throw ("pip install -r requirements.txt failed. pip log: " + $pipLog + ". Tail: " + $excerpt)
                }
                Write-Host 'CORE dependencies installed.'
            }
            if ((Test-Path -LiteralPath $requirements) -and (Get-Item -LiteralPath $requirements).Length -gt 0) {
                Write-Host 'CORE import smoke: astrbot.core'
                $smoke = Test-CyberButlerCoreImportSmoke -InstallPath $root -PythonPath $venvPython -Handlers $Handlers
                if (-not $smoke.ok) {
                    throw ('AstrBot import smoke failed (exit ' + $smoke.exit_code + '): ' + ((@($smoke.output) | Select-Object -Last 8) -join ' | '))
                }
                Write-Host 'CORE import smoke: ok'
            }
        } else {
            New-Item -ItemType Directory -Path (Join-Path $astrbotTarget '.venv\Scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $astrbotTarget '.venv\Scripts\python.exe') -Value '' -Encoding ASCII
            New-Item -ItemType Directory -Path (Join-Path $webTarget '.venv\Scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $webTarget '.venv\Scripts\python.exe') -Value '' -Encoding ASCII
        }

        $asserted = Test-CyberButlerCoreDeploy -InstallPath $root -Handlers $Handlers
        if (-not $asserted.satisfied) { throw ('Core deployment assertion failed: ' + ($asserted.missing -join ', ')) }
        if (-not (Test-Path -LiteralPath $workspaceTarget)) { throw 'workspace directory missing.' }
        if (-not (Test-Path -LiteralPath $dataTarget)) { throw 'data directory missing.' }

        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        if ($null -ne $Journal -and $stepStarted) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status completed -Details ([pscustomobject]@{ reason = 'core deployment completed'; existing_state = $ExistingState; python_source = $PythonSource; python_path = $PythonPath; python_version = $PythonVersion; cbs_plugins_status = [string]$cbsResult.status; cbs_plugins = @($cbsResult.plugins); personal_plugins_path = [string]$PersonalPluginsPath; personal_plugins_status = [string]$personalResult.status; personal_plugins_error = [string]$personalResult.reason; personal_plugins = @($personalResult.plugins) }) | Out-Null
        }
        return [pscustomobject]@{
            status = 'completed'; changed = $true; exit_code = 0; test = $asserted; existing_state = $ExistingState
            reason = 'core deployment completed'; python_source = $PythonSource; python_path = $PythonPath; python_version = $PythonVersion
            cbs_plugins_status = [string]$cbsResult.status; cbs_plugins = @($cbsResult.plugins)
            personal_plugins_path = [string]$PersonalPluginsPath; personal_plugins_status = [string]$personalResult.status; personal_plugins_error = [string]$personalResult.reason; personal_plugins = @($personalResult.plugins)
            paths = [pscustomobject]@{
                astrbot = $astrbotTarget
                snowluma = $snowTarget
                tools = $toolsTarget
                webui = $webTarget
                workspace = $workspaceTarget
                data = $dataTarget
                astrbot_data = $astrbotDataTarget
            }
        }
    } catch {
        $rawError = [string]$_.Exception.Message
        $safeError = $rawError
        $lockedPath = ''
        $pathMatch = [regex]::Match($rawError, '([A-Za-z]:\[^"

]+)')
        if ($pathMatch.Success) { $lockedPath = $pathMatch.Groups[1].Value }
        if ($rawError -match '(?i)(node\.exe|being used by another process|另一个进程|正由另一进程|使用中|锁定)' -or $rawError -match '[�ʹʺ]') {
            $safeError = 'CORE file is in use. Stop AstrBot, SnowLuma, WebUI and Broker, then retry.'
            if ($lockedPath) { $safeError += ' Path: ' + $lockedPath }
        }
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
        if ($ExistingState -eq 'None') {
            $paths = @($createdDirs)
            [array]::Reverse($paths)
            foreach ($path in $paths) {
                if ($path -eq $staging) { continue }
                if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue }
            }
        }
        if ($null -ne $Journal -and $stepStarted) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ error = $safeError }) | Out-Null
        }
        return [pscustomobject]@{ status = 'failed'; changed = $false; exit_code = 20; message = $safeError; reason = $safeError; created_dirs = $createdDirs.ToArray() }
    }
}
