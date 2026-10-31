#Requires -Version 5.1
<#
.SYNOPSIS
  Migrate a single-account Cyber-Butler install to dual-account isolation.
#>
[CmdletBinding()]
param(
    [switch]$PlanOnly,
    [switch]$Apply,
    [switch]$Verify,
    [switch]$Rollback,

    [switch]$NonInteractive,
    [string]$Tier = 'Medium',
    [string]$InstallPath = 'C:\CyberButler',
    [string]$ServiceAccountName = 'CyberButlerSvc',
    [string]$DesktopAccount = '',
    [string]$AstrBotAccount = '',
    [string]$DataPath = '',
    [string]$WorkspacePath = '',
    [string]$TotpVaultPath = '',

    [string]$JournalRoot = '',
    [string]$ReportDirectory = '',
    [string]$StatePath = '',
    [string]$Approval = '',

    [hashtable]$Handlers = @{},
    [hashtable]$RollbackHandlers = @{},
    [string]$TestConfigPath = ''
)

$ErrorActionPreference = 'Stop'
$migrationRoot = $PSScriptRoot
. (Join-Path $migrationRoot 'lib\Installer.Common.ps1')
. (Join-Path $migrationRoot 'lib\Installer.Tier.ps1')
. (Join-Path $migrationRoot 'lib\Installer.Journal.ps1')
. (Join-Path $migrationRoot 'lib\Installer.Preflight.ps1')
. (Join-Path $migrationRoot 'lib\Installer.Accounts.ps1')
. (Join-Path $migrationRoot 'lib\Installer.Acl.ps1')
. (Join-Path $migrationRoot 'lib\Installer.Secrets.ps1')
. (Join-Path $migrationRoot 'lib\Installer.Services.ps1')

if (-not [string]::IsNullOrWhiteSpace($TestConfigPath)) {
    if (-not (Test-Path -LiteralPath $TestConfigPath)) { throw "TestConfigPath not found: $TestConfigPath" }
    $testConfig = & $TestConfigPath
    if ($testConfig.Handlers) { $Handlers = $testConfig.Handlers }
    if ($testConfig.RollbackHandlers) { $RollbackHandlers = $testConfig.RollbackHandlers }
    if (-not $Approval -and $testConfig.Approval) { $Approval = [string]$testConfig.Approval }
}

$modes = @($PlanOnly.IsPresent, $Apply.IsPresent, $Verify.IsPresent, $Rollback.IsPresent) | Where-Object { $_ }
if ($modes.Count -ne 1) {
    Write-InstallerLine 'Choose exactly one of -PlanOnly, -Apply, -Verify, or -Rollback.' -Level ERROR
    exit (Get-InstallerExitCode -Name ValidationFailed)
}

if ([string]::IsNullOrWhiteSpace($DesktopAccount)) {
    $DesktopAccount = [Security.Principal.WindowsIdentity]::GetCurrent().Name
}
if ([string]::IsNullOrWhiteSpace($AstrBotAccount)) {
    $AstrBotAccount = [Security.Principal.WindowsIdentity]::GetCurrent().Name
}
if ([string]::IsNullOrWhiteSpace($TotpVaultPath)) {
    $TotpVaultPath = Join-Path $InstallPath 'tools\totp-vault'
}
if ([string]::IsNullOrWhiteSpace($JournalRoot)) {
    $JournalRoot = if (Test-InstallerAdministrator) {
        Join-Path $env:ProgramData 'CyberButler\installer\state'
    } else {
        Join-Path $env:LOCALAPPDATA 'CyberButler\installer\state'
    }
}
if ([string]::IsNullOrWhiteSpace($ReportDirectory)) {
    $ReportDirectory = if (Test-InstallerAdministrator) {
        Join-Path $InstallPath 'migration-report'
    } else {
        Join-Path $env:LOCALAPPDATA 'CyberButler\migration-report'
    }
}

function Write-MigrationReport {
    param(
        [string]$Mode,
        [string]$Status,
        $State,
        $Steps,
        $Approvals,
        $Journal,
        $Failure,
        [string]$Message
    )
    $report = [ordered]@{
        schema = 1
        generated_at = Get-InstallerUtcTimestamp
        mode = $Mode
        status = $Status
        tier = $Tier
        service_account = $ServiceAccountName
        desktop_account = $DesktopAccount
        astrbot_account = $AstrBotAccount
        snowluma = 'unchanged'
        broker = 'unchanged'
        downtime_estimate = '2-5 minutes (must be measured on the clean VM)'
        steps = @($Steps)
        approvals = @($Approvals)
        journal_path = if ($Journal) { [string]$Journal.StatePath } else { $null }
        failure = $Failure
        message = $Message
    }
    $dir = [IO.Path]::GetFullPath($ReportDirectory)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $jsonPath = Join-Path $dir 'migration-report.json'
    $mdPath = Join-Path $dir 'migration-report.md'
    Write-InstallerJson -Path $jsonPath -Value $report
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Cyber-Butler Isolation Migration Report')
    $lines.Add('')
    $lines.Add('- Mode: ' + $Mode)
    $lines.Add('- Status: ' + $Status)
    $lines.Add('- Tier: ' + $Tier)
    $lines.Add('- Service account: ' + $ServiceAccountName)
    $lines.Add('- SnowLuma: unchanged')
    $lines.Add('- Broker: unchanged')
    $lines.Add('- Downtime estimate: ' + $report.downtime_estimate)
    if ($Journal) { $lines.Add('- Journal: ' + $Journal.StatePath) }
    $lines.Add('')
    $lines.Add('## Steps')
    foreach ($step in @($Steps)) { $lines.Add(('- {0}: {1}' -f $step.name, $step.status)) }
    $lines.Add('')
    $lines.Add('## Approvals')
    foreach ($approval in @($Approvals)) { $lines.Add(('- {0} at {1}' -f $approval.token, $approval.at)) }
    if ($Failure) { $lines.Add(''); $lines.Add('## Failure'); $lines.Add($Failure.message) }
    [IO.File]::WriteAllText($mdPath, ($lines -join [Environment]::NewLine) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    return [pscustomobject]@{ json = $jsonPath; markdown = $mdPath }
}

function Get-MigrationState {
    param($Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.test') {
        $state = Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.test' -Context ([pscustomobject]@{ ServiceAccountName = $ServiceAccountName; AstrBotAccount = $AstrBotAccount })
        return $state
    }
    $user = Get-LocalUser -Name $ServiceAccountName -ErrorAction SilentlyContinue
    $astrbotTask = Get-ScheduledTask -TaskName 'AstrBot Service' -ErrorAction SilentlyContinue
    $webTask = Get-ScheduledTask -TaskName 'Cyber-Butler Web UI Services' -ErrorAction SilentlyContinue
    $astrbotPrincipal = if ($astrbotTask) { [string]$astrbotTask.Principal.UserId } else { $null }
    $webPrincipal = if ($webTask) { [string]$webTask.Principal.UserId } else { $null }
    return [pscustomobject]@{
        satisfied = ([bool]$user -and $astrbotPrincipal -ieq $ServiceAccountName -and $webPrincipal -ieq $ServiceAccountName)
        account_exists = [bool]$user
        astrbot_principal = $astrbotPrincipal
        webui_principal = $webPrincipal
        snowluma = 'unchanged'
        broker = 'unchanged'
        reason = 'migration state checked'
    }
}

function Format-MigrationPlan {
    param([string]$Mode, $State)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Cyber-Butler isolation migration plan')
    $lines.Add('Mode: ' + $Mode)
    $lines.Add('Tier: ' + $Tier)
    $lines.Add('Service account: ' + $ServiceAccountName)
    $lines.Add('Current AstrBot principal: ' + $(if ($State.astrbot_principal) { $State.astrbot_principal } else { 'unknown' }))
    $lines.Add('Current Web UI principal: ' + $(if ($State.webui_principal) { $State.webui_principal } else { 'unknown' }))
    $lines.Add('SnowLuma: unchanged (not migrated)')
    $lines.Add('Broker: unchanged (not migrated)')
    $lines.Add('Steps: preflight -> snapshot -> account -> acl -> dpapi -> stop -> tasks -> start -> verify -> commit')
    $lines.Add('Downtime estimate: 2-5 minutes (must be measured on the clean VM)')
    $lines.Add('Rollback: restore task XML, ACL, secret backups; start old AstrBot/Web UI; data is not copied')
    $lines.Add('Data: never copied or rolled back')
    return ($lines -join [Environment]::NewLine)
}

function Invoke-MigrationPreflight {
    param($Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.preflight') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.preflight' -Context ([pscustomobject]@{ InstallPath = $InstallPath }))
    }
    return (Get-CyberButlerPreflight -InstallPath $InstallPath)
}

function Invoke-MigrationSnapshot {
    param($Journal, $Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.snapshot') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.snapshot' -Context ([pscustomobject]@{ Journal = $Journal }))
    }
    $taskNames = @('AstrBot Service', 'Cyber-Butler Web UI Services')
    foreach ($taskName in $taskNames) {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            $backup = Backup-CyberButlerScheduledTask -Journal $Journal -Step 'snapshot' -TaskName $taskName
            Add-CyberButlerReverseAction -Journal $Journal -Step 'snapshot' -Action ([pscustomobject]@{ type = 'restore-scheduled-task'; task_name = $taskName; backup = $backup })
        }
    }
    foreach ($path in @((Join-Path $InstallPath 'AstrBot'), (Join-Path $InstallPath 'tools'), (Join-Path $InstallPath 'AstrBot\data'), $TotpVaultPath)) {
        if (Test-Path -LiteralPath $path) {
            $backup = Backup-CyberButlerAcl -Journal $Journal -Step 'snapshot' -Path $path -NoTrack
            Add-CyberButlerReverseAction -Journal $Journal -Step 'snapshot' -Action ([pscustomobject]@{ type = 'restore-acl'; target = [IO.Path]::GetFullPath($path); backup = $backup })
        }
    }
    return [pscustomobject]@{ status = 'completed'; snapshot = 'tasks+acl' }
}

function Invoke-MigrationAcl {
    param($Journal, $Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.acl') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.acl' -Context ([pscustomobject]@{ Journal = $Journal; ServiceAccountName = $ServiceAccountName }))
    }
    $targets = @(
        @{ path = (Join-Path $InstallPath 'AstrBot'); mode = 'RX' },
        @{ path = (Join-Path $InstallPath 'AstrBot\.venv'); mode = 'RX' },
        @{ path = (Join-Path $InstallPath 'AstrBot\data'); mode = 'RW' },
        @{ path = (Join-Path $InstallPath 'workspace'); mode = 'RW' },
        @{ path = $TotpVaultPath; mode = 'Deny' }
    )
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target.path)) { continue }
        $backup = Backup-CyberButlerAcl -Journal $Journal -Step 'acl' -Path $target.path -NoTrack
        Add-CyberButlerReverseAction -Journal $Journal -Step 'acl' -Action ([pscustomobject]@{ type = 'restore-acl'; target = [IO.Path]::GetFullPath($target.path); backup = $backup })
        Set-CyberButlerAcl -Path $target.path -Identity $ServiceAccountName -Mode $target.mode | Out-Null
    }
    return [pscustomobject]@{ status = 'completed'; targets = $targets.Count }
}

function Invoke-MigrationDpapi {
    param($Journal, $Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.dpapi') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.dpapi' -Context ([pscustomobject]@{ Journal = $Journal }))
    }
    foreach ($name in @('deepseek.key.dpapi', 'owner_qq.dpapi', 'smtp.secret.dpapi')) {
        $path = Join-Path $InstallPath ('tools\' + $name)
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $backup = Backup-CyberButlerFile -Journal $Journal -Step 'dpapi' -Path $path -AllowedRoot $InstallPath
        try {
            $plain = Unprotect-CyberButlerFile -Path $path -Scope CurrentUser
            $bytes = Protect-CyberButlerString -PlainText $plain -Scope LocalMachine
            [IO.File]::WriteAllBytes($path, $bytes)
        } catch {
            # Machine-scope material may already be readable; leave it untouched.
        }
    }
    return [pscustomobject]@{ status = 'completed'; scope = 'LocalMachine' }
}

function Invoke-MigrationStop {
    param($Journal, $Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.stop') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.stop' -Context ([pscustomobject]@{ Journal = $Journal }))
    }
    foreach ($taskName in @('AstrBot Service', 'Cyber-Butler Web UI Services')) {
        Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    return [pscustomobject]@{ status = 'completed'; stopped = 'AstrBot Service, Cyber-Butler Web UI Services'; snowluma = 'unchanged'; broker = 'unchanged' }
}

function Invoke-MigrationTasks {
    param($Journal, $Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.tasks') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.tasks' -Context ([pscustomobject]@{ Journal = $Journal; ServiceAccountName = $ServiceAccountName }))
    }
    $python = Join-Path $InstallPath 'AstrBot\.venv\Scripts\python.exe'
    $web = Join-Path $InstallPath 'webui\.venv\Scripts\python.exe'
    New-CyberButlerScheduledTask -Name 'AstrBot Service' -Exe $python -Arguments 'main.py' -WorkingDirectory (Join-Path $InstallPath 'AstrBot') -PrincipalMode 'service' -ServiceAccount $ServiceAccountName -DesktopAccount $DesktopAccount -Trigger 'AtLogOn'
    New-CyberButlerScheduledTask -Name 'Cyber-Butler Web UI Services' -Exe $web -Arguments 'run.py' -WorkingDirectory (Join-Path $InstallPath 'webui') -PrincipalMode 'service' -ServiceAccount $ServiceAccountName -DesktopAccount $DesktopAccount -Trigger 'AtLogOn'
    return [pscustomobject]@{ status = 'completed'; tasks = @('AstrBot Service', 'Cyber-Butler Web UI Services'); snowluma = 'unchanged'; broker = 'unchanged' }
}

function Invoke-MigrationStart {
    param($Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.start') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.start' -Context ([pscustomobject]@{ InstallPath = $InstallPath }))
    }
    foreach ($taskName in @('AstrBot Service', 'Cyber-Butler Web UI Services')) {
        Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    }
    $deadline = (Get-Date).AddSeconds(60)
    do {
        $ports = Test-CyberButlerPortHealth -Ports @(6185, 8765, 18090)
        if (@($ports | Where-Object { -not $_.healthy }).Count -eq 0) { break }
        Start-Sleep -Seconds 2
    } while ((Get-Date) -lt $deadline)
    return [pscustomobject]@{ status = 'completed'; ports = @(6185, 8765, 18090) }
}

function Invoke-MigrationVerify {
    param($Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.verify') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.verify' -Context ([pscustomobject]@{ ServiceAccountName = $ServiceAccountName }))
    }
    $state = Get-MigrationState -Handlers $Handlers
    return $state.satisfied
}

function Invoke-MigrationRollback {
    param($Journal, $Handlers)
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.undo') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.undo' -Context ([pscustomobject]@{ Journal = $Journal }))
    }
    $result = Invoke-CyberButlerRollback -Journal $Journal -Handlers $RollbackHandlers
    foreach ($taskName in @('AstrBot Service', 'Cyber-Butler Web UI Services')) {
        Start-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    }
    return $result
}

$state = Get-MigrationState -Handlers $Handlers

if ($PlanOnly) {
    $preflight = Invoke-MigrationPreflight -Handlers $Handlers
    Write-Output ('PREFLIGHT existing=' + $preflight.install_path.existing_state)
    Write-Output (Format-MigrationPlan -Mode 'PlanOnly' -State $state)
    exit (Get-InstallerExitCode -Name Success)
}

if ($Verify) {
    if ([bool]$state.satisfied) {
        Write-Output 'ISOLATION_VERIFIED'
        exit (Get-InstallerExitCode -Name Success)
    }
    Write-Output 'ISOLATION_NOT_VERIFIED'
    exit (Get-InstallerExitCode -Name ValidationFailed)
}

if ($Rollback) {
    if ([string]::IsNullOrWhiteSpace($StatePath)) {
        $candidate = Get-ChildItem -LiteralPath $JournalRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { Join-Path $_.FullName 'state.json' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        $StatePath = $candidate
    }
    if ([string]::IsNullOrWhiteSpace($StatePath) -or -not (Test-Path -LiteralPath $StatePath)) {
        Write-InstallerLine 'No migration journal found for -Rollback.' -Level ERROR
        exit (Get-InstallerExitCode -Name ValidationFailed)
    }
    $journal = Read-CyberButlerJournal -StatePath $StatePath
    $rollbackResult = Invoke-MigrationRollback -Journal $journal -Handlers $Handlers
    $report = Write-MigrationReport -Mode 'Rollback' -Status $(if ($rollbackResult.status -eq 'rollback_failed') { 'failed' } else { 'rolled_back' }) -State $state -Steps @($journal.State.steps) -Approvals @() -Journal $journal -Failure $null -Message 'Migration rolled back; data was not copied.'
    Write-Output ('ROLLBACK ' + $rollbackResult.status)
    Write-Output ('REPORT ' + $report.json)
    if ($rollbackResult.status -eq 'rollback_failed') { exit (Get-InstallerExitCode -Name RollbackFailed) }
    exit (Get-InstallerExitCode -Name Success)
}

# Apply
if ($state.satisfied) {
    Write-Output 'ISOLATION_ALREADY_ENABLED'
    exit (Get-InstallerExitCode -Name Success)
}
if (-not $Approval) {
    if ($NonInteractive) {
        Write-InstallerLine 'APPROVE MIGRATE-ISOLATION is required.' -Level BLOCKING
        exit (Get-InstallerExitCode -Name NeedsApproval)
    }
    $Approval = Read-Host 'Type APPROVE MIGRATE-ISOLATION to continue'
}
if ($Approval -cne 'APPROVE MIGRATE-ISOLATION') {
    Write-InstallerLine 'Migration approval token did not match.' -Level BLOCKING
    exit (Get-InstallerExitCode -Name NeedsApproval)
}

$journal = New-CyberButlerJournal -Root $JournalRoot -InstallPath $InstallPath -Tier $Tier -Isolation $true
$approvals = @([pscustomobject]@{ token = 'APPROVE MIGRATE-ISOLATION'; step = 'apply'; at = Get-InstallerUtcTimestamp })

function Add-MigrationStep {
    param([string]$Name, [string]$Status, [string]$Reason = '')
    Add-CyberButlerJournalStep -Journal $journal -Name $Name -Status $Status -Details ([pscustomobject]@{ reason = $Reason }) | Out-Null
}

$steps = @(
    @{ name = 'preflight'; handler = 'migration.preflight'; action = { Invoke-MigrationPreflight -Handlers $Handlers } },
    @{ name = 'snapshot'; handler = 'migration.snapshot'; action = { Invoke-MigrationSnapshot -Journal $journal -Handlers $Handlers } },
    @{ name = 'account'; handler = 'migration.account'; action = {
        if (Test-CyberButlerHandler -Handlers $Handlers -Name 'migration.account') {
            $created = Invoke-CyberButlerHandler -Handlers $Handlers -Name 'migration.account' -Context ([pscustomobject]@{ ServiceAccountName = $ServiceAccountName })
        } else {
            $created = New-CyberButlerLocalAccount -AccountName $ServiceAccountName -Handlers $Handlers
        }
        if ($created.created) {
            Add-CyberButlerReverseAction -Journal $journal -Step 'account' -Action ([pscustomobject]@{ type = 'delete-created-account'; account_name = $ServiceAccountName })
        }
        $created
    } },
    @{ name = 'acl'; handler = 'migration.acl'; action = { Invoke-MigrationAcl -Journal $journal -Handlers $Handlers } },
    @{ name = 'dpapi'; handler = 'migration.dpapi'; action = { Invoke-MigrationDpapi -Journal $journal -Handlers $Handlers } },
    @{ name = 'stop'; handler = 'migration.stop'; action = { Invoke-MigrationStop -Journal $journal -Handlers $Handlers } },
    @{ name = 'tasks'; handler = 'migration.tasks'; action = { Invoke-MigrationTasks -Journal $journal -Handlers $Handlers } },
    @{ name = 'start'; handler = 'migration.start'; action = { Invoke-MigrationStart -Handlers $Handlers } },
    @{ name = 'verify'; handler = 'migration.verify'; action = { Invoke-MigrationVerify -Handlers $Handlers } }
)

$failure = $null
foreach ($step in $steps) {
    Add-MigrationStep -Name $step.name -Status 'in_progress'
    try {
        $result = & $step.action
        if ($null -ne $result -and $null -ne $result.status -and $result.status -eq 'failed') { throw "step returned failed" }
        if ($step.name -eq 'verify' -and -not [bool]$result) { throw 'isolation verification failed' }
        Add-MigrationStep -Name $step.name -Status 'completed'
    } catch {
        Add-MigrationStep -Name $step.name -Status 'failed' -Reason $_.Exception.Message
        $failure = [pscustomobject]@{ step = $step.name; message = $_.Exception.Message }
        break
    }
}

if ($failure) {
    $rollbackResult = Invoke-MigrationRollback -Journal $journal -Handlers $Handlers
    $manualPath = Join-Path $journal.RunRoot 'migration-manual-recovery.txt'
    $manual = "Migration failed.`r`nJournal: $($journal.StatePath)`r`nRollback: $($rollbackResult.status)`r`nFailure: $($failure.step): $($failure.message)`r`n"
    [IO.File]::WriteAllText($manualPath, $manual, (New-Object Text.UTF8Encoding($false)))
    $report = Write-MigrationReport -Mode 'Apply' -Status 'failed' -State $state -Steps @($journal.State.steps) -Approvals $approvals -Journal $journal -Failure $failure -Message ('Manual recovery: ' + $manualPath)
    Write-Output ('FAILED ' + $failure.step + ': ' + $failure.message)
    Write-Output ('REPORT ' + $report.json)
    Write-Output ('MANUAL ' + $manualPath)
    if ($rollbackResult.status -eq 'rollback_failed') { exit (Get-InstallerExitCode -Name RollbackFailed) }
    exit (Get-InstallerExitCode -Name ValidationFailed)
}

$migrationVersion = '1.6.0'
try {
    $releaseVersionPath = Join-Path (Split-Path -Parent $migrationRoot) 'VERSION'
    if (Test-Path -LiteralPath $releaseVersionPath) {
        $migrationVersion = (Get-Content -LiteralPath $releaseVersionPath -Raw -ErrorAction SilentlyContinue).Trim()
    }
} catch { }
try {
    $markerPath = Write-CyberButlerInstallStateMarker -InstallPath $InstallPath -Version $migrationVersion -Tier $Tier -Isolation $true -Source 'migration'
    Write-Output ('STATE ' + $markerPath)
} catch {
    Write-InstallerLine ('Install state marker was not written: ' + $_.Exception.Message) -Level WARN
}
$report = Write-MigrationReport -Mode 'Apply' -Status 'success' -State $state -Steps @($journal.State.steps) -Approvals $approvals -Journal $journal -Failure $null -Message 'Dual-account isolation enabled; SnowLuma and Broker unchanged.'
Write-Output 'MIGRATION_OK'
Write-Output ('REPORT ' + $report.json)
exit (Get-InstallerExitCode -Name Success)
