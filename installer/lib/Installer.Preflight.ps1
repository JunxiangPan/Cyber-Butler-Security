# Read-only preflight for the Cyber-Butler installer.
# Dot-source Installer.Common.ps1 before this file.

if (-not (Get-Command Get-CyberButlerExistingState -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'Installer.Common.ps1')
}

<#
.SYNOPSIS
    Get-CyberButlerPortSnapshot performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerPortSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports
    )

    $results = New-Object System.Collections.Generic.List[object]
    $hasNetTcp = $null -ne (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)

    foreach ($port in $Ports) {
        $inUse = $false
        $pidValue = $null
        $processName = $null
        $listener = $null

        if ($hasNetTcp) {
            try {
                $connections = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction Stop)
                if ($connections.Count -gt 0) {
                    $inUse = $true
                    $pidValue = [int]$connections[0].OwningProcess
                    $listener = [string]$connections[0].LocalAddress
                    $process = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
                    if ($process) { $processName = [string]$process.ProcessName }
                }
            } catch {
                $hasNetTcp = $false
            }
        }

        if (-not $hasNetTcp) {
            $client = New-Object System.Net.Sockets.TcpClient
            try {
                $async = $client.BeginConnect('127.0.0.1', $port, $null, $null)
                $inUse = $async.AsyncWaitHandle.WaitOne(120, $false) -and $client.Connected
                if ($inUse) { $listener = '127.0.0.1' }
            } catch {
                $inUse = $false
            } finally {
                $client.Close()
            }
        }

        $results.Add([pscustomobject][ordered]@{
            port = $port
            in_use = [bool]$inUse
            listener = $listener
            pid = $pidValue
            process_name = $processName
        })
    }

    return $results.ToArray()
}

<#
.SYNOPSIS
    Get-CyberButlerProcessSnapshot performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerProcessSnapshot {
    param(
        [object[]]$PortSnapshot = @()
    )

    $result = [ordered]@{
        agentruntime = @()
        auxruntime = @()
        broker = @()
    }

    try {
        $processes = @(Get-CimInstance Win32_Process -ErrorAction Stop)
    } catch {
        return [pscustomobject]$result
    }

    $agentruntime = New-Object System.Collections.Generic.List[object]
    $auxruntime = New-Object System.Collections.Generic.List[object]
    $broker = New-Object System.Collections.Generic.List[object]
    $agentruntimePids = @($PortSnapshot | Where-Object { $_.port -eq 6185 -and $_.pid } | ForEach-Object { [int]$_.pid })
    $brokerPids = @($PortSnapshot | Where-Object { $_.port -eq 18090 -and $_.pid } | ForEach-Object { [int]$_.pid })

    foreach ($process in $processes) {
        $name = [string]$process.Name
        $command = [string]$process.CommandLine
        $pidValue = [int]$process.ProcessId
        $isAgentRuntimePort = $agentruntimePids -contains $pidValue
        $isBrokerPort = $brokerPids -contains $pidValue
        if (-not $command -and -not $isAgentRuntimePort -and -not $isBrokerPort) { continue }
        $item = [pscustomobject][ordered]@{
            pid = $pidValue
            name = $name
            command_line = if ($command.Length -gt 320) { $command.Substring(0, 320) } else { $command }
            detected_by = if ($isAgentRuntimePort -or $isBrokerPort) { 'port' } else { 'command-line' }
        }
        if ($name -ieq 'python.exe' -and ($command -match 'main\.py' -or $isAgentRuntimePort)) {
            $agentruntime.Add($item)
        }
        if ($name -ieq 'python.exe' -and ($command -match 'tools[\/]broker\.py' -or $isBrokerPort)) {
            $broker.Add($item)
        }
        if ($name -ieq 'node.exe' -and $command -match 'AuxRuntimeApplication') {
            $auxruntime.Add($item)
        }
    }

    $result['agentruntime'] = $agentruntime.ToArray()
    $result['auxruntime'] = $auxruntime.ToArray()
    $result['broker'] = $broker.ToArray()
    return [pscustomobject]$result
}

<#
.SYNOPSIS
    Get-CyberButlerScheduledTaskSnapshot performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerScheduledTaskSnapshot {
    param()

    $result = [ordered]@{ available = $false; tasks = @(); error = $null }
    $command = Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue
    if (-not $command) {
        $result.error = 'Get-ScheduledTask is unavailable'
        return [pscustomobject]$result
    }

    try {
        $tasks = @(Get-ScheduledTask -ErrorAction Stop)
        $wanted = New-Object System.Collections.Generic.List[object]
        foreach ($task in $tasks) {
            if ([string]$task.TaskName -notmatch 'AgentRuntime|AuxRuntimeApplication|Ollama|Game Mode|Cyber-Butler') { continue }
            $principal = $null
            try { $principal = [string]$task.Principal.UserId } catch { Write-Verbose 'optional operation failed' }
            $wanted.Add([pscustomobject][ordered]@{
                task_name = [string]$task.TaskName
                task_path = [string]$task.TaskPath
                state = [string]$task.State
                principal = $principal
            })
        }
        $result.available = $true
        $result['tasks'] = $wanted.ToArray()
    } catch {
        $result.error = $_.Exception.Message
    }
    return [pscustomobject]$result
}

<#
.SYNOPSIS
    Get-CyberButlerDefenderSnapshot performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerDefenderSnapshot {
    param()

    $result = [ordered]@{
        available = $false
        antivirus_enabled = $null
        real_time_protection = $null
        tamper_protected = $null
        error = $null
    }

    if (-not (Get-Command Get-MpComputerStatus -ErrorAction SilentlyContinue)) {
        $result.error = 'Get-MpComputerStatus is unavailable'
        return [pscustomobject]$result
    }

    try {
        $status = Get-MpComputerStatus -ErrorAction Stop
        $result.available = $true
        $result.antivirus_enabled = [bool]$status.AntivirusEnabled
        $result.real_time_protection = [bool]$status.RealTimeProtectionEnabled
        $result.tamper_protected = [bool]$status.IsTamperProtected
    } catch {
        $result.error = $_.Exception.Message
    }
    return [pscustomobject]$result
}

<#
.SYNOPSIS
    Get-CyberButlerPythonSnapshot performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerPythonSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [string[]]$CandidatePaths = @()
    )

    $candidates = New-Object System.Collections.Generic.List[object]
    $seen = New-Object System.Collections.Generic.HashSet[string]
    $paths = New-Object System.Collections.Generic.List[string]
    if ($CandidatePaths.Count -gt 0) {
        foreach ($candidate in $CandidatePaths) { if ($candidate) { $paths.Add([string]$candidate) } }
    } else {
        $paths.Add((Join-Path $InstallPath 'python\python.exe'))
        $command = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($command) { $paths.Add([string]$command.Source) }
        $launcher = Get-Command py.exe -ErrorAction SilentlyContinue
        if ($launcher) { $paths.Add([string]$launcher.Source) }
        $paths.Add((Join-Path $InstallPath 'AgentRuntime\.venv\Scripts\python.exe'))
        # Python's official installer normally installs per-user into this
        # directory. It may not be on PATH, so probe it explicitly before
        # deciding that a bundled interpreter is required.
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
        # The installer may run as a different account (for example SYSTEM)
        # while the per-user Python belongs to the interactive owner. Probe
        # every profile and the official registry InstallPath as well.
        try {
            foreach ($profile in @(Get-ChildItem -LiteralPath (Join-Path $env:SystemDrive 'Users') -Directory -ErrorAction SilentlyContinue)) {
                foreach ($version in @('Python313', 'Python312', 'Python311', 'Python310')) {
                    $paths.Add((Join-Path $profile.FullName ('AppData\Local\Programs\Python\' + $version + '\python.exe')))
                }
            }
        } catch { Write-Verbose 'optional operation failed' }
        foreach ($tree in @('HKCU:\Software\Python\PythonCore\3.13\InstallPath',
                            'HKLM:\Software\Python\PythonCore\3.13\InstallPath',
                            'HKLM:\Software\WOW6432Node\Python\PythonCore\3.13\InstallPath')) {
            try {
                $value = (Get-ItemProperty -LiteralPath $tree -ErrorAction Stop).'(default)'
                if ($value) { $paths.Add((Join-Path ([string]$value) 'python.exe')) }
            } catch { Write-Verbose 'optional operation failed' }
        }
    }

    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $full = [IO.Path]::GetFullPath($path)
        $probeExit = 1
        $probeOutput = $null
        try {
            $probeOutput = (& $full -c "import sys; print(sys.executable)" 2>$null | Out-String).Trim()
            $probeExit = [int]$LASTEXITCODE
        } catch {
            $probeExit = 1
            $probeOutput = $null
        }
        if ($probeExit -ne 0 -or [string]::IsNullOrWhiteSpace($probeOutput)) { continue }
        $realPath = [IO.Path]::GetFullPath($probeOutput.Trim())
        if (-not (Test-Path -LiteralPath $realPath -PathType Leaf)) { continue }
        if (-not $seen.Add($realPath.ToLowerInvariant())) { continue }

        $version = $null
        try { $version = (& $realPath --version 2>&1 | Out-String).Trim() } catch { $version = $null }
        $versionOk = $false
        $versionTooNew = $false
        $major = $null
        $minor = $null
        if ($version -match 'Python\s+(\d+)\.(\d+)') {
            $major = [int]$Matches[1]
            $minor = [int]$Matches[2]
            $versionTooNew = (($major -gt 3) -or ($major -eq 3 -and $minor -ge 14))
            $versionOk = ($major -eq 3 -and $minor -ge 10 -and $minor -le 13)
        }
        $candidateSource = if ($full -like ((Join-Path ([IO.Path]::GetFullPath($InstallPath)) 'python') + '\*')) { 'bundled' } else { 'system' }
        $candidates.Add([pscustomobject][ordered]@{
            found = $true
            path = $realPath
            candidate_path = $full
            python_source = $candidateSource
            probe_exit = $probeExit
            version = $version
            major = $major
            minor = $minor
            version_ok = [bool]$versionOk
            version_too_new = [bool]$versionTooNew
        })
    }

    return $candidates.ToArray()
}

<#
.SYNOPSIS
    Get-CyberButlerOllamaSnapshot performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerOllamaSnapshot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )

    $paths = New-Object System.Collections.Generic.List[string]
    $command = Get-Command ollama.exe -ErrorAction SilentlyContinue
    if ($command) { $paths.Add([string]$command.Source) }
    if ($env:LOCALAPPDATA) {
        $paths.Add((Join-Path $env:LOCALAPPDATA 'Programs\Ollama\ollama.exe'))
    }
    $paths.Add((Join-Path $InstallPath 'Ollama\ollama.exe'))

    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (Test-Path -LiteralPath $path) {
            return [pscustomobject][ordered]@{
                found = $true
                path = [IO.Path]::GetFullPath($path)
            }
        }
    }
    return [pscustomobject][ordered]@{
        found = $false
        path = $null
    }
}

<#
.SYNOPSIS
    Get-CyberButlerPreflight performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerPreflight {
    [CmdletBinding()]
    param(
        [string]$InstallPath = 'C:\CyberButler',
        [int[]]$Ports = @(6185, 18090, 8765, 11434, 11435),
        [string]$OutputPath = '',
        [string[]]$PythonCandidates = @(),
        $Handlers = @{}
    )

    $warnings = New-Object System.Collections.Generic.List[string]
    $errors = New-Object System.Collections.Generic.List[string]
    $blocking = New-Object System.Collections.Generic.List[object]

    $os = $null
    try { $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop } catch {
        $warnings.Add('Operating system information is unavailable.')
    }

    $hostName = $env:COMPUTERNAME
    $admin = Test-InstallerAdministrator
    if (-not $admin) { $warnings.Add('Preflight is running without administrator rights; write operations will be refused later.') }

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'preflight.python') {
        $python = @(Invoke-CyberButlerHandler -Handlers $Handlers -Name 'preflight.python' -Context ([pscustomobject]@{ InstallPath = $InstallPath }))
    } else {
        $python = @(Get-CyberButlerPythonSnapshot -InstallPath $InstallPath -CandidatePaths $PythonCandidates)
    }
    $bundledCandidates = @($python | Where-Object { $_.version_ok -eq $true -and [string]$_.python_source -eq 'bundled' })
    $systemCandidates = @($python | Where-Object { $_.version_ok -eq $true -and [string]$_.python_source -ne 'bundled' })
    $resolvedPython = if ($bundledCandidates.Count -gt 0) { $bundledCandidates[0] } elseif ($systemCandidates.Count -gt 0) { $systemCandidates[0] } else { $null }
    $pythonUsable = $null -ne $resolvedPython
    $pythonNeedsBundle = -not $pythonUsable
    $pythonSource = if ($resolvedPython) { [string]$resolvedPython.python_source } else { 'bundled' }
    $pythonTargetPath = Join-Path ([IO.Path]::GetFullPath($InstallPath)) 'python\python.exe'
    $pythonResolvedPath = if ($resolvedPython) { [string]$resolvedPython.path } else { $pythonTargetPath }
    $pythonResolvedVersion = if ($resolvedPython) { [string]$resolvedPython.version } else { 'Python 3.13.17 (bundled target)' }
    if ($pythonNeedsBundle) {
        $warnings.Add('No compatible system Python was found; bundled Python 3.13 will be required.')
    }

    $ollama = Get-CyberButlerOllamaSnapshot -InstallPath $InstallPath
    if (-not $ollama.found) { $warnings.Add('Ollama was not found; local-model installation will be unavailable.') }

    $portSnapshot = @(Get-CyberButlerPortSnapshot -Ports $Ports)
    $processSnapshot = Get-CyberButlerProcessSnapshot -PortSnapshot $portSnapshot
    $tasks = Get-CyberButlerScheduledTaskSnapshot
    $defender = Get-CyberButlerDefenderSnapshot

    $longPaths = [ordered]@{
        enabled = $null
        source = 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem\LongPathsEnabled'
        error = $null
    }
    try {
        $value = Get-ItemProperty -LiteralPath 'HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem' -Name 'LongPathsEnabled' -ErrorAction Stop
        $longPaths.enabled = ([int]$value.LongPathsEnabled -eq 1)
    } catch {
        $longPaths.error = $_.Exception.Message
        $warnings.Add('Long path support could not be read from the registry.')
    }

    $existingState = 'None'
    if (Get-Command Get-CyberButlerExistingState -ErrorAction SilentlyContinue) {
        $existingState = Get-CyberButlerExistingState -InstallPath $InstallPath
    }

    $installExists = Test-Path -LiteralPath $InstallPath
    $versionPath = Join-Path $InstallPath 'VERSION'
    $version = if (Test-Path -LiteralPath $versionPath) { (Get-Content -LiteralPath $versionPath -Raw -ErrorAction SilentlyContinue).Trim() } else { $null }

    $data = [ordered]@{
        schema = 1
        generated_at = Get-InstallerUtcTimestamp
        read_only = $true
        host = [ordered]@{
            computer_name = $hostName
            os_caption = if ($os) { [string]$os.Caption } else { $null }
            os_version = if ($os) { [string]$os.Version } else { $null }
            os_build = if ($os) { [string]$os.BuildNumber } else { $null }
            os_architecture = if ($os) { [string]$os.OSArchitecture } else { $null }
        }
        powershell = [ordered]@{
            version = $PSVersionTable.PSVersion.ToString()
            edition = if ($PSVersionTable.PSEdition) { [string]$PSVersionTable.PSEdition } else { 'Desktop' }
            clr = if ($PSVersionTable.CLRVersion) { [string]$PSVersionTable.CLRVersion } else { $null }
        }
        admin = [ordered]@{
            is_admin = [bool]$admin
            identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        }
        install_path = [ordered]@{
            path = [IO.Path]::GetFullPath($InstallPath)
            exists = [bool]$installExists
            version = $version
            existing_state = $existingState
            has_existing_install = ($existingState -in @('Legacy', 'Installed'))
        }
        python = $python
        python_usable = [bool]$pythonUsable
        python_required = '>=3.10,<3.14 (bundled Python 3.13 will be used if system Python is unsupported)'
        python_needs_bundle = [bool]$pythonNeedsBundle
        python_source = $pythonSource
        python_resolved_path = $pythonResolvedPath
        python_resolved_version = $pythonResolvedVersion
        python_target_path = $pythonTargetPath
        blocking = $blocking.ToArray()
        ollama = $ollama
        ports = $portSnapshot
        processes = $processSnapshot
        scheduled_tasks = $tasks
        defender = $defender
        long_paths = [pscustomobject]$longPaths
        warnings = $warnings.ToArray()
        errors = $errors.ToArray()
    }

    $result = [pscustomobject]$data
    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        Write-InstallerJson -Path $OutputPath -Value $result
    }
    return $result
}
