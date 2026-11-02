# Bundled Python 3.13 bootstrap for the Cyber-Butler installer.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

function Get-CyberButlerPythonTargetPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )
    return (Join-Path ([IO.Path]::GetFullPath($InstallPath)) '.python\python.exe')
}

function Get-CyberButlerPythonSourceConfig {
    param([string]$CoreSourcesPath = '')
    if ([string]::IsNullOrWhiteSpace($CoreSourcesPath)) {
        $CoreSourcesPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'core-sources.json'
    }
    if (-not (Test-Path -LiteralPath $CoreSourcesPath)) { throw "Core source config not found: $CoreSourcesPath" }
    $config = Get-Content -LiteralPath $CoreSourcesPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $config.python) { throw 'Python source entry missing from core-sources.json.' }
    return $config.python
}

function Get-CyberButlerExistingSystemPython {
    $paths = New-Object System.Collections.Generic.List[string]
    if ($env:LOCALAPPDATA) {
        foreach ($version in @('Python313', 'Python312', 'Python311', 'Python310')) {
            $paths.Add((Join-Path $env:LOCALAPPDATA ('Programs\Python' + $version + '\python.exe')))
        }
    }
    foreach ($root in @('C:\Python313', 'C:\Python312', 'C:\Python311', 'C:\Python310',
                       'C:\Program Files\Python313', 'C:\Program Files\Python312',
                       'C:\Program Files\Python311', 'C:\Program Files\Python310')) {
        $paths.Add((Join-Path $root 'python.exe'))
    }
    try {
        foreach ($profile in @(Get-ChildItem -LiteralPath 'C:\Users' -Directory -ErrorAction SilentlyContinue)) {
            foreach ($version in @('Python313', 'Python312', 'Python311', 'Python310')) {
                $paths.Add((Join-Path $profile.FullName ('AppData\Local\Programs\Python\' + $version + '\python.exe')))
            }
        }
    } catch { }
    foreach ($tree in @('HKCU:\Software\Python\PythonCore\3.13\InstallPath',
                        'HKLM:\Software\Python\PythonCore\3.13\InstallPath',
                        'HKLM:\Software\WOW6432Node\Python\PythonCore\3.13\InstallPath')) {
        try {
            $value = (Get-ItemProperty -LiteralPath $tree -ErrorAction Stop).'(default)'
            if ($value) { $paths.Add((Join-Path ([string]$value) 'python.exe')) }
        } catch { }
    }
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace([string]$path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        try {
            $version = (& $path --version 2>&1 | Out-String).Trim()
            $probe = (& $path -c "import sys; print(sys.executable)" 2>$null | Out-String).Trim()
            if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($probe)) { continue }
            $pip = $false
            & $path -m pip --version 2>&1 | Out-Null
            $pip = ($LASTEXITCODE -eq 0)
            if ($version -match 'Python\s+3\.(1[0-3])\.' -and $pip) {
                return [pscustomobject]@{
                    found = $true
                    path = [IO.Path]::GetFullPath($probe)
                    version = $version
                    python_source = 'system'
                }
            }
        } catch { }
    }
    return [pscustomobject]@{ found = $false }
}

function Test-CyberButlerBundledPython {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )
    $path = Get-CyberButlerPythonTargetPath -InstallPath $InstallPath
    $result = [ordered]@{
        found = $false
        path = $path
        version = $null
        version_ok = $false
        pip_ok = $false
        reason = ''
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { $result.reason = 'missing'; return [pscustomobject]$result }
    $probe = $null
    try {
        $probe = (& $path -c "import sys; print(sys.executable)" 2>$null | Out-String).Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($probe)) { throw 'probe failed' }
    } catch {
        $result.reason = 'probe-failed'
        return [pscustomobject]$result
    }
    $result.found = $true
    $result.version = (& $path --version 2>&1 | Out-String).Trim()
    if ($result.version -match 'Python\s+3\.(1[0-3])\.') { $result.version_ok = $true }
    try {
        & $path -m pip --version 2>&1 | Out-Null
        $result.pip_ok = ($LASTEXITCODE -eq 0)
    } catch { $result.pip_ok = $false }
    if (-not $result.version_ok) { $result.reason = 'unsupported-version' }
    elseif (-not $result.pip_ok) { $result.reason = 'pip-missing' }
    else { $result.reason = 'ready' }
    return [pscustomobject]$result
}

function Get-CyberButlerPythonRegistryKey {
    param([string]$TargetRoot)
    $keys = New-Object System.Collections.Generic.List[string]
    $roots = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    foreach ($root in $roots) {
        try {
            foreach ($item in @(Get-ItemProperty -Path $root -ErrorAction SilentlyContinue)) {
                if ([string]$item.DisplayName -match '^Python 3\.13\.17') {
                    $keys.Add([string]$item.PSPath)
                }
            }
        } catch { }
    }
    return $keys.ToArray()
}

function Invoke-CyberButlerPythonBootstrap {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [string]$PythonPackage = '',
        [string]$PythonSha256 = '',
        [string]$CoreSourcesPath = '',
        [int]$DownloadTimeoutSeconds = 300,
        [int]$DownloadRetryCount = 3,
        [string]$JournalStep = 'python',
        $Journal = $null,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'python.bootstrap') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'python.bootstrap' -Context ([pscustomobject]@{ InstallPath = $InstallPath; PythonPackage = $PythonPackage }))
    }

    $existing = Test-CyberButlerBundledPython -InstallPath $InstallPath
    if ($existing.found -and $existing.version_ok -and $existing.pip_ok) {
        return [pscustomobject]@{
            status = 'skipped'; reason = 'bundled Python already present'; python_source = 'bundled'
            python_path = $existing.path; python_version = $existing.version; created = $false
        }
    }

    # Reuse a valid per-user/system interpreter before touching the Python
    # bootstrapper. This avoids the per-user vs per-machine MSI conflict.
    $systemPython = if (-not $PythonPackage -and -not $PythonSha256) { Get-CyberButlerExistingSystemPython } else { [pscustomobject]@{ found = $false } }
    if ($systemPython.found) {
        return [pscustomobject]@{
            status = 'skipped'; reason = 'valid system/per-user Python reused'
            python_source = 'system'; python_path = $systemPython.path
            python_version = $systemPython.version; created = $false
        }
    }

    $root = [IO.Path]::GetFullPath($InstallPath)
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    $targetRoot = Join-Path $root '.python'
    $createdTarget = -not (Test-Path -LiteralPath $targetRoot)
    $staging = Join-Path $root ('.python-installer-' + [guid]::NewGuid().ToString('N') + '.exe')
    if ($null -ne $Journal) { Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status in_progress | Out-Null }
    $source = Get-CyberButlerPythonSourceConfig -CoreSourcesPath $CoreSourcesPath
    $url = if ($PythonPackage) { $PythonPackage } else { [string]$source.url }
    $hash = if ($PythonSha256) { $PythonSha256 } else { [string]$source.sha256 }
    if ([string]::IsNullOrWhiteSpace($url)) { throw 'Python source URL missing.' }
    if ([string]::IsNullOrWhiteSpace($hash)) { throw 'Python source SHA-256 missing.' }
    if (-not $PythonPackage -and $url -notmatch '^https?://') { throw 'Python source must be an HTTP(S) URL or -PythonPackage .exe.' }
    if ($PythonPackage -and [IO.Path]::GetExtension($PythonPackage) -ine '.exe') { throw '-PythonPackage must be the official Python .exe installer.' }

    try {
        Write-Host ('PYTHON downloading Python ' + [string]$source.version + ' installer...')
        if ($url -match '^https?://') {
            $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
            $attempt = 0
            $lastError = $null
            while ($attempt -lt [Math]::Max(1, $DownloadRetryCount)) {
                $attempt++
                try {
                    if ($curl) {
                        & $curl.Source -L --fail --progress-bar --connect-timeout 30 --max-time $DownloadTimeoutSeconds -o $staging $url
                        if ($LASTEXITCODE -ne 0) { throw "curl exit code $LASTEXITCODE" }
                    } else {
                        Invoke-WebRequest -Uri $url -OutFile $staging -UseBasicParsing -TimeoutSec $DownloadTimeoutSeconds -ErrorAction Stop
                    }
                    $lastError = $null
                    break
                } catch {
                    $lastError = $_
                    if (Test-Path -LiteralPath $staging) { Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue }
                    if ($attempt -lt $DownloadRetryCount) { Start-Sleep -Seconds ($attempt * 2) }
                }
            }
            if ($lastError) { throw ('Python download failed: ' + $lastError.Exception.Message) }
        } else {
            Copy-Item -LiteralPath $url -Destination $staging -Force
        }

        $actual = (Get-FileHash -LiteralPath $staging -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne ([string]$hash).ToLowerInvariant()) {
            if ($null -ne $Journal) {
                Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ reason = 'sha_mismatch'; expected = $hash; actual = $actual }) | Out-Null
            }
            Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue
            return [pscustomobject]@{ status = 'failed'; code = 'python_bootstrap_failed'; reason = 'sha_mismatch'; message = ('Python installer SHA-256 mismatch: expected ' + $hash + ', got ' + $actual) }
        }

        Write-Host 'PYTHON installing Python 3.13 into .python (this may take several minutes)...'
        $pythonLog = Join-Path $root 'python-install.log'
        # InstallAllUsers=1 is required for a reliable custom TargetDir on a
        # clean Windows image; InstallAllUsers=0 can silently install into the
        # current user's profile. Keep the official installer log for support.
        $arguments = '/quiet InstallAllUsers=0 TargetDir="' + $targetRoot + '" Include_pip=1 Include_launcher=0 Include_test=0 PrependPath=0 Shortcuts=0 AssociateFiles=0 /log "' + $pythonLog + '"'
        $process = Start-Process -FilePath $staging -ArgumentList $arguments -WindowStyle Hidden -Wait -PassThru
        if ($process.ExitCode -notin @(0, 3010)) {
            throw ('Python installer exit code ' + $process.ExitCode + '; log: ' + $pythonLog)
        }

        # Some Windows installer bootstrappers return before the MSI payload is
        # fully observable. Poll briefly instead of reporting a false missing.
        $pythonExe = Get-CyberButlerPythonTargetPath -InstallPath $root
        $deadline = (Get-Date).AddSeconds(90)
        while (-not (Test-Path -LiteralPath $pythonExe -PathType Leaf) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 2
        }

        $verified = Test-CyberButlerBundledPython -InstallPath $root
        if (-not $verified.found) {
            throw ('Bundled Python verification failed: missing at ' + $pythonExe + '; installer log: ' + $pythonLog)
        }
        if (-not $verified.found -or -not $verified.version_ok -or -not $verified.pip_ok) {
            throw ('Bundled Python verification failed: ' + $verified.reason)
        }
        if ($null -ne $Journal -and $createdTarget) {
            Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                type = 'delete-created-directory'
                path = [IO.Path]::GetFullPath($targetRoot)
                allowed_root = $root
            })
        }
        $registryKey = Get-CyberButlerPythonRegistryKey -TargetRoot $targetRoot
        $details = [pscustomobject]@{
            reason = 'bundled Python installed'
            python_source = 'bundled'
            python_path = $verified.path
            python_version = $verified.version
            registry_key = $registryKey
        }
        if ($null -ne $Journal) { Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status completed -Details $details | Out-Null }
        Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{
            status = 'completed'; reason = 'bundled Python installed'; python_source = 'bundled'
            python_path = $verified.path; python_version = $verified.version; created = $createdTarget
            registry_key = $registryKey
        }
    } catch {
        Remove-Item -LiteralPath $staging -Force -ErrorAction SilentlyContinue
        if ($createdTarget -and (Test-Path -LiteralPath $targetRoot)) {
            Remove-Item -LiteralPath $targetRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ reason = 'python_bootstrap_failed'; error = $_.Exception.Message }) | Out-Null
        }
        return [pscustomobject]@{ status = 'failed'; code = 'python_bootstrap_failed'; reason = 'install_failed'; message = $_.Exception.Message }
    }
}
