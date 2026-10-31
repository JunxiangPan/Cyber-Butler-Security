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

function Get-CyberButlerTaskPrincipalSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrincipalMode,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = ''
    )
    switch ($PrincipalMode) {
        'SYSTEM' { return [pscustomobject]@{ user_id = 'NT AUTHORITY\SYSTEM'; logon_type = 'ServiceAccount'; run_level = 'Highest' } }
        'service' { return [pscustomobject]@{ user_id = (Resolve-CyberButlerTaskAccount -Account $ServiceAccount); logon_type = 'S4U'; run_level = 'Limited' } }
        default { return [pscustomobject]@{ user_id = (Resolve-CyberButlerTaskAccount -Account $DesktopAccount -CurrentUser:([string]::IsNullOrWhiteSpace($DesktopAccount))); logon_type = 'Interactive'; run_level = 'Limited' } }
    }
}


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
    $python = Join-Path $rootFull 'AstrBot\.venv\Scripts\python.exe'
    $webPython = Join-Path $rootFull 'webui\.venv\Scripts\python.exe'
    return @(
        [pscustomobject]@{ name = 'AstrBot Service'; exe = $python; args = 'main.py'; workdir = (Join-Path $rootFull 'AstrBot'); principal = $(if ($Isolation) { 'service' } else { 'desktop' }); trigger = 'AtLogOn'; port = 6185 },
        [pscustomobject]@{ name = 'AstrBot TOTP Broker'; exe = $python; args = (Join-Path $rootFull 'tools\broker.py'); workdir = (Join-Path $rootFull 'tools'); principal = 'SYSTEM'; trigger = 'AtStartup'; port = 18090 },
        [pscustomobject]@{ name = 'Cyber-Butler Web UI Services'; exe = $webPython; args = 'run.py'; workdir = (Join-Path $rootFull 'webui'); principal = 'desktop'; trigger = 'AtLogOn'; port = 8765 },
        [pscustomobject]@{ name = 'Cyber-Butler OTP Mailer'; exe = $python; args = (Join-Path $rootFull 'tools\email_approval.py'); workdir = (Join-Path $rootFull 'tools'); principal = 'desktop'; trigger = 'AtLogOn'; port = 8766 }
    )
}

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
        $results.Add([pscustomobject][ordered]@{ port = $port; healthy = [bool]$ok })
    }
    return $results.ToArray()
}

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
        $task = Get-ScheduledTask -TaskName $spec.name -ErrorAction SilentlyContinue
        $principal = $null
        if ($task) { try { $principal = [string]$task.Principal.UserId } catch { } }
        $expected = switch ($spec.principal) {
            'SYSTEM' { 'NT AUTHORITY\SYSTEM' }
            'service' { (Resolve-CyberButlerTaskAccount -Account $ServiceAccount) }
            default { (Resolve-CyberButlerTaskAccount -Account $DesktopAccount -CurrentUser:([string]::IsNullOrWhiteSpace($DesktopAccount))) }
        }
        $taskRows.Add([pscustomobject][ordered]@{
            name = $spec.name
            exists = [bool]$task
            state = if ($task) { [string]$task.State } else { $null }
            principal = $principal
            expected_principal = $expected
            principal_ok = ([string]$principal -ieq [string]$expected)
            port = $spec.port
        })
    }
    $result['tasks'] = $taskRows.ToArray()
    $result['ports'] = Test-CyberButlerPortHealth -Ports @($specs | ForEach-Object { [int]$_.port })
    $result['satisfied'] = (@($result['tasks'] | Where-Object { -not ($_.exists -and $_.principal_ok) }).Count -eq 0) -and
        (@($result['ports'] | Where-Object { -not $_.healthy }).Count -eq 0)
    if (-not $result['satisfied']) { $result['reason'] = 'service-task-or-port-not-ready' }
    return [pscustomobject]$result
}

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
        [string]$Trigger = 'AtLogOn'
    )

    $action = New-ScheduledTaskAction -Execute $Exe -Argument $Arguments -WorkingDirectory $WorkingDirectory
    $taskTrigger = if ($Trigger -eq 'AtStartup') { New-ScheduledTaskTrigger -AtStartup } else { New-ScheduledTaskTrigger -AtLogOn -User $DesktopAccount }
    $principalSpec = Get-CyberButlerTaskPrincipalSpec -PrincipalMode $PrincipalMode -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount
    Write-Host ('SERVICE registering ' + $Name + ' as ' + $principalSpec.user_id + ' (' + $principalSpec.logon_type + ')')
    $principal = New-ScheduledTaskPrincipal -UserId $principalSpec.user_id -LogonType $principalSpec.logon_type -RunLevel $principalSpec.run_level
    $settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
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
        } catch { }
    }
    return $ids.ToArray()
}

function Set-CyberButlerServiceTasks {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = '',
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
    $ports = @($specs | ForEach-Object { [int]$_.port })
    $beforePids = @(Get-CyberButlerPortOwnerIds -Ports $ports)
    $created = New-Object System.Collections.Generic.List[object]
    $taskBackups = @{}
    foreach ($spec in $specs) {
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
            -PrincipalMode $spec.principal -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -Trigger $spec.trigger
    }
    Start-Sleep -Seconds 2
    $afterPids = @(Get-CyberButlerPortOwnerIds -Ports $ports)
    $newPids = @($afterPids | Where-Object { $beforePids -notcontains $_ })
    return [pscustomobject]@{ created = $created.ToArray(); started_process_ids = $newPids; task_backups = $taskBackups; started_at = Get-InstallerUtcTimestamp }
}

function Assert-CyberButlerServices {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = '',
        [bool]$Isolation = $false,
        [int]$TimeoutSeconds = 60,
        $Handlers = @{}
    )
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'services.assert') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'services.assert' -Context ([pscustomobject]@{ Root = $Root; ServiceAccount = $ServiceAccount; DesktopAccount = $DesktopAccount }))
    }
    $deadline = (Get-Date).AddSeconds([Math]::Max(1, $TimeoutSeconds))
    do {
        $test = Test-CyberButlerServices -Root $Root -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -Isolation $Isolation -Handlers $Handlers
        if ($test.satisfied) { return $true }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return $false
}

function Undo-CyberButlerServices {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string[]]$CreatedTasks = @(),
        [int[]]$StartedProcessIds = @(),
        [hashtable]$TaskBackups = @{},
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'services.undo') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'services.undo' -Context ([pscustomobject]@{
            Root = $Root; CreatedTasks = $CreatedTasks; StartedProcessIds = $StartedProcessIds
        }))
    }
    foreach ($taskName in @($CreatedTasks)) {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
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
    return [pscustomobject]@{ action = 'removed'; tasks = @($CreatedTasks); processes = @($StartedProcessIds) }
}

function Invoke-CyberButlerServices {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$DesktopAccount = '',
        [bool]$Isolation = $false,
        [string]$JournalStep = 'services',
        $Journal = $null,
        [string]$Approval = '',
        [switch]$NonInteractive,
        [switch]$PlanOnly,
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
        $base.message = 'Would register or update four scheduled tasks and wait for ports.'
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
    try {
        $applied = Set-CyberButlerServiceTasks -Root $Root -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -Isolation $Isolation -Journal $Journal -JournalStep $JournalStep -Handlers $Handlers
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
        $asserted = Assert-CyberButlerServices -Root $Root -ServiceAccount $ServiceAccount -DesktopAccount $DesktopAccount -Isolation $Isolation -Handlers $Handlers
        if (-not $asserted) { throw 'Service assertion failed.' }
        if ($null -ne $Journal) { Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status completed | Out-Null }
        $base.status = 'completed'
        $base.changed = $true
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    } catch {
        $undo = Undo-CyberButlerServices -Root $Root -CreatedTasks $createdTasks -StartedProcessIds $startedPids -TaskBackups $taskBackups -Handlers $Handlers
        $base.status = 'failed'
        $base.message = $_.Exception.Message
        $base.undo = $undo
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ error = $_.Exception.Message; undo = $undo.action }) | Out-Null
        }
        return [pscustomobject]$base
    }
}
