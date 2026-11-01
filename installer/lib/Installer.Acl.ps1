# ACL lifecycle for the Cyber-Butler installer.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

function Get-CyberButlerAclTargets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )
    $root = [IO.Path]::GetFullPath($InstallPath)
    return @(
        (Join-Path $root 'AstrBot'),
        (Join-Path $root 'AstrBot\.venv'),
        (Join-Path $root 'SnowLuma'),
        (Join-Path $root 'data'),
        (Join-Path $root 'workspace')
    )
}

function Get-CyberButlerAclMask {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('RX', 'RW', 'Deny')]
        [string]$Mode
    )

    switch ($Mode) {
        'RX'   { return [System.Security.AccessControl.FileSystemRights]::ReadAndExecute }
        'RW'   { return [System.Security.AccessControl.FileSystemRights]::Modify }
        'Deny' { return [System.Security.AccessControl.FileSystemRights]::FullControl }
    }
}

function Get-CyberButlerAclAccessType {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('RX', 'RW', 'Deny')]
        [string]$Mode
    )
    if ($Mode -eq 'Deny') { return [System.Security.AccessControl.AccessControlType]::Deny }
    return [System.Security.AccessControl.AccessControlType]::Allow
}

function Test-CyberButlerAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Identity,
        [Parameter(Mandatory = $true)]
        [ValidateSet('RX', 'RW', 'Deny')]
        [string]$Mode,
        $Handlers = @{}
    )

    $context = [pscustomobject]@{ Path = $Path; Identity = $Identity; Mode = $Mode }
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'acl.test') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'acl.test' -Context $context)
    }

    $result = [ordered]@{
        path = $Path
        identity = $Identity
        mode = $Mode
        exists = $false
        supported = $true
        can_manage = [bool](Test-InstallerAdministrator)
        satisfied = $false
        reason = ''
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        $result.reason = 'path-missing'
        return [pscustomobject]$result
    }
    $result.exists = $true

    try {
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $target = ([System.Security.Principal.NTAccount]$Identity).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $required = Get-CyberButlerAclMask -Mode $Mode
        $accessType = Get-CyberButlerAclAccessType -Mode $Mode
        foreach ($rule in @($acl.Access)) {
            if ([string]$rule.AccessControlType -ne [string]$accessType) { continue }
            $ruleIdentity = [string]$rule.IdentityReference.Value
            $ruleSid = $null
            try { $ruleSid = ([System.Security.Principal.NTAccount]$ruleIdentity).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }
            if ($ruleIdentity -ne $Identity -and $ruleSid -ne $target) { continue }
            if (([int]$rule.FileSystemRights -band [int]$required) -eq [int]$required) {
                $result.satisfied = $true
                break
            }
        }
        if (-not $result.satisfied) { $result.reason = 'ace-missing' }
    } catch {
        $result.reason = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Assert-CyberButlerAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Identity,
        [Parameter(Mandatory = $true)]
        [ValidateSet('RX', 'RW', 'Deny')]
        [string]$Mode,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'acl.assert') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'acl.assert' -Context ([pscustomobject]@{ Path = $Path; Identity = $Identity; Mode = $Mode }))
    }
    $test = Test-CyberButlerAcl -Path $Path -Identity $Identity -Mode $Mode -Handlers $Handlers
    return [bool]$test.satisfied
}

function Set-CyberButlerAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Identity,
        [Parameter(Mandatory = $true)]
        [ValidateSet('RX', 'RW', 'Deny')]
        [string]$Mode,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'acl.apply') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'acl.apply' -Context ([pscustomobject]@{ Path = $Path; Identity = $Identity; Mode = $Mode }))
    }

    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $inheritance = if (Test-Path -LiteralPath $Path -PathType Container) {
        [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
    } else {
        [System.Security.AccessControl.InheritanceFlags]::None
    }
    $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
        $Identity,
        (Get-CyberButlerAclMask -Mode $Mode),
        $inheritance,
        [System.Security.AccessControl.PropagationFlags]::None,
        (Get-CyberButlerAclAccessType -Mode $Mode)
    )
    $acl.AddAccessRule($rule)
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
    return $true
}


function Set-CyberButlerDataAcl {
    param(
        [Parameter(Mandatory = $true)][string]$DataRoot,
        [Parameter(Mandatory = $true)][string]$ServiceAccount,
        [Parameter(Mandatory = $true)][string]$DesktopAccount,
        $Journal = $null,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'acl.data') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'acl.data' -Context ([pscustomobject]@{ DataRoot = $DataRoot; ServiceAccount = $ServiceAccount; DesktopAccount = $DesktopAccount }))
    }
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'acl.test') {
        return [pscustomobject]@{ status = 'skipped'; reason = 'test-handler'; message = '' }
    }
    if (-not (Test-Path -LiteralPath $DataRoot)) {
        return [pscustomobject]@{ status = 'failed'; reason = 'data-root-missing'; message = $DataRoot }
    }

    $backup = $null
    if ($null -ne $Journal) {
        $backup = Backup-CyberButlerAcl -Journal $Journal -Step 'acl_data' -Path $DataRoot -NoTrack
        if ($backup) {
            Add-CyberButlerReverseAction -Journal $Journal -Step 'acl_data' -Action ([pscustomobject]@{
                type = 'restore-acl'
                target = [IO.Path]::GetFullPath($DataRoot)
                backup = [IO.Path]::GetFullPath($backup)
            })
        }
    }

    $writeDirs = @('cache', 'tmp', 'temp', 'logs', 'plugin_data')
    $readDirs = @('memory', 'config')
    foreach ($name in @($writeDirs + $readDirs)) {
        $path = Join-Path $DataRoot $name
        if (-not (Test-Path -LiteralPath $path)) { New-Item -ItemType Directory -Path $path -Force | Out-Null }
    }

    # Make the root explicit and read-only, then grant writes only to the
    # disposable cache/temp/log/plugin-data subtrees.
    & icacls.exe $DataRoot /inheritance:r `
        /grant:r '*S-1-5-18:(OI)(CI)F' `
        /grant:r '*S-1-5-32-544:(OI)(CI)F' `
        /grant:r "${ServiceAccount}:(OI)(CI)RX" `
        /grant:r "${DesktopAccount}:(OI)(CI)RX" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ status = 'failed'; reason = 'root-acl'; message = ('icacls root failed: ' + $LASTEXITCODE) } }

    foreach ($sid in @('*S-1-5-11', '*S-1-5-32-545', '*S-1-1-0')) {
        & icacls.exe $DataRoot /remove:g $sid /T 2>$null | Out-Null
    }

    foreach ($name in $writeDirs) {
        $path = Join-Path $DataRoot $name
        & icacls.exe $path /grant:r "${ServiceAccount}:(OI)(CI)M" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ status = 'failed'; reason = 'write-acl'; message = $path } }
    }
    foreach ($name in $readDirs) {
        $path = Join-Path $DataRoot $name
        & icacls.exe $path /grant:r "${ServiceAccount}:(OI)(CI)RX" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ status = 'failed'; reason = 'read-acl'; message = $path } }
    }

    $cmdConfig = Join-Path $DataRoot 'cmd_config.json'
    if (Test-Path -LiteralPath $cmdConfig) {
        & icacls.exe $cmdConfig /grant:r "${ServiceAccount}:(RX)" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { return [pscustomobject]@{ status = 'failed'; reason = 'config-acl'; message = $cmdConfig } }
    }

    return [pscustomobject]@{
        status = 'completed'
        reason = 'root-rx; cache/tmp/temp/logs/plugin_data-modify; memory/config-rx'
        message = ''
        backup = $backup
    }
}

function Undo-CyberButlerAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [string]$BackupPath = '',
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'acl.undo') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'acl.undo' -Context ([pscustomobject]@{ Path = $Path; BackupPath = $BackupPath }))
    }
    if ([string]::IsNullOrWhiteSpace($BackupPath) -or -not (Test-Path -LiteralPath $BackupPath)) {
        return [pscustomobject]@{ action = 'failed'; path = $Path; reason = 'backup-missing' }
    }
    try {
        $acl = Import-Clixml -LiteralPath $BackupPath
        Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
        return [pscustomobject]@{ action = 'restored'; path = $Path }
    } catch {
        return [pscustomobject]@{ action = 'failed'; path = $Path; reason = $_.Exception.Message }
    }
}

function Invoke-CyberButlerAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Identity,
        [Parameter(Mandatory = $true)]
        [ValidateSet('RX', 'RW', 'Deny')]
        [string]$Mode,
        [string]$JournalStep = 'acl',
        $Journal = $null,
        [string]$Approval = '',
        [switch]$NonInteractive,
        [switch]$PlanOnly,
        $Handlers = @{}
    )

    $test = Test-CyberButlerAcl -Path $Path -Identity $Identity -Mode $Mode -Handlers $Handlers
    $base = [ordered]@{
        module = 'acl'
        step = $JournalStep
        path = $Path
        identity = $Identity
        mode = $Mode
        test = $test
        changed = $false
    }

    if ($test.satisfied) {
        $base.status = 'skipped'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if (-not $test.exists) {
        $base.status = 'failed'
        $base.message = ('ACL target does not exist: ' + [string]$Path)
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        return [pscustomobject]$base
    }
    if (-not $test.can_manage) {
        $base.status = 'needs_elevation'
        $base.message = 'ACL changes require administrator rights.'
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        return [pscustomobject]$base
    }

    $approvalState = Get-CyberButlerApprovalState -Required 'APPROVE ACL' -Approval $Approval -NonInteractive:$NonInteractive -PlanOnly:$PlanOnly
    if ($approvalState -eq 'plan') {
        $base.status = 'plan'
        $base.message = 'Would back up the ACL and apply the requested access rule.'
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

    $backup = $null
    try {
        if (Test-CyberButlerHandler -Handlers $Handlers -Name 'acl.backup') {
            $backup = Invoke-CyberButlerHandler -Handlers $Handlers -Name 'acl.backup' -Context ([pscustomobject]@{ Path = $Path; Journal = $Journal; Step = $JournalStep })
        } else {
            if ($null -eq $Journal) { throw 'ACL changes require a journal for backup.' }
            $backup = Backup-CyberButlerAcl -Journal $Journal -Step $JournalStep -Path $Path -NoTrack
        }
        if ([string]::IsNullOrWhiteSpace($backup) -or -not (Test-Path -LiteralPath $backup)) {
            throw 'ACL backup was not created.'
        }
        if ($null -ne $Journal) {
            Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                type = 'restore-acl'
                target = [IO.Path]::GetFullPath($Path)
                backup = [IO.Path]::GetFullPath($backup)
            })
        }

        Set-CyberButlerAcl -Path $Path -Identity $Identity -Mode $Mode -Handlers $Handlers | Out-Null
        $asserted = Assert-CyberButlerAcl -Path $Path -Identity $Identity -Mode $Mode -Handlers $Handlers
        if (-not $asserted) { throw 'ACL assertion failed.' }

        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status completed | Out-Null
        }
        $base.changed = $true
        $base.status = 'completed'
        $base.backup = $backup
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    } catch {
        $undo = Undo-CyberButlerAcl -Path $Path -BackupPath $backup -Handlers $Handlers
        $base.status = 'failed'
        $base.message = $_.Exception.Message
        $base.undo = $undo
        $base.exit_code = if ($undo.action -eq 'failed') { Get-InstallerExitCode -Name RollbackFailed } else { Get-InstallerExitCode -Name ValidationFailed }
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ error = $_.Exception.Message; undo = $undo.action }) | Out-Null
        }
        return [pscustomobject]$base
    }
}
