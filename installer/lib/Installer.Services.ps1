# Scheduled-task and service-health lifecycle for the installer.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

function Resolve-CyberButlerTaskAccount {
    param(
        [string]$Account,
        [switch]$CurrentUser
    )
    if ($CurrentUser -or [string]::IsNullOrWhiteSpace($Account)) {
        return [Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
    if ($Account -match '\\') { return $Account }
    if ($Account -ieq 'SYSTEM') { return 'NT AUTHORITY\SYSTEM' }
    if ($Account -ieq $env:USERNAME) { return [Security.Principal.WindowsIdentity]::GetCurrent().Name }
    return ($env:COMPUTERNAME + '\' + $Account)
}

function ConvertTo-CyberButlerCanonicalPrincipal {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '' }
    $n = $Name.Trim()
    if ($n.StartsWith('.')) { $n = $env:COMPUTERNAME + $n.Substring(1) }
    if ($n -notmatch '\\') {
        switch -Regex ($n) {
            '^(?i)SYSTEM$'          { return 'NT AUTHORITY\SYSTEM' }
            '^(?i)LOCAL SERVICE$'   { return 'NT AUTHORITY\LOCAL SERVICE' }
            '^(?i)NETWORK SERVICE$' { return 'NT AUTHORITY\NETWORK SERVICE' }
            default                 { return ($env:COMPUTERNAME + '\' + $n) }
        }
    }
    $parts = $n -split '\\', 2
    if ($parts[0] -ieq $env:COMPUTERNAME) { return ($env:COMPUTERNAME + '\' + $parts[1]) }
    return $n
}

function Get-CyberButlerTaskPrincipalSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrincipalMode,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = ''
    )
    switch ($PrincipalMode) {
        'SYSTEM' { return [pscustomobject]@{ user_id = 'NT AUTHORITY\SYSTEM'; logon_type = 'ServiceAccount'; run_level = 'Highest' } }
        'service' { throw 'S4U scheduled tasks are retired; use the native SCM service CyberButlerAgentRuntime.' }
        default { return [pscustomobject]@{ user_id = (Resolve-CyberButlerTaskAccount -Account $DesktopAccount -CurrentUser:([string]::IsNullOrWhiteSpace($DesktopAccount))); logon_type = 'Interactive'; run_level = 'Limited' } }
    }
}


<#
.SYNOPSIS
    Invoke-CyberButlerBrokerAclHardening performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Invoke-CyberButlerBrokerAclHardening {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$ServiceUser = '',
        [string]$DesktopUser = '',
        $Handlers = @{}
    )
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'services.broker-acl') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'services.broker-acl' -Context ([pscustomobject]@{ Root = $Root }))
    }
    $script = Join-Path $Root 'tools\harden_broker_runtime.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        return [pscustomobject]@{ status = 'skipped'; reason = 'harden_broker_runtime.ps1 missing' }
    }
    if ([string]::IsNullOrWhiteSpace($ServiceUser)) { $ServiceUser = $DesktopUser }
    if ([string]::IsNullOrWhiteSpace($ServiceUser)) { throw 'Broker ACL hardening needs a service or desktop user' }
    $output = & pwsh.exe -NoProfile -ExecutionPolicy Bypass -File $script -ServiceUser $ServiceUser -DesktopUser $DesktopUser 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ('Broker ACL hardening failed: ' + (($output | ForEach-Object { [string]$_ }) -join ' '))
    }
    return [pscustomobject]@{ status = 'completed'; output = (($output | ForEach-Object { [string]$_ }) -join "`n") }
}

<#
.SYNOPSIS
    Get-CyberButlerServiceSpecs performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerServiceSpecs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = '',
        [bool]$Isolation = $false
    )

    $rootFull = [IO.Path]::GetFullPath($Root)
    if (-not $DesktopAccount) { $DesktopAccount = [Security.Principal.WindowsIdentity]::GetCurrent().Name }
    $python = Join-Path $rootFull 'python\python.exe'
    $pythonw = $python
    $webPython = $python
    $webPythonw = Join-Path $rootFull 'python\pythonw.exe'
    if (-not (Test-Path -LiteralPath $webPythonw)) { $webPythonw = $webPython }
    $launcher = Join-Path $rootFull 'tools\CyberButlerLauncher.exe'
    $webLog = Join-Path $rootFull 'webui\data\webui-service.log'

    # The wrapper supplies a known one-time AgentRuntime dashboard password and
    # lets us display it in the post-install window. It still starts main.py
    # from the AgentRuntime directory with the same interpreter.
    # Prefer the direct Python entry point. The previous PowerShell wrapper
    # was an unverified failure path (AgentRuntime exit 0x2) and is not required for
    # the known password now written into cmd_config.json by the installer.
    # A visible console can appear when Task Scheduler starts python.exe.
    # Start python.exe through the hidden launcher; stdout/stderr are redirected
    # so AgentRuntime's startup logs and initial credentials are preserved.
    $agentruntimeArgs = ('--exe "pwsh.exe" --workdir "{0}" --args "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"run-python-hidden.ps1\" -Python \"{1}\" -Script \"main.py\" -WorkDir \"{2}\" -StdOut \"{3}\" -StdErr \"{4}\"" --hidden --wait --log "{5}"' -f (Join-Path $rootFull 'tools'), $python, (Join-Path $rootFull 'AgentRuntime'), $agentruntimeOutLog, $agentruntimeErrLog, $agentruntimeLog)
    # Launch the wrapper, not bare run.py: the wrapper starts both WebUI
    # (8765) and OTP Mailer (8766). The previous task never started 8766,
    # so WebUI login always failed with "verification mail failed".
    $webArgs = '--exe "pwsh.exe" --workdir "' + (Join-Path $rootFull 'webui') + '" --args "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"start-services.ps1\"" --hidden --wait --log "' + $webLog + '"'

    return @(
        [pscustomobject]@{ name = 'Cyber-Butler Broker'; kind = 'service'; exe = $launcher; args = ('--exe "{0}" --workdir "{1}" --args "broker.py" --hidden --wait --log "{2}"' -f $python, (Join-Path $rootFull 'tools'), (Join-Path $rootFull 'tools/logs/broker-startup.log')); workdir = (Join-Path $rootFull 'tools'); principal = 'SYSTEM'; trigger = 'AtStartup'; port = 18090 },
        [pscustomobject]@{ name = 'Cyber-Butler WFP Guard'; exe = $launcher; args = ('--exe "{0}" --workdir "{1}" --args "wfp_guard.py --watch --policy {2}" --hidden --wait --log "{3}"' -f $webPython, (Join-Path $rootFull 'tools'), (Join-Path $rootFull 'webui/data/network-policy.json'), (Join-Path $rootFull 'tools/logs/wfp-startup.log')); workdir = (Join-Path $rootFull 'tools'); principal = 'SYSTEM'; trigger = 'AtStartup'; port = 0 },
        [pscustomobject]@{ name = 'Cyber-Butler Web UI Services'; exe = $launcher; args = $webArgs; workdir = (Join-Path $rootFull 'webui'); principal = 'desktop'; trigger = 'AtLogOn'; port = 8765 },
        [pscustomobject]@{ name = 'Cyber-Butler OTP Mailer'; exe = $webPythonw; args = 'otp_mailer.py'; workdir = (Join-Path $rootFull 'webui'); principal = 'desktop'; trigger = 'AtLogOn'; port = 8766 },
        [pscustomobject]@{
            name = 'Game Mode Startup'
            exe = $launcher
            args = ('--exe "pwsh.exe" --workdir "{0}" --args "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File \"{1}\"" --hidden --wait' -f (Join-Path $rootFull 'tools'), (Join-Path $rootFull 'tools/start-game-mode.ps1'))
            workdir = (Join-Path $rootFull 'tools')
            principal = 'desktop'
            trigger = 'AtLogOn'
            port = 0
        }
    )
}

<#
.SYNOPSIS
    Test-CyberButlerPortHealth performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Test-CyberButlerPortHealth {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$Ports,
        [int]$TimeoutMilliseconds = 350
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($port in $Ports) {
        $client = New-Object System.Net.Sockets.TcpClient
        $ok = $false
        try {
            $async = $client.BeginConnect('127.0.0.1', $port, $null, $null)
            $ok = $async.AsyncWaitHandle.WaitOne($TimeoutMilliseconds, $false) -and $client.Connected
        } catch { $ok = $false } finally { $client.Close() }
        $listener = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | Select-Object -First 1)
        $ownerPid = if ($listener.Count -gt 0) { [int]$listener[0].OwningProcess } else { $null }
        $results.Add([pscustomobject][ordered]@{ port = $port; healthy = [bool]$ok; listening = [bool]($listener.Count -gt 0); owner_pid = $ownerPid })
    }
    return $results.ToArray()
}

<#
.SYNOPSIS
    Test-CyberButlerServices performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Test-CyberButlerServices {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = '',
        [bool]$Isolation = $false,
        $Handlers = @{}
    )

    $context = [pscustomobject]@{ Root = $Root; ServiceAccount = $ServiceAccount; DesktopAccount = $DesktopAccount; Isolation = $Isolation }
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'services.test') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'services.test' -Context $context)
    }

    $result = [ordered]@{
        supported = $null -ne (Get-Command Get-ScheduledTask -ErrorAction SilentlyContinue)
        can_manage = [bool](Test-InstallerAdministrator)
        tasks = @()
        ports = @()
        satisfied = $false
        reason = ''
    }
    if (-not $result.supported) {
        $result.reason = 'scheduled-task-module-unavailable'
        return [pscustomobject]$result
    }

    $specs = Get-CyberButlerServiceSpecs -Root $Root -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -Isolation $Isolation
    $taskRows = New-Object System.Collections.Generic.List[object]
    foreach ($spec in $specs) {
        if ([string]$spec.kind -eq 'service') {
            $svc = Get-Service -Name $spec.name -ErrorAction SilentlyContinue
            $taskRows.Add([pscustomobject][ordered]@{
                name = $spec.name
                exists = [bool]$svc
                state = if ($svc) { [string]$svc.Status } else { $null }
                principal = 'NT AUTHORITY\SYSTEM'
                expected_principal = 'NT AUTHORITY\SYSTEM'
                principal_ok = $true
                port = $spec.port
                action_execute = if ($svc) { 'native-service' } else { $null }
                action_arguments = $null
                action_workdir = $null
                last_task_result = $null
            })
            continue
        }
        $task = Get-ScheduledTask -TaskName $spec.name -ErrorAction SilentlyContinue
        $principal = $null
        if ($task) { try { $principal = [string]$task.Principal.UserId } catch { Write-Verbose 'optional operation failed' } }
        $expected = switch ($spec.principal) {
            'SYSTEM' { 'NT AUTHORITY\SYSTEM' }
            'service' { (Resolve-CyberButlerTaskAccount -Account $ServiceAccount) }
            default { (Resolve-CyberButlerTaskAccount -Account $DesktopAccount -CurrentUser:([string]::IsNullOrWhiteSpace($DesktopAccount))) }
        }
        $action = if ($task -and @($task.Actions).Count -gt 0) { $task.Actions[0] } else { $null }
        $lastTaskResult = $null
        if ($task) {
            try { $lastTaskResult = ('0x{0:X8}' -f [uint32](Get-ScheduledTaskInfo -TaskName $spec.name).LastTaskResult) } catch { $lastTaskResult = 'unknown' }
        }
        $taskRows.Add([pscustomobject][ordered]@{
            name = $spec.name
            exists = [bool]$task
            state = if ($task) { [string]$task.State } else { $null }
            principal = $principal
            expected_principal = $expected
            principal_ok = ((ConvertTo-CyberButlerCanonicalPrincipal $principal) -ieq (ConvertTo-CyberButlerCanonicalPrincipal $expected))
            port = $spec.port
            action_execute = if ($action) { [string]$action.Execute } else { $null }
            action_arguments = if ($action) { [string]$action.Arguments } else { $null }
            action_workdir = if ($action) { [string]$action.WorkingDirectory } else { $null }
            last_task_result = $lastTaskResult
        })
    }
    $result['tasks'] = $taskRows.ToArray()
    $result['ports'] = Test-CyberButlerPortHealth -Ports @($specs | Where-Object { [int]$_.port -gt 0 } | ForEach-Object { [int]$_.port })
    $result['satisfied'] = (@($result['tasks'] | Where-Object { -not ($_.exists -and $_.principal_ok) }).Count -eq 0) -and
        (@($result['ports'] | Where-Object { -not $_.healthy }).Count -eq 0)
    if (-not $result['satisfied']) { $result['reason'] = 'service-task-or-port-not-ready' }
    $reasons = New-Object System.Collections.Generic.List[string]
    foreach ($row in @($result['tasks'])) {
        if (-not $row.exists) { $reasons.Add($row.name + ': task missing') }
        elseif (-not $row.principal_ok) { $reasons.Add($row.name + ': principal mismatch') }
    }
    foreach ($row in @($result['ports'])) {
        if (-not $row.healthy) { $reasons.Add('port ' + $row.port + ' not listening') }
    }
    $result['reasons'] = $reasons.ToArray()
    return [pscustomobject]$result
}

<#
.SYNOPSIS
    New-CyberButlerScheduledTask performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
<#
.SYNOPSIS
    New-CyberButlerNativeService registers the SYSTEM broker as a real SCM service.
.DESCRIPTION
    Uses New-Service -ErrorAction Stop and start-broker.bat, which sets cwd and
    PYTHONPATH explicitly. Registration or startup failures are thrown.
#>
function New-CyberButlerNativeService {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$BatPath
    )
    if (-not (Get-Command New-Service -ErrorAction SilentlyContinue)) { throw 'New-Service is unavailable.' }
    if (-not (Test-Path -LiteralPath $BatPath -PathType Leaf)) { throw ('Broker wrapper missing: ' + $BatPath) }
    $cmd = Join-Path $env:SystemRoot 'System32\cmd.exe'
    if (-not (Test-Path -LiteralPath $cmd)) { throw ('cmd.exe missing: ' + $cmd) }
    $binary = '"' + $cmd + '" /c "' + $BatPath + '"'
    $existing = Get-Service -Name $Name -ErrorAction SilentlyContinue
    if ($existing) {
        try { Stop-Service -Name $Name -Force -ErrorAction Stop } catch {
            Write-Host ('SERVICE warning stopping existing ' + $Name + ': ' + $_.Exception.Message)
        }
        $delete = & sc.exe delete $Name 2>&1
        if ($LASTEXITCODE -ne 0) { throw ('sc.exe delete failed for ' + $Name + ': ' + ($delete -join ' ')) }
        Start-Sleep -Seconds 1
    }
    try {
        New-Service -Name $Name -BinaryPathName $binary -DisplayName $Name -Description 'Cyber-Butler Broker (SYSTEM)' -StartupType Automatic -ErrorAction Stop | Out-Null
        Write-Host ('SERVICE registered native service ' + $Name)
        Start-Service -Name $Name -ErrorAction Stop
        Write-Host ('SERVICE started native service ' + $Name)
    } catch {
        $message = 'Native service registration/start failed for ' + $Name + ': ' + $_.Exception.Message
        Write-Host $message
        throw $message
    }
}

<#
.SYNOPSIS
    New-CyberButlerScheduledTask registers a scheduled task for a desktop or
    legacy service entry.
.DESCRIPTION
    Registration and Start failures are thrown with the task name and principal.
#>
function New-CyberButlerScheduledTask {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [Parameter(Mandatory = $true)]
        [string]$Exe,
        [Parameter(Mandatory = $true)]
        [string]$Arguments,
        [Parameter(Mandatory = $true)]
        [string]$WorkingDirectory,
        [Parameter(Mandatory = $true)]
        [string]$PrincipalMode,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = '',
        [string]$ServiceAccountPassword = '',
        [string]$Trigger = 'AtLogOn'
    )

    $action = New-ScheduledTaskAction -Execute $Exe -Argument $Arguments -WorkingDirectory $WorkingDirectory
    $taskTrigger = if ($Trigger -eq 'AtStartup') { New-ScheduledTaskTrigger -AtStartup } else { New-ScheduledTaskTrigger -AtLogOn -User $DesktopAccount }
    $principalSpec = Get-CyberButlerTaskPrincipalSpec -PrincipalMode $PrincipalMode -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount
    Write-Host ('SERVICE registering ' + $Name + ' as ' + $principalSpec.user_id + ' (' + $principalSpec.logon_type + ')')
    $principal = New-ScheduledTaskPrincipal -UserId $principalSpec.user_id -LogonType $principalSpec.logon_type -RunLevel $principalSpec.run_level
    $settings = New-ScheduledTaskSettingsSet -Hidden -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    try {
        Register-ScheduledTask -TaskName $Name -Action $action -Trigger $taskTrigger -Principal $principal -Settings $settings -Force | Out-Null
    } catch {
        throw ('Register-ScheduledTask failed for ' + $Name + ' (UserId=' + $principalSpec.user_id + ', LogonType=' + $principalSpec.logon_type + '): ' + $_.Exception.Message)
    }
    try {
        Start-ScheduledTask -TaskName $Name
    } catch {
        throw ('Start-ScheduledTask failed for ' + $Name + ' (UserId=' + $principalSpec.user_id + '): ' + $_.Exception.Message)
    }
}


function Get-CyberButlerPortOwnerIds {
    param([int[]]$Ports)
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { return @() }
    $ids = New-Object System.Collections.Generic.List[int]
    foreach ($port in $Ports) {
        try {
            foreach ($connection in @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)) {
                if ($connection.OwningProcess -and -not $ids.Contains([int]$connection.OwningProcess)) {
                    $ids.Add([int]$connection.OwningProcess)
                }
            }
        } catch { Write-Verbose 'optional operation failed' }
    }
    return $ids.ToArray()
}

<#
.SYNOPSIS
    Get-CyberButlerInstallPortOwnerIds performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerInstallPortOwnerIds {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [int[]]$Ports = @(6185, 18090, 8765, 8766)
    )
    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('')
    $ids = New-Object System.Collections.Generic.List[int]
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) { return @() }
    foreach ($port in @($Ports)) {
        try {
            foreach ($connection in @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue)) {
                $ownerId = [int]$connection.OwningProcess
                if ($ownerId -le 0 -or $ids.Contains($ownerId)) { continue }
                $proc = Get-CimInstance Win32_Process -Filter ("ProcessId=" + $ownerId) -ErrorAction SilentlyContinue
                if (-not $proc -or -not $proc.CommandLine) { continue }
                if (([string]$proc.CommandLine).IndexOf($rootFull, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    $ids.Add($ownerId)
                }
            }
        } catch { Write-Verbose 'optional operation failed' }
    }
    return $ids.ToArray()
}

function Stop-CyberButlerInstallProcesses {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [int[]]$Ports = @(6185, 18090, 8765, 8766)
    )
    $stopped = New-Object System.Collections.Generic.List[int]
    foreach ($processId in @(Get-CyberButlerInstallPortOwnerIds -Root $Root -Ports $Ports)) {
        try {
            Stop-Process -Id $processId -Force -ErrorAction Stop
            $stopped.Add([int]$processId)
        } catch { Write-Verbose 'optional operation failed' }
    }
    return $stopped.ToArray()
}

<#
.SYNOPSIS
    Set-CyberButlerServiceTasks performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Set-CyberButlerServiceTasks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = '',
        [string]$ServiceAccountPassword = '',
        [bool]$Isolation = $false,
        [string]$JournalStep = 'services',
        $Journal = $null,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'services.apply') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'services.apply' -Context ([pscustomobject]@{
            Root = $Root; ServiceAccount = $ServiceAccount; DesktopAccount = $DesktopAccount; Journal = $Journal; JournalStep = $JournalStep
        }))
    }

    $specs = Get-CyberButlerServiceSpecs -Root $Root -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -Isolation $Isolation
    if (@($specs | Where-Object { $_.principal -eq 'service' }).Count -gt 0) {
        # Task Scheduler must be reachable before registering a service task.
        # Restart-Service on a protected Schedule service produced a misleading
        # warning and did not ensure it was running; use a controlled check.
        $scheduleService = Get-Service -Name Schedule -ErrorAction SilentlyContinue
        if (-not $scheduleService) {
            throw 'Task Scheduler service (Schedule) was not found; services cannot be installed.'
        }
        if ($scheduleService.Status -ne 'Running') {
            try {
                Start-Service -Name Schedule -ErrorAction Stop
                $scheduleService.WaitForStatus('Running', [TimeSpan]::FromSeconds(10))
            } catch {
                throw ('Task Scheduler service (Schedule) is not running and could not be started: ' + $_.Exception.Message)
            }
        }
    }
    # Stale listeners from an older install can keep 6185/18090 owned while
    # Task Scheduler launches a second tree. Stop only processes whose command
    # line points at this install root.
    $stoppedBeforeApply = @(Stop-CyberButlerInstallProcesses -Root $Root -Ports $ports)
    if ($stoppedBeforeApply.Count -gt 0) {
        Write-Host ('SERVICE stopped stale listeners: ' + ($stoppedBeforeApply -join ', '))
        Start-Sleep -Seconds 2
    }
    $beforePids = @(Get-CyberButlerPortOwnerIds -Ports $ports)
    $created = New-Object System.Collections.Generic.List[object]
    $taskBackups = @{}
    foreach ($spec in $specs) {
        if ([string]$spec.kind -eq 'service') {
            $batPath = Join-Path ([IO.Path]::GetFullPath($Root)) 'start-broker.bat'
            New-CyberButlerNativeService -Name $spec.name -BatPath $batPath
            $created.Add($spec.name)
            continue
        }
        $existing = Get-ScheduledTask -TaskName $spec.name -ErrorAction SilentlyContinue
        if ($existing) {
            if ($null -ne $Journal) {
                $backup = Backup-CyberButlerScheduledTask -Journal $Journal -Step $JournalStep -TaskName $spec.name
                $taskBackups[$spec.name] = $backup
                Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                    type = 'restore-scheduled-task'
                    task_name = $spec.name
                    backup = [IO.Path]::GetFullPath($backup)
                })
            }
        } else {
            $created.Add($spec.name)
            if ($null -ne $Journal) {
                Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                    type = 'delete-created-scheduled-task'
                    task_name = $spec.name
                })
            }
        }
        New-CyberButlerScheduledTask -Name $spec.name -Exe $spec.exe -Arguments $spec.args -WorkingDirectory $spec.workdir `
            -PrincipalMode $spec.principal -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -ServiceAccountPassword $ServiceAccountPassword -Trigger $spec.trigger
    }
    Start-Sleep -Seconds 2
    $afterPids = @(Get-CyberButlerPortOwnerIds -Ports $ports)
    $newPids = @($afterPids | Where-Object { $beforePids -notcontains $_ })
    return [pscustomobject]@{ created = $created.ToArray(); started_process_ids = $newPids; task_backups = $taskBackups; started_at = Get-InstallerUtcTimestamp }
}

<#
.SYNOPSIS
    Save-CyberButlerServicesDiagnostics performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Save-CyberButlerServicesDiagnostics {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [string]$SnapshotRoot = '',
        $Assertion = $null
    )
    if ([string]::IsNullOrWhiteSpace($SnapshotRoot)) {
        $programData = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
        $SnapshotRoot = Join-Path $programData 'CyberButler\installer\diagnostics'
    }
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dir = Join-Path $SnapshotRoot ('services-' + $stamp)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $taskDir = Join-Path $dir 'tasks'
    $portDir = Join-Path $dir 'ports'
    $logDir = Join-Path $dir 'logs'
    New-Item -ItemType Directory -Path $taskDir, $portDir, $logDir -Force | Out-Null

    $taskNames = @('Cyber-Butler Broker','Cyber-Butler Web UI Services','Cyber-Butler OTP Mailer','Cyber-Butler WFP Guard')
    $info = New-Object System.Collections.Generic.List[string]
    foreach ($name in $taskNames) {
        $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if ($task) {
            try {
                Export-ScheduledTask -TaskName $name | Out-File -LiteralPath (Join-Path $taskDir ($name + '.xml')) -Encoding utf8
            } catch {
                ('EXPORT_FAILED: ' + $_.Exception.Message) | Out-File -LiteralPath (Join-Path $taskDir ($name + '.export-error.txt')) -Encoding utf8
            }
            try {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $name
                $info.Add(('## ' + $name))
                $info.Add(($taskInfo | Format-List * | Out-String))
            } catch {
                ('TASKINFO_FAILED: ' + $_.Exception.Message) | Out-File -LiteralPath (Join-Path $taskDir ($name + '.taskinfo-error.txt')) -Encoding utf8
            }
        } else {
            'task-missing' | Out-File -LiteralPath (Join-Path $taskDir ($name + '.missing.txt')) -Encoding utf8
        }
    }
    $info -join "`n" | Out-File -LiteralPath (Join-Path $taskDir 'task-info.txt') -Encoding utf8

    foreach ($port in @(6185, 18090, 8765, 8766)) {
        try {
            $connections = @(Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue)
            if ($connections.Count -eq 0) { 'no listener' | Out-File -LiteralPath (Join-Path $portDir ($port.ToString() + '.txt')) -Encoding utf8 }
            else { $connections | Format-List * | Out-File -LiteralPath (Join-Path $portDir ($port.ToString() + '.txt')) -Encoding utf8 }
        } catch {
            ('PORT_QUERY_FAILED: ' + $_.Exception.Message) | Out-File -LiteralPath (Join-Path $portDir ($port.ToString() + '.txt')) -Encoding utf8
        }
    }

    $logPaths = [ordered]@{
        'broker' = Join-Path $Root 'tools\totp_broker.log'
        'webui-startup' = Join-Path $Root 'webui\data\webui-startup.log'
        'webui-out' = Join-Path $Root 'webui\data\webui.out.log'
        'webui-err' = Join-Path $Root 'webui\data\webui.err.log'
        'otp-mailer-out' = Join-Path $Root 'webui\data\otp_mailer.out.log'
        'otp-mailer-err' = Join-Path $Root 'webui\data\otp_mailer.err.log'
    }
    foreach ($key in $logPaths.Keys) {
        $path = [string]$logPaths[$key]
        $out = Join-Path $logDir ($key + '.tail.txt')
        if (Test-Path -LiteralPath $path) {
            Get-Content -LiteralPath $path -Tail 50 -ErrorAction SilentlyContinue | Out-File -LiteralPath $out -Encoding utf8
        } else {
            ([string]$path + ' MISSING') | Out-File -LiteralPath $out -Encoding utf8
        }
    }
    if ($null -ne $Assertion) {
        $Assertion | ConvertTo-Json -Depth 8 | Out-File -LiteralPath (Join-Path $dir 'assertion.json') -Encoding utf8
    }
    $programDataPath = if ($env:ProgramData) { $env:ProgramData } else { 'C:\ProgramData' }
    $emailPath = Join-Path $programDataPath 'CyberButler\email_secret.json'
    $emailState = if (Test-Path -LiteralPath $emailPath) { 'EXISTS' } else { 'MISSING' }
    $emailState | Out-File -LiteralPath (Join-Path $dir 'email-secret.exists.txt') -Encoding utf8
    return $dir
}

<#
.SYNOPSIS
    Format-CyberButlerServiceAssertion performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Format-CyberButlerServiceAssertion {
    param($Assertion)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Service assertion failed:')
    $seenPorts = New-Object System.Collections.Generic.List[int]
    foreach ($task in @($Assertion.tasks)) {
        $parts = New-Object System.Collections.Generic.List[string]
        if (-not $task.exists) {
            $parts.Add('task missing')
        } elseif (-not $task.principal_ok) {
            $parts.Add('principal mismatch')
        } elseif ([string]$task.state -eq 'Ready' -and [string]$task.last_task_result -eq '0x00000000' -and [string]$task.name -ne 'AuxRuntimeApplication Startup') {
            $parts.Add('task exited immediately')
        } elseif ([string]$task.state -eq 'Ready' -and [string]$task.last_task_result -eq '0x00041301') {
            $parts.Add('task is running (LastTaskResult=0x00041301)')
        } elseif ([string]$task.last_task_result -and [string]$task.last_task_result -ne '0x00000000' -and [string]$task.last_task_result -ne '0x00041301') {
            $parts.Add('LastTaskResult=' + [string]$task.last_task_result)
        } elseif ([string]$task.state) {
            $parts.Add('State=' + [string]$task.state + ', LastTaskResult=' + [string]$task.last_task_result)
        }
        $portRow = @($Assertion.ports | Where-Object { [int]$_.port -eq [int]$task.port } | Select-Object -First 1)
        if ($portRow.Count -gt 0) {
            $seenPorts.Add([int]$task.port)
            if (-not $portRow[0].listening -and -not $portRow[0].healthy) { $parts.Add('port ' + [int]$task.port + ' not listening') }
        }
        if ($parts.Count -gt 0) { $lines.Add('- ' + [string]$task.name + ': ' + ($parts -join ', ')) }
    }
    foreach ($portRow in @($Assertion.ports)) {
        if ($seenPorts -contains [int]$portRow.port) { continue }
        if (-not $portRow.listening -and -not $portRow.healthy) { $lines.Add('- port ' + [int]$portRow.port + ' not listening') }
    }
    return ($lines -join "`n")
}

<#
.SYNOPSIS
    Assert-CyberButlerServices performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Assert-CyberButlerServices {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = '',
        [bool]$Isolation = $false,
        [int]$TimeoutSeconds = 60,
        [string]$PersonalPluginsPath = '',
        [int]$StartupTimeoutSeconds = 120,
        $Handlers = @{}
    )
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'services.assert') {
        $handlerResult = Invoke-CyberButlerHandler -Handlers $Handlers -Name 'services.assert' -Context ([pscustomobject]@{ Root = $Root; ServiceAccount = $ServiceAccount; DesktopAccount = $DesktopAccount })
        if ($handlerResult -is [bool]) {
            return [pscustomobject]@{ satisfied = [bool]$handlerResult; elapsed_seconds = 0; attempts = 1; tasks = @(); ports = @(); reasons = if ($handlerResult) { @() } else { @('handler returned false') } }
        }
        return $handlerResult
    }
    $started = Get-Date
    $deadline = $started.AddSeconds([Math]::Max(1, $TimeoutSeconds))
    $attempts = 0
    $last = $null
    do {
        $attempts++
        $last = Test-CyberButlerServices -Root $Root -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -Isolation $Isolation -Handlers $Handlers
        if ($last.satisfied) {
            return [pscustomobject]@{
                satisfied = $true
                elapsed_seconds = [int]((Get-Date) - $started).TotalSeconds
                attempts = $attempts
                tasks = @($last.tasks)
                ports = @($last.ports)
                reasons = @()
            }
        }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return [pscustomobject]@{
        satisfied = $false
        elapsed_seconds = [int]((Get-Date) - $started).TotalSeconds
        attempts = $attempts
        tasks = if ($last) { @($last.tasks) } else { @() }
        ports = if ($last) { @($last.ports) } else { @() }
        reasons = if ($last -and $last.reasons) { @($last.reasons) } else { @('service task or port not ready') }
    }
}


<#
.SYNOPSIS
    Undo-CyberButlerServices performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Undo-CyberButlerServices {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string[]]$CreatedTasks = @(),
        [int[]]$StartedProcessIds = @(),
        [hashtable]$TaskBackups = @{},
        [switch]$KeepTaskDefinitions,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'services.undo') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'services.undo' -Context ([pscustomobject]@{
            Root = $Root; CreatedTasks = $CreatedTasks; StartedProcessIds = $StartedProcessIds
        }))
    }
    foreach ($taskName in @($CreatedTasks)) {
        # Service assertion failures must preserve AgentRuntime Service in Task
        # Scheduler: deleting it makes diagnosis impossible and forces a full
        # reinstall. Stop processes/ports instead; keep the task definition.
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    $stoppedByPort = @(Stop-CyberButlerInstallProcesses -Root $Root)
    foreach ($taskName in @($TaskBackups.Keys)) {
        $backup = $TaskBackups[$taskName]
        if ($backup -and (Test-Path -LiteralPath $backup)) {
            $xml = Get-Content -LiteralPath $backup -Raw -Encoding UTF8
            Register-ScheduledTask -TaskName $taskName -Xml $xml -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    foreach ($processId in @($StartedProcessIds)) {
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
        if ($process) { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue }
    }
    return [pscustomobject]@{ action = 'removed'; tasks = @($CreatedTasks); processes = @($StartedProcessIds); port_processes = @($stoppedByPort) }
}

<#
.SYNOPSIS
    Invoke-CyberButlerServices performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Invoke-CyberButlerServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = '',
        [string]$ServiceAccountPassword = '',
        [bool]$Isolation = $false,
        [string]$JournalStep = 'services',
        $Journal = $null,
        [string]$Approval = '',
        [switch]$NonInteractive,
        [switch]$PlanOnly,
        [string]$PersonalPluginsPath = '',
        [int]$StartupTimeoutSeconds = 120,
        $Handlers = @{}
    )

    $test = Test-CyberButlerServices -Root $Root -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -Isolation $Isolation -Handlers $Handlers
    $base = [ordered]@{ module = 'services'; step = $JournalStep; root = $Root; test = $test; changed = $false }
    if ($test.satisfied) {
        $base.status = 'skipped'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if (-not $test.supported) {
        $base.status = 'unsupported'
        $base.message = 'Scheduled-task cmdlets are unavailable; register services manually.'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if (-not $test.can_manage) {
        $base.status = 'needs_elevation'
        $base.message = 'Service task registration requires administrator rights.'
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        return [pscustomobject]$base
    }

    $approvalState = Get-CyberButlerApprovalState -Required 'APPROVE SERVICES' -Approval $Approval -NonInteractive:$NonInteractive -PlanOnly:$PlanOnly
    if ($approvalState -eq 'plan') {
        $base.status = 'plan'
        $base.message = 'Would register or update three scheduled tasks and wait for ports.'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if ($approvalState -ne 'approved') {
        $base.status = 'needs_approval'
        $base.exit_code = Get-InstallerExitCode -Name NeedsApproval
        return [pscustomobject]$base
    }

    if ($null -ne $Journal) {
        Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status in_progress | Out-Null
    }
    $createdTasks = @()
    $startedPids = @()
    $taskBackups = @{}
    $serviceAssertion = $null
    $diagnosticsPath = $null
    try {
        $applied = Set-CyberButlerServiceTasks -Root $Root -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -ServiceAccountPassword $ServiceAccountPassword -Isolation $Isolation -Journal $Journal -JournalStep $JournalStep -Handlers $Handlers
        $createdTasks = @($applied.created)
        $startedPids = @($applied.started_process_ids | Where-Object { $_ })
        if ($applied.task_backups) { $taskBackups = $applied.task_backups }
        foreach ($processId in $startedPids) {
            if ($null -ne $Journal) {
                Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                    type = 'stop-created-process'
                    process_id = [int]$processId
                    expected_name = ''
                })
            }
        }
        $asserted = Assert-CyberButlerServices -Root $Root -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -Isolation $Isolation -PersonalPluginsPath $PersonalPluginsPath -TimeoutSeconds $StartupTimeoutSeconds -StartupTimeoutSeconds $StartupTimeoutSeconds -Handlers $Handlers
        if (-not $asserted.satisfied) {
            $serviceAssertion = $asserted
            try {
                $diagnosticsPath = Save-CyberButlerServicesDiagnostics -Root $Root -Assertion $asserted
            } catch {
                Write-Warning ('Service diagnostics snapshot failed: ' + $_.Exception.Message)
                $diagnosticsPath = $null
            }
            throw (Format-CyberButlerServiceAssertion -Assertion $asserted)
        }
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status completed -Details ([pscustomobject]@{
            }) | Out-Null
        }
        $base.status = 'completed'
        $base.changed = $true
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    } catch {
        $undo = Undo-CyberButlerServices -Root $Root -CreatedTasks $createdTasks -StartedProcessIds $startedPids -TaskBackups $taskBackups -KeepTaskDefinitions -Handlers $Handlers
        $base.status = 'failed'
        $base.message = $_.Exception.Message
        $base.undo = $undo
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        $base.service_assertion = $serviceAssertion
        $base.diagnostics_path = $diagnosticsPath
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{
                error = $_.Exception.Message
                undo = $undo.action
                assertion = $serviceAssertion
                diagnostics_path = $diagnosticsPath
            }) | Out-Null
        }
        return [pscustomobject]$base
    }
}
