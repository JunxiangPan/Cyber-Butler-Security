# State journal, backups, and reverse actions for the Cyber-Butler installer.
# Dot-source Installer.Common.ps1 before this file.

function Save-CyberButlerJournal {
    param(
        [Parameter(Mandatory = $true)]
        $Journal
    )

    $Journal.State.updated_at = Get-InstallerUtcTimestamp
    Write-InstallerJson -Path $Journal.StatePath -Value $Journal.State
}

<#
.SYNOPSIS
    New-CyberButlerJournal performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function New-CyberButlerJournal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [Parameter(Mandatory = $true)]
        [string]$Tier,
        [bool]$Isolation = $false,
        [string]$RunId = ''
    )

    if ([string]::IsNullOrWhiteSpace($RunId)) { $RunId = New-InstallerRunId }
    $runRoot = Join-Path ([IO.Path]::GetFullPath($Root)) $RunId
    $backupRoot = Join-Path $runRoot 'backups'
    New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null

    $state = [ordered]@{
        schema = 1
        run_id = $RunId
        created_at = Get-InstallerUtcTimestamp
        updated_at = Get-InstallerUtcTimestamp
        tier = $Tier
        isolation = [bool]$Isolation
        install_path = [IO.Path]::GetFullPath($InstallPath)
        status = 'running'
        current_step = $null
        steps = @()
    }

    $journal = [pscustomobject]@{
        RunId = $RunId
        Root = [IO.Path]::GetFullPath($Root)
        RunRoot = $runRoot
        StatePath = (Join-Path $runRoot 'state.json')
        BackupRoot = $backupRoot
        State = [pscustomobject]$state
    }
    Save-CyberButlerJournal -Journal $journal
    return $journal
}

<#
.SYNOPSIS
    Read-CyberButlerJournal performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Read-CyberButlerJournal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$StatePath
    )

    $statePath = [IO.Path]::GetFullPath($StatePath)
    if (-not (Test-Path -LiteralPath $statePath)) {
        throw "Journal state not found: $statePath"
    }
    $runRoot = Split-Path -Parent $statePath
    $root = Split-Path -Parent $runRoot
    return [pscustomobject]@{
        RunId = (Split-Path -Leaf $runRoot)
        Root = $root
        RunRoot = $runRoot
        StatePath = $statePath
        BackupRoot = (Join-Path $runRoot 'backups')
        State = (Read-InstallerJson -Path $statePath)
    }
}

function Get-CyberButlerJournalStep {
    param(
        [Parameter(Mandatory = $true)]
        $Journal,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    foreach ($step in @($Journal.State.steps)) {
        if ([string]$step.name -eq $Name) { return $step }
    }
    return $null
}

<#
.SYNOPSIS
    Add-CyberButlerJournalStep performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Add-CyberButlerJournalStep {
    param(
        [Parameter(Mandatory = $true)]
        $Journal,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [ValidateSet('pending', 'in_progress', 'completed', 'failed', 'skipped', 'rolled_back')]
        [string]$Status = 'pending',
        [object[]]$ReverseActions = @(),
        $Details = $null
    )

    $step = Get-CyberButlerJournalStep -Journal $Journal -Name $Name
    if ($null -eq $step) {
        $step = [pscustomobject]@{
            name = $Name
            status = 'pending'
            started_at = $null
            finished_at = $null
            reverse_actions = @()
            details = [pscustomobject]@{}
        }
        $Journal.State.steps = @($Journal.State.steps) + $step
    }

    if ($Status -eq 'in_progress' -and -not $step.started_at) {
        $step.started_at = Get-InstallerUtcTimestamp
    }
    if ($Status -in @('completed', 'failed', 'rolled_back')) {
        $step.finished_at = Get-InstallerUtcTimestamp
    }
    $step.status = $Status
    $Journal.State.current_step = if ($Status -in @('completed', 'skipped', 'rolled_back')) { $null } else { $Name }

    foreach ($action in @($ReverseActions)) {
        if ($null -ne $action) {
            $step.reverse_actions = @($step.reverse_actions) + $action
        }
    }
    if ($null -ne $Details -and $Details -isnot [string]) {
        $step.details = $Details
    } elseif ($null -ne $Details) {
        $step.details = [pscustomobject]@{ note = [string]$Details }
    }

    Save-CyberButlerJournal -Journal $Journal
    return $step
}

function Add-CyberButlerReverseAction {
    param(
        [Parameter(Mandatory = $true)]
        $Journal,
        [Parameter(Mandatory = $true)]
        [string]$Step,
        [Parameter(Mandatory = $true)]
        $Action
    )

    $stepObject = Get-CyberButlerJournalStep -Journal $Journal -Name $Step
    if ($null -eq $stepObject) { throw "Journal step not found: $Step" }
    $stepObject.reverse_actions = @($stepObject.reverse_actions) + $Action
    Save-CyberButlerJournal -Journal $Journal
}

function Get-CyberButlerResumeStep {
    param(
        [Parameter(Mandatory = $true)]
        $Journal
    )

    foreach ($step in @($Journal.State.steps)) {
        if ([string]$step.status -notin @('completed', 'skipped', 'rolled_back')) {
            return $step
        }
    }
    return $null
}

<#
.SYNOPSIS
    New-CyberButlerTrackedDirectory performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function New-CyberButlerTrackedDirectory {
    param(
        [Parameter(Mandatory = $true)]
        $Journal,
        [Parameter(Mandatory = $true)]
        [string]$Step,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot
    )

    $full = [IO.Path]::GetFullPath($Path)
    $rootFull = [IO.Path]::GetFullPath($AllowedRoot).TrimEnd('')
    if ($full -ine $rootFull -and -not (Test-InstallerPathWithin -Path $full -Root $AllowedRoot)) {
        throw "Tracked directory escapes AllowedRoot: $full"
    }
    if (Test-Path -LiteralPath $full) { return $null }

    New-Item -ItemType Directory -Path $full -Force | Out-Null
    $action = [pscustomobject][ordered]@{
        type = 'delete-created-directory'
        path = $full
        allowed_root = [IO.Path]::GetFullPath($AllowedRoot)
    }
    Add-CyberButlerReverseAction -Journal $Journal -Step $Step -Action $action
    return $full
}

<#
.SYNOPSIS
    Backup-CyberButlerFile performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Backup-CyberButlerFile {
    param(
        [Parameter(Mandatory = $true)]
        $Journal,
        [Parameter(Mandatory = $true)]
        [string]$Step,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$AllowedRoot
    )

    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) { throw "File not found: $full" }
    if (-not (Test-InstallerPathWithin -Path $full -Root $AllowedRoot)) {
        throw "Backup file escapes AllowedRoot: $full"
    }

    $hash = Get-InstallerFileSha256 -Path $full
    $backupDir = Join-Path $Journal.BackupRoot 'files'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backup = Join-Path $backupDir ('{0}-{1}' -f $hash.Substring(0, 12), (Split-Path -Leaf $full))
    Copy-Item -LiteralPath $full -Destination $backup -Force

    $action = [pscustomobject][ordered]@{
        type = 'restore-file'
        target = $full
        backup = $backup
        sha256 = $hash
        allowed_root = [IO.Path]::GetFullPath($AllowedRoot)
    }
    Add-CyberButlerReverseAction -Journal $Journal -Step $Step -Action $action
    return $backup
}

<#
.SYNOPSIS
    Backup-CyberButlerAcl performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Backup-CyberButlerAcl {
    param(
        [Parameter(Mandatory = $true)]
        $Journal,
        [Parameter(Mandatory = $true)]
        [string]$Step,
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [switch]$NoTrack
    )

    $full = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $full)) { throw "ACL target not found: $full" }
    $backupDir = Join-Path $Journal.BackupRoot 'acl'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $key = [guid]::NewGuid().ToString('N').Substring(0, 12)
    $backup = Join-Path $backupDir ($key + '.clixml')
    Get-Acl -LiteralPath $full | Export-Clixml -LiteralPath $backup -Force

    $action = [pscustomobject][ordered]@{
        type = 'restore-acl'
        target = $full
        backup = $backup
    }
    if (-not $NoTrack) {
        Add-CyberButlerReverseAction -Journal $Journal -Step $Step -Action $action
    }
    return $backup
}

<#
.SYNOPSIS
    Backup-CyberButlerScheduledTask performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Backup-CyberButlerScheduledTask {
    param(
        [Parameter(Mandatory = $true)]
        $Journal,
        [Parameter(Mandatory = $true)]
        [string]$Step,
        [Parameter(Mandatory = $true)]
        [string]$TaskName
    )

    $xml = Export-ScheduledTask -TaskName $TaskName -ErrorAction Stop
    if (-not $xml) { throw "Scheduled task not found: $TaskName" }
    $backupDir = Join-Path $Journal.BackupRoot 'tasks'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $safeName = ($TaskName -replace '[^A-Za-z0-9_.-]', '_')
    $backup = Join-Path $backupDir ($safeName + '.xml')
    [IO.File]::WriteAllText($backup, $xml, (New-Object Text.UTF8Encoding($false)))

    $action = [pscustomobject][ordered]@{
        type = 'restore-scheduled-task'
        task_name = $TaskName
        backup = $backup
    }
    Add-CyberButlerReverseAction -Journal $Journal -Step $Step -Action $action
    return $backup
}

<#
.SYNOPSIS
    Invoke-CyberButlerReverseAction performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Invoke-CyberButlerReverseAction {
    param(
        [Parameter(Mandatory = $true)]
        $Action
    )

    $type = [string]$Action.type
    switch ($type) {
        'delete-created-directory' {
            $path = [IO.Path]::GetFullPath([string]$Action.path)
            $allowed = [IO.Path]::GetFullPath([string]$Action.allowed_root)
            if (-not (Test-InstallerPathWithin -Path $path -Root $allowed)) {
                throw "Refusing to delete outside allowed root: $path"
            }
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
        }
        'delete-created-file' {
            $path = [IO.Path]::GetFullPath([string]$Action.path)
            $allowed = [IO.Path]::GetFullPath([string]$Action.allowed_root)
            if (-not (Test-InstallerPathWithin -Path $path -Root $allowed)) {
                throw "Refusing to delete outside allowed root: $path"
            }
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
        }
        'restore-file' {
            $target = [IO.Path]::GetFullPath([string]$Action.target)
            $backup = [IO.Path]::GetFullPath([string]$Action.backup)
            if (-not (Test-Path -LiteralPath $backup -PathType Leaf)) { throw "Backup file missing: $backup" }
            $parent = Split-Path -Parent $target
            if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $backup -Destination $target -Force
            if ($Action.sha256 -and (Get-InstallerFileSha256 -Path $target) -ne [string]$Action.sha256) {
                throw "Restored file hash mismatch: $target"
            }
        }
        'restore-acl' {
            $target = [IO.Path]::GetFullPath([string]$Action.target)
            $backup = [IO.Path]::GetFullPath([string]$Action.backup)
            if (-not (Test-Path -LiteralPath $backup)) { throw "ACL backup missing: $backup" }
            $acl = Import-Clixml -LiteralPath $backup
            Set-Acl -LiteralPath $target -AclObject $acl
        }
        'restore-scheduled-task' {
            $backup = [IO.Path]::GetFullPath([string]$Action.backup)
            if (-not (Test-Path -LiteralPath $backup)) { throw "Task XML backup missing: $backup" }
            $xml = Get-Content -LiteralPath $backup -Raw -Encoding UTF8
            Register-ScheduledTask -TaskName ([string]$Action.task_name) -Xml $xml -Force | Out-Null
        }
        'delete-created-scheduled-task' {
            $name = [string]$Action.task_name
            if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
                Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop
            }
        }
        'stop-created-process' {
            $processId = [int]$Action.process_id
            $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($process) {
                if ($Action.expected_name -and [string]$process.ProcessName -ne [string]$Action.expected_name) {
                    throw "PID $processId no longer matches $($Action.expected_name)"
                }
                Stop-Process -Id $processId -Force -ErrorAction Stop
            }
        }
        'stop-install-port-processes' {
            if (Get-Command Stop-CyberButlerInstallProcesses -ErrorAction SilentlyContinue) {
                Stop-CyberButlerInstallProcesses -Root ([string]$Action.root) -Ports @($Action.ports) | Out-Null
            }
        }
        'delete-created-account' {
            $name = [string]$Action.account_name
            $user = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
            if ($user) { Remove-LocalUser -Name $name -ErrorAction Stop }
        }
        'disable-created-account' {
            $name = [string]$Action.account_name
            $user = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
            if ($user) { Disable-LocalUser -Name $name -ErrorAction Stop }
        }
        'delete-created-firewall-rule' {
            $name = [string]$Action.rule_name
            if (Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue) {
                Remove-NetFirewallRule -Name $name -ErrorAction Stop
            }
        }
        'restore-firewall-rule' {
            $name = [string]$Action.rule_name
            $state = $Action.state
            $rule = Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue
            if (-not $rule) {
                New-NetFirewallRule -Name $name -DisplayName $name -Direction ([string]$state.direction) `
                    -Action ([string]$state.action) -Profile ([string]$state.profile) -Enabled ([bool]$state.enabled) | Out-Null
            } else {
                Set-NetFirewallRule -Name $name -Enabled ([bool]$state.enabled) `
                    -Direction ([string]$state.direction) -Action ([string]$state.action) `
                    -Profile ([string]$state.profile) -ErrorAction Stop
            }
            if ($null -ne $state.remote_address) {
                Set-NetFirewallAddressFilter -Name $name -RemoteAddress ([string]$state.remote_address) -ErrorAction Stop
            }
            if ($null -ne $state.port) {
                Set-NetFirewallPortFilter -Name $name -Protocol ([string]$state.protocol) -LocalPort ([string]$state.port) -ErrorAction Stop
            }
        }
        default { throw "Unknown reverse action type: $type" }
    }
}

<#
.SYNOPSIS
    Invoke-CyberButlerRollback performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Invoke-CyberButlerRollback {
    param(
        [Parameter(Mandatory = $true)]
        $Journal,
        [hashtable]$Handlers = @{},
        [switch]$DryRun
    )

    $executed = New-Object System.Collections.Generic.List[object]
    $errors = New-Object System.Collections.Generic.List[string]
    $steps = @($Journal.State.steps)
    [array]::Reverse($steps)

    foreach ($step in $steps) {
        if ([string]$step.status -in @('pending', 'skipped', 'rolled_back')) { continue }
        if ([string]$step.status -eq 'completed') {
            if (-not $DryRun) {
                if ($null -eq $step.details -or $step.details -is [string]) { $step.details = [pscustomobject]@{} }
                $step.details | Add-Member -NotePropertyName undo -NotePropertyValue ([pscustomobject]@{
                    status = 'preserved'
                    executed = @()
                    errors = @()
                    at = Get-InstallerUtcTimestamp
                }) -Force
            }
            continue
        }
        $actions = @($step.reverse_actions)
        [array]::Reverse($actions)
        $stepExecuted = New-Object System.Collections.Generic.List[object]
        $stepErrors = New-Object System.Collections.Generic.List[string]
        foreach ($action in $actions) {
            if ($null -eq $action) { continue }
            $type = [string]$action.type
            $executed.Add($action)
            $stepExecuted.Add($action)
            if ($DryRun) { continue }
            try {
                if ($Handlers.ContainsKey($type)) {
                    $Handlers[$type].Invoke($action) | Out-Null
                } else {
                    Invoke-CyberButlerReverseAction -Action $action
                }
            } catch {
                $message = ('{0}: {1}' -f $type, $_.Exception.Message)
                $errors.Add($message)
                $stepErrors.Add($message)
            }
        }
        if (-not $DryRun) {
            $undoStatus = if ($stepErrors.Count -gt 0) { 'rollback_failed' } else { 'completed' }
            if ($null -eq $step.details -or $step.details -is [string]) { $step.details = [pscustomobject]@{} }
            $step.details | Add-Member -NotePropertyName undo -NotePropertyValue ([pscustomobject]@{
                status = $undoStatus
                executed = $stepExecuted.ToArray()
                errors = $stepErrors.ToArray()
                at = Get-InstallerUtcTimestamp
            }) -Force
            if ([string]$step.status -notin @('completed', 'failed')) { $step.status = 'rolled_back' }
        }
    }

    if (-not $DryRun) {
        $Journal.State.status = if ($errors.Count -gt 0) { 'rollback_failed' } else { 'rolled_back' }
        $Journal.State.current_step = $null
        Save-CyberButlerJournal -Journal $Journal
    }

    return [pscustomobject]@{
        status = if ($errors.Count -gt 0) { 'rollback_failed' } else { 'rolled_back' }
        dry_run = [bool]$DryRun
        executed = $executed.ToArray()
        errors = $errors.ToArray()
    }
}
