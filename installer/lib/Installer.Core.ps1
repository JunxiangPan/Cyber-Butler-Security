# Real core deployment: download, verify, extract, venv, overlay.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

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
    $wheelhouse = Join-Path (Split-Path -Parent $PSScriptRoot) 'wheelhouse'
    $hasWheelhouse = (Test-Path -LiteralPath $wheelhouse) -and @(Get-ChildItem -LiteralPath $wheelhouse -Filter '*.whl' -File -ErrorAction SilentlyContinue).Count -gt 0
    $command = (& $quote $PythonPath) + ' -m pip install --disable-pip-version-check --progress-bar on'
    if ($hasWheelhouse) {
        $command += ' --no-index --find-links ' + (& $quote $wheelhouse)
        Write-Host ('CORE pip source: offline wheelhouse ' + $wheelhouse)
    } else {
        Write-Host 'CORE pip source: PyPI (wheelhouse not present)'
    }
    $command += ' -r ' + (& $quote $Requirements)
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
    $exitCode = [int]$process.ExitCode
    $combinedText = (@($lines) | Out-String)
    if ($exitCode -eq 0 -and $combinedText -match '(?im)^\s*ERROR:\s') {
        $exitCode = 1
    }
    return [pscustomobject]@{
        exit_code = $exitCode
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
    $missing = New-Object System.Collections.Generic.List[string]
    foreach ($rel in @('tools/broker.py','tools\email_approval.py','tools\wfp_guard.py','webui/run.py','webui/requirements.txt','workspace','data')) {
        if (-not (Test-Path -LiteralPath (Join-Path $root $rel))) { $missing.Add($rel) }
    }
    $venvPython = Join-Path $root 'webui\.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $venvPython)) { $missing.Add('webui/.venv/Scripts/python.exe') }
    if (-not (Test-Path -LiteralPath (Join-Path $root 'VERSION'))) { $missing.Add('VERSION') }
    $satisfied = $missing.Count -eq 0
    return [pscustomobject]@{
        satisfied = [bool]$satisfied
        install_path = $root
        missing = $missing.ToArray()
        reason = if ($satisfied) { 'CBS core tree present' } else { 'CBS core incomplete: ' + ($missing -join ', ') }
    }
}

function Test-CyberButlerCbsPythonDependencies {
    param([Parameter(Mandatory = $true)][string]$PythonPath)
    if (-not (Test-Path -LiteralPath $PythonPath)) { return [pscustomobject]@{ ok = $false; reason = 'python missing' } }
    $probe = & $PythonPath -c 'import fastapi, uvicorn, httpx, pyotp, qrcode, win32crypt' 2>&1 | Out-String
    return [pscustomobject]@{ ok = ($LASTEXITCODE -eq 0); reason = $probe.Trim() }
}

function Invoke-CyberButlerCoreDeploy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [string]$ExistingState = 'None',
        [string]$Tier = 'Medium',
        [string]$ExternalAgentPackage = '',
        [string]$ExternalApplicationPackage = '',
        [string]$ExternalAgentSha256 = '',
        [string]$ExternalApplicationSha256 = '',
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
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'core.deploy' -Context ([pscustomobject]@{ Root = $InstallPath; ExistingState = $ExistingState; Tier = $Tier }))
    }

    $test = Test-CyberButlerCoreDeploy -InstallPath $InstallPath -Handlers $Handlers
    if ($test.satisfied -and -not $SkipDependencyInstall) {
        $dependencyProbe = Test-CyberButlerCbsPythonDependencies -PythonPath (Join-Path $InstallPath 'webui\.venv\Scripts\python.exe')
        if (-not $dependencyProbe.ok) {
            $test.satisfied = $false
            $test.reason = 'CBS Python dependencies missing: ' + $dependencyProbe.reason
            Write-Host ('CORE dependency probe failed: ' + $dependencyProbe.reason)
        }
    }
    $root = [IO.Path]::GetFullPath($InstallPath)
    $paths = [pscustomobject]@{
        tools = Join-Path $root 'tools'
        webui = Join-Path $root 'webui'
        workspace = Join-Path $root 'workspace'
        data = Join-Path $root 'data'
    }
    if ($test.satisfied) {
        return [pscustomobject]@{ status = 'skipped'; changed = $false; exit_code = 0; test = $test; reason = 'CBS core already present'; paths = $paths }
    }

    $releaseRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $stepStarted = $false
    if ($null -ne $Journal) {
        Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status in_progress | Out-Null
        $stepStarted = $true
    }
    try {
        foreach ($dir in @($root, $paths.tools, $paths.webui, $paths.workspace, $paths.data)) {
            if (-not (Test-Path -LiteralPath $dir)) {
                if ($null -ne $Journal) {
                    New-CyberButlerTrackedDirectory -Journal $Journal -Step $JournalStep -Path $dir -AllowedRoot $root | Out-Null
                } else {
                    New-Item -ItemType Directory -Path $dir -Force | Out-Null
                }
            }
        }
        if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot 'tools'))) { throw ('Tools tree missing: ' + (Join-Path $releaseRoot 'tools')) }
        if (-not (Test-Path -LiteralPath (Join-Path $releaseRoot 'webui'))) { throw ('Web UI tree missing: ' + (Join-Path $releaseRoot 'webui')) }
        Copy-CyberButlerCoreTree -Source (Join-Path $releaseRoot 'tools') -Destination $paths.tools -AllowedRoot $root -Journal $Journal -JournalStep $JournalStep `
            -ExcludeTop @('__pycache__') -ExcludePatterns @('__pycache__\*','*.pyc','*.log','tmp-*','*.dpapi','broker_token.txt','totp_recovery.json') -Label 'tools'
        Copy-CyberButlerCoreTree -Source (Join-Path $releaseRoot 'webui') -Destination $paths.webui -AllowedRoot $root -Journal $Journal -JournalStep $JournalStep `
            -ExcludeTop @('.venv', 'data', 'tests', '__pycache__') -ExcludePatterns @('.venv\*','data\*','tests\*','__pycache__\*','tmp-*','*.pyc','config.json') -Label 'webui'
        Set-Content -LiteralPath (Join-Path $root 'VERSION') -Value ((Get-Content -LiteralPath (Join-Path $releaseRoot 'VERSION') -Raw -Encoding UTF8).Trim()) -Encoding ASCII

        $webConfigPath = Join-Path $paths.webui 'config.json'
        if (-not (Test-Path -LiteralPath $webConfigPath)) {
            $templatePath = Join-Path $paths.webui 'example-config.json'
            if (Test-Path -LiteralPath $templatePath) {
                $webConfig = Get-Content -LiteralPath $templatePath -Raw -Encoding UTF8 | ConvertFrom-Json
                $webConfig.admin_email = $WebUIAdminEmail
                $webConfig.project_root = $root
                $webConfig.file_root = Join-Path ([Environment]::GetFolderPath('Desktop')) '大肥鱼专用文件夹'
                Write-InstallerJson -Path $webConfigPath -Value $webConfig
            }
        }
        $brokerConfigPath = Join-Path $paths.tools 'broker_config.json'
        $brokerConfig = [pscustomobject]@{ approval_channel = 'qq'; admin_email = '' }
        if (Test-Path -LiteralPath $brokerConfigPath) {
            try { $brokerConfig = Get-Content -LiteralPath $brokerConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { }
        }
        $brokerConfig | Add-Member -NotePropertyName admin_email -NotePropertyValue $WebUIAdminEmail -Force
        Write-InstallerJson -Path $brokerConfigPath -Value $brokerConfig

        $webVenv = Join-Path $paths.webui '.venv'
        if (-not $SkipDependencyInstall) {
            $python = Get-CyberButlerCorePython -PreferredPath $PythonPath -ServiceRoot $root -Isolation:($Tier -eq 'High')
            & $python -m venv $webVenv
            if ($LASTEXITCODE -ne 0) { throw 'webui python -m venv failed.' }
            $webRequirements = Join-Path $paths.webui 'requirements.txt'
            $webPipLog = Join-Path $root 'installer-report\webui-pip-install.log'
            $webPipRun = Invoke-CyberButlerPipInstall -PythonPath (Join-Path $webVenv 'Scripts\python.exe') -Requirements $webRequirements -LogPath $webPipLog -SitePackagesPath (Join-Path $webVenv 'Lib\site-packages')
            if ($webPipRun.exit_code -ne 0) { throw ('CBS Web UI pip install failed. pip log: ' + $webPipLog) }
        } else {
            New-Item -ItemType Directory -Path (Join-Path $webVenv 'Scripts') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $webVenv 'Scripts\python.exe') -Value '' -Encoding ASCII
        }

        $asserted = Test-CyberButlerCoreDeploy -InstallPath $root -Handlers $Handlers
        if (-not $asserted.satisfied) { throw ('CBS core assertion failed: ' + ($asserted.missing -join ', ')) }
        if ($null -ne $Journal -and $stepStarted) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status completed -Details ([pscustomobject]@{ reason = 'independent CBS core deployed'; existing_state = $ExistingState }) | Out-Null
        }
        return [pscustomobject]@{ status = 'completed'; changed = $true; exit_code = 0; test = $asserted; reason = 'independent CBS core deployed'; paths = $paths }
    } catch {
        if ($null -ne $Journal -and $stepStarted) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ error = [string]$_.Exception.Message }) | Out-Null
        }
        return [pscustomobject]@{ status = 'failed'; changed = $false; exit_code = 20; message = [string]$_.Exception.Message; reason = [string]$_.Exception.Message; paths = $paths }
    }
}
