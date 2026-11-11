#Requires -Version 5.1
<#
.SYNOPSIS
  Cyber-Butler v1.6.3 installer.

.DESCRIPTION
  End-to-end installer skeleton. Core deployment is a dry-run placeholder;
  security modules are real but handler-injectable for tests.
#>
[CmdletBinding()]
param(
    [ValidateSet('High', 'Medium', 'Light')]
    [string]$Tier = 'Medium',

    [string[]]$FeatureIds = @(),
    [ValidateSet('QQ', 'Email', '')]
    [string]$ApprovalChannel = '',
    [switch]$AcceptBelowMinimum,

    [string]$EnableIsolation = '',

    [switch]$AcceptLowerSecurity,
    [switch]$AllowSecurityDowngrade,

    [string]$InstallPath = 'C:\CyberButler',
    [string]$OwnerQQ = '',

    [string]$InstallLocalModel = '',
    [ValidateSet('Auto', 'None', 'Existing', 'Install')]
    [string]$OllamaMode = 'Auto',
    [string]$ModelName = '',

    [ValidateSet('Loopback', 'Tailscale', 'LAN')]
    [string]$WebUIBind = '',
    [switch]$EnableTailscaleServe,

    [string]$ServiceAccountName = 'CyberButlerSvc',
    [Security.SecureString]$ServiceAccountPassword = $null,
    [switch]$UseExistingServiceAccount,

    [string]$AgentRuntimeAccount = '',
    [string]$DesktopAccount = '',
    [string]$TotpReaderAccount = 'BUILTIN\Administrators',

    [string]$DataPath = '',
    [string]$WorkspacePath = '',

    [int]$AgentRuntimePort = 6185,
    [int]$BrokerPort = 18090,
    [int]$WebUIPort = 8765,
    [int]$OtpMailerPort = 8766,

    [object]$ApiKey = $null,
    [object]$SmtpSecret = $null,
    [string]$ApiKeyFile = '',
    [string]$WebUIAdminEmail = 'owner@example.com',
    [string]$SmtpHost = 'smtp.163.com',
    [int]$SmtpPort = 465,
    [string]$SmtpUser = '',

    [string]$AgentRuntimePackage = '',
    [string]$AuxRuntimeApplicationPackage = '',
    [string]$AgentRuntimeSha256 = '',
    [string]$AuxRuntimeApplicationSha256 = '',
    [string]$CoreSourcesPath = '',
    [string]$PythonPackage = '',
    [string]$PythonSha256 = '',
    [string]$PersonalPluginsPath = '',
    [int]$StartupTimeoutSeconds = 180,
    [switch]$SkipDependencyInstall,
    [int]$DownloadTimeoutSeconds = 300,
    [int]$DownloadRetryCount = 3,
    [switch]$ResumeDownload,

    [switch]$Scanned,
    [switch]$RecoverySaved,

    [switch]$PlanOnly,
    [switch]$NonInteractive,
    [switch]$GuiMode,
    [string]$GuiSignalDirectory = '',
    [switch]$SkipSecrets,
    [switch]$SkipSmtp,
    [switch]$Resume,
    [switch]$Repair,
    [switch]$Rollback,

    [string]$JournalRoot = '',
    [string]$ReportDirectory = '',
    [string]$LogPath = '',
    [string]$StatePath = '',

    [hashtable]$Handlers = @{},
    [hashtable]$RollbackHandlers = @{},
    [hashtable]$ApprovalTokens = @{},
    [string]$TestConfigPath = ''
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object Text.UTF8Encoding($false)
[Console]::OutputEncoding = $utf8NoBom
$OutputEncoding = $utf8NoBom
$installerMutex = New-Object System.Threading.Mutex($false, 'Local\CyberButlerInstaller')
if (-not $installerMutex.WaitOne(0)) {
    throw 'Another Cyber-Butler installer instance is already running on this machine.'
}
if (-not $Resume -and $ReportDirectory -and (Test-Path -LiteralPath (Join-Path $ReportDirectory 'install-report.json'))) {
    $previousReport = Join-Path $ReportDirectory ('install-report.previous-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.json')
    try { Move-Item -LiteralPath (Join-Path $ReportDirectory 'install-report.json') -Destination $previousReport -Force } catch { Write-Verbose 'optional operation failed' }
}
$installerRoot = $PSScriptRoot
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Tier.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Preflight.ps1')
. (Join-Path $installerRoot 'lib\Installer.Upgrade.ps1')
. (Join-Path $installerRoot 'lib\Installer.Accounts.ps1')
. (Join-Path $installerRoot 'lib\Installer.Acl.ps1')
. (Join-Path $installerRoot 'lib\Installer.Firewall.ps1')
. (Join-Path $installerRoot 'lib\Installer.Totp.ps1')
. (Join-Path $installerRoot 'lib\Installer.Secrets.ps1')
. (Join-Path $installerRoot 'lib\Installer.Services.ps1')
. (Join-Path $installerRoot 'lib\Installer.Diagnostics.ps1')
. (Join-Path $installerRoot 'lib\Installer.Report.ps1')
. (Join-Path $installerRoot 'lib\Installer.Features.ps1')
. (Join-Path $installerRoot 'lib\Installer.Core.ps1')
. (Join-Path $installerRoot 'lib\Installer.Python.ps1')

if (-not [string]::IsNullOrWhiteSpace($TestConfigPath)) {
    if (-not (Test-Path -LiteralPath $TestConfigPath)) { throw "TestConfigPath not found: $TestConfigPath" }
    $testConfig = & $TestConfigPath
    if ($testConfig.Handlers) { $Handlers = $testConfig.Handlers }
    if ($testConfig.ApprovalTokens) { $ApprovalTokens = $testConfig.ApprovalTokens }
    if ($testConfig.RollbackHandlers) { $RollbackHandlers = $testConfig.RollbackHandlers }
    if ($testConfig.ApiKey) { $ApiKey = $testConfig.ApiKey }
    if ($testConfig.SmtpSecret) { $SmtpSecret = $testConfig.SmtpSecret }
}

if (-not $SmtpSecret -and $env:CB_SMTP_AUTH_CODE) {
    $SmtpSecret = $env:CB_SMTP_AUTH_CODE
}

if ($GuiMode) {
    $guiEmail = ([string]$WebUIAdminEmail).Trim()
    if ($guiEmail -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        Write-InstallerLine 'GUI validation failed: a valid WebUI admin email is required.' -Level ERROR
        exit (Get-InstallerExitCode -Name ValidationFailed)
    }
    if (-not $env:CB_SMTP_AUTH_CODE -and (Test-CyberButlerSecureStringEmpty $SmtpSecret)) {
        Write-InstallerLine 'GUI validation failed: SMTP auth code is required for WebUI email approval.' -Level ERROR
        exit (Get-InstallerExitCode -Name ValidationFailed)
    }
}

try {
    $ApiKey = ConvertTo-CyberButlerSecureString -Value $ApiKey
    $SmtpSecret = ConvertTo-CyberButlerSecureString -Value $SmtpSecret
} catch {
    Write-InstallerLine ('Invalid secret parameter: ' + $_.Exception.Message) -Level ERROR
    exit (Get-InstallerExitCode -Name ValidationFailed)
}

function Add-MainJournalStep {
    param($Journal, [string]$Name, [string]$Status, [string]$Reason = '')
    if ($null -eq $Journal) { return }
    Add-CyberButlerJournalStep -Journal $Journal -Name $Name -Status $Status -Details ([pscustomobject]@{ reason = $Reason }) | Out-Null
}

function Test-MainStepDone {
    param($Journal, [string]$Name)
    if ($null -eq $Journal) { return $false }
    $step = Get-CyberButlerJournalStep -Journal $Journal -Name $Name
    return ($null -ne $step -and [string]$step.status -in @('completed', 'skipped'))
}

function Add-MainApproval {
    param($Approvals, [string]$Token, [string]$Step)
    [void]$Approvals.Add([pscustomobject]@{ token = $Token; step = $Step; at = Get-InstallerUtcTimestamp })
}

<#
.SYNOPSIS
    Request-MainApproval performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Request-MainApproval {
    param(
        [string]$Token,
        [string]$Step,
        [hashtable]$ApprovalTokens,
        $Approvals,
        [switch]$NonInteractive
    )
    if ($ApprovalTokens.ContainsKey($Token) -and [string]$ApprovalTokens[$Token] -ceq $Token) {
        Add-MainApproval -Approvals $Approvals -Token $Token -Step $Step
        return $true
    }
    if ($NonInteractive) { return $false }
    if (-not (Test-CyberButlerInteractiveStdin)) {
        Write-Host 'stdin is not interactive; run from an interactive console or pass -NonInteractive and approval tokens.'
        return $false
    }
    $answer = Read-Host ("Type {0} to approve {1}" -f $Token, $Step)
    if ($answer -ceq $Token) {
        Add-MainApproval -Approvals $Approvals -Token $Token -Step $Step
        return $true
    }
    Write-InstallerLine ("Approval token did not match for {0}." -f $Token) -Level BLOCKING
    return $false
}

<#
.SYNOPSIS
    Request-MainConfirmation performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Request-MainConfirmation {
    param(
        [string]$Token,
        [string]$Step,
        [bool]$AlreadyConfirmed,
        [hashtable]$ApprovalTokens,
        $Approvals,
        [switch]$NonInteractive
    )
    if ($AlreadyConfirmed) {
        Add-MainApproval -Approvals $Approvals -Token $Token -Step $Step
        return $true
    }
    if ($ApprovalTokens.ContainsKey($Token) -and [string]$ApprovalTokens[$Token] -ceq $Token) {
        Add-MainApproval -Approvals $Approvals -Token $Token -Step $Step
        return $true
    }
    if ($NonInteractive) { return $false }
    if (-not (Test-CyberButlerInteractiveStdin)) {
        Write-Host 'stdin is not interactive; run from an interactive console or pass -NonInteractive and approval tokens.'
        return $false
    }
    $answer = Read-Host ("Type {0} to confirm {1}" -f $Token, $Step)
    if ($answer -ceq $Token) {
        Add-MainApproval -Approvals $Approvals -Token $Token -Step $Step
        return $true
    }
    return $false
}

function Write-MainReport {
    param(
        [string]$Status,
        $Diagnostics,
        $Journal,
        $Approvals,
        $Steps,
        $Failure,
        [string]$Message,
        [string]$ReportDirectory,
        [string]$Tier,
        [string]$EffectiveTier,
        [bool]$Isolation,
        [hashtable]$Handlers
    )
    $model = New-CyberButlerReportModel -Tier $Tier -EffectiveTier $EffectiveTier -Isolation $Isolation `
        -Status $Status -Diagnostics $Diagnostics -Steps $Steps -Approvals $Approvals `
        -Journal $Journal -Failure $Failure -Message $Message
    return (Write-CyberButlerReport -OutputDirectory $ReportDirectory -Report $model -Handlers $Handlers)
}

function Invoke-MainFailureRollback {
    param($Journal, [hashtable]$RollbackHandlers)
    if ($null -eq $Journal) {
        return [pscustomobject]@{ status = 'no-journal'; executed = @(); errors = @() }
    }
    try { return (Invoke-CyberButlerRollback -Journal $Journal -Handlers $RollbackHandlers) } catch { Write-Output ('INNER ERROR: ' + $_.Exception.Message + ' AT ' + $_.InvocationInfo.PositionMessage); throw }
}

# Rollback mode is a direct journal operation and does not run the pipeline.
if ($Rollback) {
    if ([string]::IsNullOrWhiteSpace($StatePath) -or -not (Test-Path -LiteralPath $StatePath)) {
        Write-InstallerLine 'StatePath must point to an existing journal state.json for -Rollback.' -Level ERROR
        exit (Get-InstallerExitCode -Name ValidationFailed)
    }
    $journal = Read-CyberButlerJournal -StatePath $StatePath
    $rollbackResultResult = Invoke-CyberButlerRollback -Journal $journal -Handlers $RollbackHandlers
    Write-Output ('ROLLBACK ' + $rollbackResultResult.status + ' actions=' + $rollbackResultResult.executed.Count + ' errors=' + $rollbackResultResult.errors.Count)
    foreach ($errorLine in $rollbackResultResult.errors) { Write-InstallerLine $errorLine -Level ERROR }
    if ($rollbackResultResult.status -eq 'rollback_failed') { exit (Get-InstallerExitCode -Name RollbackFailed) }
    exit (Get-InstallerExitCode -Name Success)
}

$isolationValue = $null
if (-not [string]::IsNullOrWhiteSpace($EnableIsolation)) {
    switch ($EnableIsolation.ToLowerInvariant()) {
        'true'  { $isolationValue = $true }
        'false' { $isolationValue = $false }
        default {
            Write-InstallerLine "EnableIsolation must be true or false; got: $EnableIsolation" -Level ERROR
            exit (Get-InstallerExitCode -Name ValidationFailed)
        }
    }
}

try {
$failure = $null
$resolution = Resolve-CyberButlerTier `
    -Tier $Tier `
    -EnableIsolation $isolationValue `
    -AcceptLowerSecurity:$AcceptLowerSecurity `
    -AllowSecurityDowngrade:$AllowSecurityDowngrade `
    -ProfileRoot (Join-Path $installerRoot 'profiles') `
    -InstallPath $InstallPath `
    -WebUIBind $WebUIBind `
    -EnableTailscaleServe:$EnableTailscaleServe `
    -OwnerQQ $OwnerQQ `
    -AgentRuntimePort $AgentRuntimePort `
    -BrokerPort $BrokerPort `
    -WebUIPort $WebUIPort `
    -OtpMailerPort $OtpMailerPort

if ($resolution.Errors.Count -gt 0) {
    Write-Output $resolution.PlanText
    exit (Get-InstallerExitCode -Name ValidationFailed)
}

$featureResolution = Resolve-CyberButlerFeatures `
    -Tier $Tier `
    -FeatureIds $FeatureIds `
    -ApprovalChannel $ApprovalChannel `
    -AcceptBelowMinimum:$AcceptBelowMinimum `
    -Fields @{ OwnerQQ = $OwnerQQ; WebUIAdminEmail = $WebUIAdminEmail; SmtpHost = $SmtpHost; SmtpPort = [string]$SmtpPort; SmtpUser = $SmtpUser; SmtpAuthCode = [string]$SmtpSecret } `
    -ManifestPath (Join-Path $installerRoot 'features.v1.json')
if ($featureResolution.Errors.Count -gt 0) {
    Write-Output ('FEATURE_ERRORS: ' + ($featureResolution.Errors -join '; '))
    exit (Get-InstallerExitCode -Name ValidationFailed)
}
$script:CyberButlerFeatureResolution = $featureResolution
if ($featureResolution.SecurityFloorWaived) {
    Write-InstallerLine ('SecurityFloorWaived: ' + ($featureResolution.SecurityFloor.missing -join ', ')) -Level WARNING
}

if ([string]::IsNullOrWhiteSpace($AgentRuntimeAccount)) {
    $AgentRuntimeAccount = if ($resolution.Isolation) { $ServiceAccountName } else { [Security.Principal.WindowsIdentity]::GetCurrent().Name }
}
$currentDesktopUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$desktopLeaf = if ($DesktopAccount) { ($DesktopAccount -split '[\/]')[-1] } else { '' }
$serviceLeaf = ($ServiceAccountName -split '[\/]')[-1]
if ([string]::IsNullOrWhiteSpace($DesktopAccount) -or $desktopLeaf -ieq $serviceLeaf -or $DesktopAccount -match '^NT AUTHORITY\SYSTEM$') {
    $DesktopAccount = $currentDesktopUser
}
if ([string]::IsNullOrWhiteSpace($DesktopAccount)) {
    throw 'DesktopAccount could not be resolved; refusing to grant broker token ACL.'
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
        Join-Path $env:ProgramData 'CyberButler\installer-report'
    } else {
        Join-Path $env:LOCALAPPDATA 'CyberButler\installer-report'
    }
}

$preflight = Get-CyberButlerPreflight -InstallPath $InstallPath -Handlers $Handlers
if (@($preflight.blocking).Count -gt 0) {
    Write-Output ('PREFLIGHT_BLOCKING admin={0} existing={1} ports={2}' -f $preflight.admin.is_admin, $preflight.install_path.existing_state, $preflight.ports.Count)
    foreach ($block in @($preflight.blocking)) {
        Write-Output ('BLOCKING ' + $block.id + ': ' + $block.message)
        if ($block.action) { Write-Output ('MANUAL ' + $block.action) }
    }
    exit (Get-InstallerExitCode -Name ValidationFailed)
}
$packageVersionPath = Join-Path $installerRoot 'VERSION'
$packageVersion = if (Test-Path -LiteralPath $packageVersionPath) { (Get-Content -LiteralPath $packageVersionPath -Raw -Encoding UTF8).Trim() } else { '0.0.0' }
$installedVersion = Get-CyberButlerInstalledVersion -InstallPath $InstallPath
$upgradePath = Test-CyberButlerUpgradePath -PackageVersion $packageVersion -InstalledVersion ([string]$installedVersion)
if ($upgradePath.status -eq 'blocked') {
    Write-Output ('UPGRADE_BLOCKED ' + $upgradePath.message)
    Write-InstallerLine ('升级被阻断 / Upgrade blocked: ' + $upgradePath.message) -Level ERROR
    exit (Get-InstallerExitCode -Name ValidationFailed)
}
if ($upgradePath.status -eq 'migration_required') {
    Write-Output ('UPGRADE_MIGRATION_REQUIRED installed=' + [string]$installedVersion + ' package=' + $packageVersion)
    $backupScript = Join-Path $installerRoot 'Backup-CyberButler.ps1'
    $backupDir = Join-Path (Join-Path $env:ProgramData 'CyberButler') 'upgrade-backups'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $backupPath = Join-Path $backupDir ('v1.6.2-preupgrade-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
    try {
        $backup = & $backupScript -InstallPath $InstallPath -OutputPath $backupPath -Force
        Write-Output ('UPGRADE_BACKUP ' + $backup.path + ' sha256=' + $backup.sha256)
        Write-InstallerLine ('已自动备份旧数据：' + $backup.path) -Level INFO
    } catch {
        Write-Output ('UPGRADE_BACKUP_FAILED ' + $_.Exception.Message)
        Write-InstallerLine ('旧数据备份失败，升级中止：' + $_.Exception.Message) -Level ERROR
        exit (Get-InstallerExitCode -Name ValidationFailed)
    }
    Write-Output ('UPGRADE_RUN_MIGRATION powershell -File "' + (Join-Path $installerRoot 'Migrate-v1.6.2-to-v1.6.3.ps1') + '" -InstallPath "' + $InstallPath + '"')
    Write-InstallerLine '请先运行 Migrate-v1.6.2-to-v1.6.3.ps1 完成解耦迁移，再重新运行本安装器。' -Level ERROR
    exit (Get-InstallerExitCode -Name ValidationFailed)
}
$pythonPath = if ($preflight.python_needs_bundle) { $null } else { [string]$preflight.python_resolved_path }
$pythonBlocking = @($preflight.blocking | Where-Object { $_.id -eq 'python' }).Count -gt 0
if ($preflight.python_needs_bundle -or -not $preflight.python_usable -or $pythonBlocking) {
    foreach ($line in @(
        'Install Python 3.10-3.13 and add it to PATH before running this installer.',
        'Python 3.14+ is not supported by faiss-cpu; use Python 3.13 for this AgentRuntime release.',
        'Supply -PythonPackage <path> for offline Python installation.'
    )) {
        if (-not $resolution.ManualSteps.Contains($line)) { $resolution.ManualSteps.Add($line) }
    }
    $resolution.PlanText = Format-CyberButlerPlan -Resolution $resolution
}

if ($PlanOnly) {
    Write-Output ('PREFLIGHT admin={0} existing={1} ports={2}' -f $preflight.admin.is_admin, $preflight.install_path.existing_state, $preflight.ports.Count)
    Write-Output $resolution.PlanText
    if ($preflight.python_needs_bundle) {
        $tooNew = @($preflight.python | Where-Object { $_.version_too_new -eq $true })
        if ($tooNew.Count -gt 0) {
            Write-Output ('System Python is 3.14+; installer will download Python 3.13 into ' + $preflight.python_target_path + '.')
        } else {
            Write-Output ('No compatible system Python was found; installer will download Python 3.13 into ' + $preflight.python_target_path + '.')
        }
        Write-Output 'Supply -PythonPackage <path> for offline installation.'
    }
    exit (Get-InstallerExitCode -Name Success)
}

if ($Repair) {
    $diagnostics = Get-CyberButlerDiagnostics -Tier $resolution.Tier -EffectiveTier $resolution.EffectiveLabel `
        -Isolation $resolution.Isolation -Root $InstallPath -ServiceAccount $ServiceAccountName `
        -TotpReaderAccount $TotpReaderAccount -AgentRuntimeAccount $AgentRuntimeAccount -WebUIBind $resolution.WebUIBind -Handlers $Handlers
    $report = Write-MainReport -Status 'repair' -Diagnostics $diagnostics -Journal $null -Approvals @() `
        -Steps @() -Failure $null -Message 'Repair mode runs diagnostics only.' -ReportDirectory $ReportDirectory `
        -Tier $resolution.Tier -EffectiveTier $resolution.EffectiveLabel -Isolation $resolution.Isolation -Handlers $Handlers
    Write-Output ('REPORT ' + $report.json)
    exit (Get-InstallerExitCode -Name Success)
}

$journal = $null
if ($Resume) {
    if (-not [string]::IsNullOrWhiteSpace($StatePath)) {
        if (-not (Test-Path -LiteralPath $StatePath)) {
            Write-InstallerLine "Resume state not found: $StatePath" -Level ERROR
            exit (Get-InstallerExitCode -Name ValidationFailed)
        }
        $journal = Read-CyberButlerJournal -StatePath $StatePath
    } else {
        $candidate = Get-ChildItem -LiteralPath $JournalRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending |
            ForEach-Object { Join-Path $_.FullName 'state.json' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if (-not $candidate) {
            Write-InstallerLine 'No journal state found for -Resume.' -Level ERROR
            exit (Get-InstallerExitCode -Name ValidationFailed)
        }
        $journal = Read-CyberButlerJournal -StatePath $candidate
    }

    $mainNames = @('preflight', 'plan', 'python', 'core', 'accounts', 'acl', 'firewall', 'totp', 'secrets', 'services', 'diagnostics', 'report')
    $hasMainStep = @($journal.State.steps | Where-Object { $mainNames -contains [string]$_.name }).Count -gt 0
    if (-not $hasMainStep) {
        $resumeStep = Get-CyberButlerResumeStep -Journal $journal
        if ($null -eq $resumeStep) { Write-Output 'RESUME no_unfinished_step' }
        else { Write-Output ('RESUME next=' + $resumeStep.name + ' status=' + $resumeStep.status) }
        exit (Get-InstallerExitCode -Name Success)
    }
} else {
    $journal = New-CyberButlerJournal -Root $JournalRoot -InstallPath $InstallPath -Tier $resolution.Tier -Isolation $resolution.Isolation
}

$approvals = New-Object System.Collections.Generic.List[object]
$diagnostics = $null
$failure = $null

# Preflight (already executed before plan/approval)
if (-not (Test-MainStepDone -Journal $journal -Name 'preflight')) {
    Add-MainJournalStep -Journal $journal -Name 'preflight' -Status 'completed' -Reason ('existing=' + $preflight.install_path.existing_state)
}
Write-Output ('PREFLIGHT admin={0} existing={1} ports={2}' -f $preflight.admin.is_admin, $preflight.install_path.existing_state, $preflight.ports.Count)

# Plan approval
if (-not (Test-MainStepDone -Journal $journal -Name 'plan')) {
    if (-not (Request-MainApproval -Token 'APPROVE PLAN' -Step 'plan' -ApprovalTokens $ApprovalTokens -Approvals $approvals -NonInteractive:$NonInteractive)) {
        Add-MainJournalStep -Journal $journal -Name 'plan' -Status 'failed' -Reason 'needs approval'
        Write-InstallerLine 'Interactive approval is required.' -Level BLOCKING
        $planFailure = [pscustomobject]@{ step = 'plan'; message = 'APPROVE PLAN required'; kind = 'needs_approval' }
        try {
            $report = Write-MainReport -Status 'needs_approval' -Diagnostics $null -Journal $journal -Approvals $approvals `
                -Steps @($journal.State.steps) -Failure $planFailure `
                -Message 'Install plan is waiting for approval.' -ReportDirectory $ReportDirectory `
                -Tier $resolution.Tier -EffectiveTier $resolution.EffectiveLabel -Isolation $resolution.Isolation -Handlers $Handlers
            Write-Output ('REPORT ' + $report.json)
        } catch {
            Write-InstallerLine ('Report not written: ' + $_.Exception.Message) -Level ERROR
        }
        exit (Get-InstallerExitCode -Name NeedsApproval)
    }
    Add-MainJournalStep -Journal $journal -Name 'plan' -Status 'completed'
}

$coreResult = $null
$pythonSource = if ($preflight.python_source) { [string]$preflight.python_source } else { 'system' }
$pythonVersion = if ($preflight.python_resolved_version) { [string]$preflight.python_resolved_version } else { '' }

$coreJournalDone = Test-MainStepDone -Journal $journal -Name 'core'
# In handler-driven tests the core tree is simulated; do not inspect the real
# filesystem there. Production installs have no handlers.
$coreTree = if ($TestConfigPath) {
    [pscustomobject]@{ satisfied = $true; missing = @() }
} else {
    Test-CyberButlerCoreDeploy -InstallPath $InstallPath -Features $featureResolution.FeatureIds
}
$coreNeedsDeploy = (-not $coreJournalDone) -or (-not $coreTree.satisfied)
if ($coreNeedsDeploy) {
    if ($coreJournalDone -and -not $coreTree.satisfied) {
        Write-Output ('CORE invalid despite journal; missing: ' + (($coreTree.missing | Select-Object -First 8) -join ', '))
    }
    $pythonStep = Get-CyberButlerJournalStep -Journal $journal -Name 'python'
    if ($preflight.python_needs_bundle) {
        $reusePython = $null
        if ($pythonStep -and [string]$pythonStep.status -eq 'completed' -and $pythonStep.details.python_path -and (Test-Path -LiteralPath ([string]$pythonStep.details.python_path))) {
            $reusePython = $pythonStep
            $pythonPath = [string]$pythonStep.details.python_path
            $pythonSource = 'bundled'
            $pythonVersion = [string]$pythonStep.details.python_version
            Write-Output ('PYTHON reuse ' + $pythonPath)
        }
        if (-not $reusePython) {
            Write-Output 'PYTHON bootstrap required'
            $pythonResult = Invoke-CyberButlerPythonBootstrap -InstallPath $InstallPath -PythonPackage $PythonPackage -PythonSha256 $PythonSha256 -CoreSourcesPath $CoreSourcesPath -DownloadTimeoutSeconds $DownloadTimeoutSeconds -DownloadRetryCount $DownloadRetryCount -Journal $journal -JournalStep 'python' -Handlers $Handlers
            Write-Output ('PYTHON ' + [string]$pythonResult.status)
            if ([string]$pythonResult.status -in @('completed', 'skipped')) {
                $pythonPath = [string]$pythonResult.python_path
                $pythonSource = if ($pythonResult.python_source) { [string]$pythonResult.python_source } else { 'bundled' }
                $pythonVersion = [string]$pythonResult.python_version
                if (-not (Get-CyberButlerJournalStep -Journal $journal -Name 'python')) {
                    Add-MainJournalStep -Journal $journal -Name 'python' -Status 'completed' -Reason ([string]$pythonResult.reason)
                }
            } elseif ([string]$pythonResult.reason -eq 'sha_mismatch') {
                $failure = [pscustomobject]@{ step = 'python'; message = ('python_bootstrap_failed: ' + [string]$pythonResult.message); kind = 'security' }
            } else {
                $fallback = @($preflight.python | Where-Object { $_.version_ok -eq $true -and [string]$_.python_source -ne 'bundled' } | Select-Object -First 1)
                if ($fallback) {
                    $pythonPath = [string]$fallback.path
                    $pythonSource = 'system'
                    $pythonVersion = [string]$fallback.version
                    Add-MainJournalStep -Journal $journal -Name 'python' -Status 'completed' -Reason 'bootstrap failed; using system Python fallback'
                    Write-Output ('PYTHON fallback system ' + $pythonPath)
                } else {
                    $failure = [pscustomobject]@{ step = 'python'; message = ('python_bootstrap_failed: ' + [string]$pythonResult.message); kind = 'configuration' }
                }
            }
        }
    } else {
        $pythonSource = [string]$preflight.python_source
        $pythonVersion = [string]$preflight.python_resolved_version
        if (-not $pythonPath) { $pythonPath = [string]$preflight.python_resolved_path }
        if (-not (Get-CyberButlerJournalStep -Journal $journal -Name 'python')) {
            Add-MainJournalStep -Journal $journal -Name 'python' -Status 'skipped' -Reason ('system Python selected: ' + $pythonPath)
        }
        Write-Output ('PYTHON system ' + $pythonPath)
    }
}

# Existing installs must be stopped before Core replaces locked binaries.
if (-not $failure -and $coreNeedsDeploy -and [string]$preflight.install_path.existing_state -ne 'None') {
    Write-Output ('STOP existing services before core: ' + [string]$preflight.install_path.existing_state)
    foreach ($taskName in @('Cyber-Butler Broker','Cyber-Butler Web UI Services','Cyber-Butler OTP Mailer','Cyber-Butler WFP Guard','Cyber-Butler Broker Watchdog')) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) { Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue | Out-Null }
    }
    $stoppedBeforeCore = @(Stop-CyberButlerInstallProcesses -Root $InstallPath -Ports @(18090,8765,8766,6199,3000,3001))
    Write-Output ('STOP core-lock processes: ' + (($stoppedBeforeCore | ForEach-Object { [string]$_ }) -join ','))
    Start-Sleep -Seconds 3
}

# Core deploy: real download/verify/extract/venv/overlay.
if (-not $failure -and $coreNeedsDeploy) {
    Write-Output ('CORE start existing=' + $preflight.install_path.existing_state)
    $coreResult = Invoke-CyberButlerCoreDeploy -InstallPath $InstallPath `
        -ExistingState $preflight.install_path.existing_state -Tier $resolution.Tier `
        -Features $featureResolution.FeatureIds `
        -AgentRuntimePackage $AgentRuntimePackage -AuxRuntimeApplicationPackage $AuxRuntimeApplicationPackage `
        -AgentRuntimeSha256 $AgentRuntimeSha256 -AuxRuntimeApplicationSha256 $AuxRuntimeApplicationSha256 `
        -CoreSourcesPath $CoreSourcesPath -SkipDependencyInstall:$SkipDependencyInstall `
        -DownloadTimeoutSeconds $DownloadTimeoutSeconds -DownloadRetryCount $DownloadRetryCount -ResumeDownload:$ResumeDownload -PythonPath $pythonPath -PythonSource $pythonSource -PythonVersion $pythonVersion -PipLogPath (Join-Path $ReportDirectory 'pip-install.log') `
        -PersonalPluginsPath $PersonalPluginsPath `
        -OwnerQQ $OwnerQQ -ToolServiceAccount $AgentRuntimeAccount -ToolDesktopAccount $DesktopAccount `
        -WebUIAdminEmail $WebUIAdminEmail `
        -Repair:($Repair -or ($coreJournalDone -and -not $coreTree.satisfied)) `
        -Journal $journal -JournalStep 'core' -Handlers $Handlers
    Write-Output ('CORE ' + [string]$coreResult.status)
    if ([string]$coreResult.status -eq 'failed') {
        $failure = [pscustomobject]@{ step = 'core'; message = ('core: ' + [string]$coreResult.message) }
    } elseif (-not (Get-CyberButlerJournalStep -Journal $journal -Name 'core')) {
        $coreReason = if ($coreResult.reason) { [string]$coreResult.reason } elseif ([string]$coreResult.status -eq 'skipped') { 'core deployment already satisfied' } else { 'core deployment completed' }
        Add-MainJournalStep -Journal $journal -Name 'core' -Status $(if ([string]$coreResult.status -eq 'skipped') { 'skipped' } else { 'completed' }) -Reason $coreReason
    }
    if (-not $failure -and -not $SkipDependencyInstall) {
        $webPython = Join-Path $InstallPath 'webui\.venv\Scripts\python.exe'
        if (Test-Path -LiteralPath $webPython) {
            $depProbe = Test-CyberButlerCbsPythonDependencies -PythonPath $webPython
            if (-not $depProbe.ok) {
                $failure = [pscustomobject]@{
                    step = 'core_dependencies'
                    message = ('CBS Python 依赖未安装完成，已中止，未进入 TOTP：' + [string]$depProbe.reason)
                    kind = 'configuration'
                }
                Write-Output 'CORE_DEPENDENCIES missing; stopping before TOTP'
            }
        }
    }
    if ($coreResult -and [string]$coreResult.personal_plugins_status -eq 'failed') {
        Add-MainJournalStep -Journal $journal -Name 'personal_plugins' -Status 'failed' -Reason ([string]$coreResult.personal_plugins_error)
        Write-Output ('PERSONAL plugins failed: ' + [string]$coreResult.personal_plugins_error)
    }
} else {
    Write-Output 'CORE skipped: resumed, core already completed'
    $coreStep = Get-CyberButlerJournalStep -Journal $journal -Name 'core'
    if ($coreStep -and [string]$coreStep.details.personal_plugins_status -eq 'failed' -and -not (Get-CyberButlerJournalStep -Journal $journal -Name 'personal_plugins')) {
        Add-MainJournalStep -Journal $journal -Name 'personal_plugins' -Status 'failed' -Reason ([string]$coreStep.details.personal_plugins_error)
    }
}

$aclIdentity = if ($resolution.Isolation) { $ServiceAccountName } else { [Security.Principal.WindowsIdentity]::GetCurrent().Name }
$aclRoot = $InstallPath
$toolsPath = Join-Path $aclRoot 'tools'
$aclPaths = @(Get-CyberButlerAclTargets -InstallPath $aclRoot)
$vaultPath = Join-Path $toolsPath 'totp-vault'
$pythonAclPath = Join-Path $aclRoot '.python'
if (Test-Path -LiteralPath $pythonAclPath) { $aclPaths = @($aclPaths) + $pythonAclPath }

function Complete-MainSecurityStep {
    param([string]$Name, $Result)
    if ([string]$Result.status -eq 'completed' -or [string]$Result.status -eq 'skipped' -or [string]$Result.status -eq 'unsupported') {
        $finalStatus = if ([string]$Result.status -eq 'unsupported') { 'skipped' } else { [string]$Result.status }
        Add-MainJournalStep -Journal $journal -Name $Name -Status $finalStatus -Reason ([string]$Result.message)
        return $true
    }
    return $false
}

$taskServiceAccountPassword = ''

# Accounts: only needed when isolation is enabled and core succeeded.
if (-not $failure -and $resolution.Isolation) {
    $accountTest = Test-CyberButlerAccount -AccountName $ServiceAccountName
    $accountNeedsSetup = if ($TestConfigPath) { -not (Test-MainStepDone -Journal $journal -Name 'accounts') } else { -not $accountTest.satisfied }
    if ($accountNeedsSetup) {
        Write-Output ('ACCOUNT setup required: exists=' + [string]$accountTest.exists + ' reason=' + [string]$accountTest.reason)
        if (-not (Request-MainApproval -Token 'APPROVE ACCOUNT' -Step 'accounts' -ApprovalTokens $ApprovalTokens -Approvals $approvals -NonInteractive:$NonInteractive)) {
            Add-MainJournalStep -Journal $journal -Name 'accounts' -Status 'failed' -Reason 'needs approval'
            $failure = [pscustomobject]@{ step = 'accounts'; message = 'APPROVE ACCOUNT required'; kind = 'needs_approval' }
        } else {
            Add-MainJournalStep -Journal $journal -Name 'accounts' -Status 'in_progress'
            $result = Invoke-CyberButlerAccountSetup -AccountName $ServiceAccountName -JournalStep 'accounts' -Journal $journal -Approval 'APPROVE ACCOUNT' -NonInteractive:$NonInteractive -Handlers $Handlers
            if (-not (Complete-MainSecurityStep -Name 'accounts' -Result $result)) {
                if ([string]$result.status -in @('needs_approval', 'needs_confirmation')) {
                    $failure = [pscustomobject]@{ step = 'accounts'; message = [string]$result.message; kind = 'needs_approval' }
                } else {
                    $failure = [pscustomobject]@{ step = 'accounts'; message = ('account setup: ' + [string]$result.status + ' ' + [string]$result.message) }
                }
            } elseif ($result.password) {
                $taskServiceAccountPassword = [string]$result.password
            }
        }
    }
} else {
    Add-MainJournalStep -Journal $journal -Name 'accounts' -Status 'skipped' -Reason 'single-account tier'
}

if (-not $failure -and $resolution.Isolation -and -not $TestConfigPath) {
    $accountReady = Test-CyberButlerAccount -AccountName $ServiceAccountName
    if (-not $accountReady.satisfied) {
        $failure = [pscustomobject]@{ step = 'accounts'; message = ('service account not ready: ' + [string]$accountReady.reason); kind = 'configuration' }
    }
}

if (-not $failure -and -not (Test-MainStepDone -Journal $journal -Name 'acl')) {
    if (-not (Request-MainApproval -Token 'APPROVE ACL' -Step 'acl' -ApprovalTokens $ApprovalTokens -Approvals $approvals -NonInteractive:$NonInteractive)) {
        Add-MainJournalStep -Journal $journal -Name 'acl' -Status 'failed' -Reason 'needs approval'
        $failure = [pscustomobject]@{ step = 'acl'; message = 'APPROVE ACL required'; kind = 'needs_approval' }
    } else {
        foreach ($aclTarget in $aclPaths) {
            if ($failure) { break }
            $aclMode = if ((Split-Path -Leaf $aclTarget) -ieq 'workspace') { 'RW' } else { 'RX' }
            $result = Invoke-CyberButlerAcl -Path $aclTarget -Identity $aclIdentity -Mode $aclMode -JournalStep 'acl' -Journal $journal -Approval 'APPROVE ACL' -NonInteractive:$NonInteractive -Handlers $Handlers
            if ([string]$result.status -notin @('completed', 'skipped')) {
                $failure = [pscustomobject]@{ step = 'acl'; message = ('ACL: ' + [string]$result.status + ' ' + [string]$result.message) }
            }
        }
        if (-not $failure -and $resolution.Isolation) {
            $testProtection = Protect-CyberButlerTestFiles -InstallPath $aclRoot -Identity $aclIdentity
            if ([string]$testProtection.status -ne 'completed' -and [string]$testProtection.status -ne 'skipped') {
                $failure = [pscustomobject]@{ step = 'acl'; message = ('ACL test-file protection: ' + [string]$testProtection.reason) }
            }
        }
    }
}

# Harden tools/ and AgentRuntime/.venv before the TOTP vault deny ACE is applied.
if (-not $failure) {
    try {
        $brokerAcl = Invoke-CyberButlerBrokerAclHardening -Root $aclRoot -ServiceUser $AgentRuntimeAccount -DesktopUser $DesktopAccount -Handlers $Handlers
        Add-MainJournalStep -Journal $journal -Name 'broker_acl' -Status ([string]$brokerAcl.status) -Reason ([string]$brokerAcl.reason)
        if ([string]$brokerAcl.status -eq 'failed') {
            Write-InstallerLine ('Broker ACL 加固警告，继续安装：' + [string]$brokerAcl.message) -Level WARN
        }
    } catch {
        Add-MainJournalStep -Journal $journal -Name 'broker_acl' -Status 'warning' -Reason $_.Exception.Message
        Write-InstallerLine ('Broker ACL 加固失败，继续安装：' + $_.Exception.Message) -Level WARN
    }
}

$totpScanned = $Scanned.IsPresent
$totpRecovery = $RecoverySaved.IsPresent
if (-not $failure -and -not (Test-MainStepDone -Journal $journal -Name 'totp')) {
    if (-not (Request-MainApproval -Token 'APPROVE TOTP' -Step 'totp' -ApprovalTokens $ApprovalTokens -Approvals $approvals -NonInteractive:$NonInteractive)) {
        Add-MainJournalStep -Journal $journal -Name 'totp' -Status 'failed' -Reason 'needs approval'
        $failure = [pscustomobject]@{ step = 'totp'; message = 'APPROVE TOTP required'; kind = 'needs_approval' }
    } else {
        try {
            $totpPrepared = Show-CyberButlerTotpEnrollment -Root $InstallPath -VaultPath $vaultPath -Issuer 'Cyber-Butler' -Account $OwnerQQ -SuppressSecrets:$GuiMode -Handlers $Handlers
        } catch {
            Add-MainJournalStep -Journal $journal -Name 'totp' -Status 'failed' -Reason ('material generation failed: ' + $_.Exception.Message)
            $failure = [pscustomobject]@{ step = 'totp'; message = ('TOTP material generation failed: ' + $_.Exception.Message) }
        }
        if (-not $failure) {
            if ($GuiMode) {
                if ([string]::IsNullOrWhiteSpace($GuiSignalDirectory)) {
                    $failure = [pscustomobject]@{ step = 'totp'; message = 'GUI signal directory is required in GuiMode' }
                } else {
                    New-Item -ItemType Directory -Path $GuiSignalDirectory -Force | Out-Null
                    $readyPath = Join-Path $GuiSignalDirectory 'totp-ready.json'
                    $confirmPath = Join-Path $GuiSignalDirectory 'totp-confirm.json'
                    $ready = [pscustomobject]@{
                        status = 'ready'
                        qr_path = [string]$totpPrepared.qr_path
                        recovery_path = [string]$totpPrepared.recovery_path
                        at = Get-InstallerUtcTimestamp
                    }
                    $ready | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $readyPath -Encoding UTF8
                    $deadline = (Get-Date).AddMinutes(15)
                    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $confirmPath)) {
                        Start-Sleep -Seconds 1
                    }
                    if (-not (Test-Path -LiteralPath $confirmPath)) {
                        $failure = [pscustomobject]@{ step = 'totp'; message = 'GUI did not confirm TOTP enrollment within 15 minutes'; kind = 'needs_approval' }
                    } else {
                        try {
                            $confirmation = Get-Content -LiteralPath $confirmPath -Raw | ConvertFrom-Json
                            $totpScanned = [bool]$confirmation.scanned
                            $totpRecovery = [bool]$confirmation.recovery_saved
                        } catch {
                            $failure = [pscustomobject]@{ step = 'totp'; message = ('invalid TOTP GUI confirmation: ' + $_.Exception.Message) }
                        }
                    }
                }
            } else {
                $totpScanned = Request-MainConfirmation -Token 'SCANNED' -Step 'totp' -AlreadyConfirmed:$totpScanned -ApprovalTokens $ApprovalTokens -Approvals $approvals -NonInteractive:$NonInteractive
                $totpRecovery = Request-MainConfirmation -Token 'RECOVERY-SAVED' -Step 'totp' -AlreadyConfirmed:$totpRecovery -ApprovalTokens $ApprovalTokens -Approvals $approvals -NonInteractive:$NonInteractive
            }
            if (-not $failure -and (-not $totpScanned -or -not $totpRecovery)) {
                Add-MainJournalStep -Journal $journal -Name 'totp' -Status 'failed' -Reason 'needs scan/recovery confirmation'
                $failure = [pscustomobject]@{ step = 'totp'; message = 'SCANNED and RECOVERY-SAVED confirmation required'; kind = 'needs_approval' }
            }
            if (-not $failure) {
                Add-MainJournalStep -Journal $journal -Name 'totp' -Status 'in_progress'
                $result = Invoke-CyberButlerTotp -Root $InstallPath -VaultPath $vaultPath -ReaderAccount $TotpReaderAccount -AgentRuntimeAccount $AgentRuntimeAccount -RequireAgentRuntimeDeny:$resolution.Isolation -Issuer 'Cyber-Butler' -Account $OwnerQQ -JournalStep 'totp' -Journal $journal -Approval 'APPROVE TOTP' -Scanned:$totpScanned -RecoverySaved:$totpRecovery -SkipMaterialGeneration -NonInteractive:$NonInteractive -Handlers $Handlers
                if (-not (Complete-MainSecurityStep -Name 'totp' -Result $result)) {
                    $failure = [pscustomobject]@{ step = 'totp'; message = ('TOTP: ' + [string]$result.status + ' ' + [string]$result.message) }
                } else {
                    $qrPath = Join-Path $vaultPath 'totp_qr.png'
                    if (Test-Path -LiteralPath $qrPath) {
                        Remove-Item -LiteralPath $qrPath -Force -ErrorAction SilentlyContinue
                        Write-InstallerLine 'TOTP QR image removed after enrollment.' -Level INFO
                    }
                }
            }
        }
    }
}

if (-not $failure -and -not (Test-MainStepDone -Journal $journal -Name 'firewall')) {
    if (-not (Request-MainApproval -Token 'APPROVE FIREWALL' -Step 'firewall' -ApprovalTokens $ApprovalTokens -Approvals $approvals -NonInteractive:$NonInteractive)) {
        Add-MainJournalStep -Journal $journal -Name 'firewall' -Status 'failed' -Reason 'needs approval'
        $failure = [pscustomobject]@{ step = 'firewall'; message = 'APPROVE FIREWALL required'; kind = 'needs_approval' }
    } else {
        Add-MainJournalStep -Journal $journal -Name 'firewall' -Status 'in_progress'
        $result = Invoke-CyberButlerFirewallRule -RuleName 'Cyber-Butler Web UI 8765' -DisplayName 'Cyber-Butler Web UI 8765' -Direction Inbound -FirewallProfile Private -RemoteAddress '127.0.0.1' -Port $WebUIPort -Protocol TCP -Action Allow -JournalStep 'firewall' -Journal $journal -Approval 'APPROVE FIREWALL' -NonInteractive:$NonInteractive -Handlers $Handlers
        if (-not (Complete-MainSecurityStep -Name 'firewall' -Result $result)) {
            $failure = [pscustomobject]@{ step = 'firewall'; message = ('firewall: ' + [string]$result.status + ' ' + [string]$result.message) }
        }
    }
}

# Optional one-click SMTP/OTP configuration for the CBS WebUI.
# The auth code is passed as a SecureString in-process, never on the command line.
if (-not $failure -and -not (Test-CyberButlerSecureStringEmpty $SmtpSecret) -and $WebUIAdminEmail) {
    $emailScript = Join-Path $InstallPath 'tools\setup_email_secret.ps1'
    if (Test-Path -LiteralPath $emailScript) {
        try {
            $smtpLogin = if ($SmtpUser) { $SmtpUser } else { $WebUIAdminEmail }
            & $emailScript -SmtpHost $SmtpHost -SmtpPort $SmtpPort -SmtpUser $smtpLogin -AllowedSender $WebUIAdminEmail -SmtpAuthCode $SmtpSecret -BrokerAccount $DesktopAccount -SkipTest
            if ($LASTEXITCODE -ne 0) { throw ('setup_email_secret exit code ' + $LASTEXITCODE) }
            Write-Output 'EMAIL WebUI OTP configured'
        } catch {
            Write-Output ('EMAIL warning: ' + $_.Exception.Message)
        }
    }
}

if (-not $failure -and $SkipSecrets -and -not (Test-MainStepDone -Journal $journal -Name 'secrets')) {
    Add-MainJournalStep -Journal $journal -Name 'secrets' -Status 'skipped' -Reason 'skipped by GUI mode'
} elseif (-not $failure -and -not (Test-MainStepDone -Journal $journal -Name 'secrets')) {
    if ((Test-CyberButlerSecureStringEmpty $ApiKey) -and $ApiKeyFile -and (Test-Path -LiteralPath $ApiKeyFile)) {
        try { $ApiKey = ConvertTo-SecureString ((Get-Content -LiteralPath $ApiKeyFile -Raw).Trim()) -AsPlainText -Force } catch { Write-Verbose 'optional operation failed' }
    }
    if (-not (Request-MainApproval -Token 'APPROVE SECRETS' -Step 'secrets' -ApprovalTokens $ApprovalTokens -Approvals $approvals -NonInteractive:$NonInteractive)) {
        Add-MainJournalStep -Journal $journal -Name 'secrets' -Status 'failed' -Reason 'needs approval'
        $failure = [pscustomobject]@{ step = 'secrets'; message = 'APPROVE SECRETS required'; kind = 'needs_approval' }
    } else {
        Add-MainJournalStep -Journal $journal -Name 'secrets' -Status 'in_progress'
        $result = Invoke-CyberButlerSecrets -Root $InstallPath -ReaderAccount $(if ($resolution.Isolation) { $ServiceAccountName } else { $AgentRuntimeAccount }) -OwnerQQ $OwnerQQ -ApiKey $ApiKey -SmtpSecret $SmtpSecret -JournalStep 'secrets' -Journal $journal -Approval 'APPROVE SECRETS' -SkipSmtp:$SkipSmtp -NonInteractive:$NonInteractive -Handlers $Handlers
        if (-not (Complete-MainSecurityStep -Name 'secrets' -Result $result)) {
            $failure = [pscustomobject]@{ step = 'secrets'; message = ('secrets: ' + [string]$result.status + ' ' + [string]$result.message) }
        } elseif ($result.partial) {
            Add-MainJournalStep -Journal $journal -Name 'secrets' -Status 'skipped' -Reason ([string]$result.message)
        }
    }
}

# Record single-account TOTP limitation for the Broker ACL verifier.
if (-not $failure -and (Test-Path -LiteralPath $vaultPath)) {
    $singleAccountMarker = Join-Path $vaultPath 'single-account.marker'
    if (-not $resolution.Isolation) {
        Set-Content -LiteralPath $singleAccountMarker -Value 'single-account mode: AgentRuntime and desktop user share an identity; TOTP vault deny is not enforceable' -Encoding ASCII
    } else {
        Remove-Item -LiteralPath $singleAccountMarker -Force -ErrorAction SilentlyContinue
    }
}

if (-not $failure -and -not (Test-MainStepDone -Journal $journal -Name 'services')) {
    if (-not (Request-MainApproval -Token 'APPROVE SERVICES' -Step 'services' -ApprovalTokens $ApprovalTokens -Approvals $approvals -NonInteractive:$NonInteractive)) {
        Add-MainJournalStep -Journal $journal -Name 'services' -Status 'failed' -Reason 'needs approval'
        $failure = [pscustomobject]@{ step = 'services'; message = 'APPROVE SERVICES required'; kind = 'needs_approval' }
    } else {
        Add-MainJournalStep -Journal $journal -Name 'services' -Status 'in_progress'
        $result = Invoke-CyberButlerServices -Root $InstallPath -ServiceAccount $ServiceAccountName -DesktopAccount $DesktopAccount -ServiceAccountPassword $taskServiceAccountPassword -Isolation $resolution.Isolation -Features $featureResolution.FeatureIds -PersonalPluginsPath $PersonalPluginsPath -StartupTimeoutSeconds $StartupTimeoutSeconds -JournalStep 'services' -Journal $journal -Approval 'APPROVE SERVICES' -NonInteractive:$NonInteractive -Handlers $Handlers
        if (-not (Complete-MainSecurityStep -Name 'services' -Result $result)) {
            $failure = [pscustomobject]@{ step = 'services'; message = ('services: ' + [string]$result.status + ' ' + [string]$result.message) }
        }
    }
}

if (-not $failure -and ($GuiMode -or [string]::IsNullOrWhiteSpace($TestConfigPath))) {
    $brokerConfigPath = Join-Path $InstallPath 'tools\broker_config.json'
    $brokerConfig = if (Test-Path -LiteralPath $brokerConfigPath) {
        try { Get-Content -LiteralPath $brokerConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json } catch { [pscustomobject]@{ approval_channel = 'webui'; admin_email = '' } }
    } else {
        [pscustomobject]@{ approval_channel = 'webui'; admin_email = '' }
    }
    $auditKey = Join-Path $InstallPath 'tools/audit_hmac.dpapi'
    if (-not (Test-Path -LiteralPath $auditKey)) {
        $keyBytes = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($keyBytes)
        $protected = [Security.Cryptography.ProtectedData]::Protect($keyBytes, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine)
        [IO.File]::WriteAllBytes($auditKey, $protected)
        & icacls.exe $auditKey /inheritance:r /grant:r '*S-1-5-18:(R)' '*S-1-5-32-544:(F)' | Out-Null
    }
    $workspaceRoot = Join-Path $InstallPath 'workspace'
    $brokerConfig | Add-Member -NotePropertyName workspace_root -NotePropertyValue $workspaceRoot -Force
    $brokerConfig | Add-Member -NotePropertyName workspace_path -NotePropertyValue $workspaceRoot -Force
    $brokerConfig | Add-Member -NotePropertyName shared_roots -NotePropertyValue @($workspaceRoot) -Force
    Write-InstallerJson -Path $brokerConfigPath -Value $brokerConfig
    $writtenConfig = Get-Content -LiteralPath $brokerConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $writtenConfig.workspace_root -or @($writtenConfig.shared_roots) -notcontains $workspaceRoot) {
        $failure = [pscustomobject]@{ step = 'config'; message = ('broker_config missing workspace: ' + $workspaceRoot); kind = 'configuration' }
    }
}

if (-not $failure -and ($GuiMode -or [string]::IsNullOrWhiteSpace($TestConfigPath))) {
    $brokerToken = Join-Path $InstallPath 'tools/broker_token.txt'
    $tokenDeadline = (Get-Date).AddSeconds(90)
    while (-not (Test-Path -LiteralPath $brokerToken) -and (Get-Date) -lt $tokenDeadline) {
        Start-Sleep -Seconds 1
    }
    if (Test-Path -LiteralPath $brokerToken) {
        $tokenReaders = @($DesktopAccount, $currentDesktopUser) | Where-Object { $_ } | Select-Object -Unique
        if ($tokenReaders.Count -eq 0) { throw 'DesktopAccount is empty; refusing broker token ACL grant.' }
        $tokenSids = @{}
        $sidResolutionError = $null
        foreach ($tokenReader in $tokenReaders) {
            try {
                $tokenSid = (New-Object System.Security.Principal.NTAccount($tokenReader)).Translate([System.Security.Principal.SecurityIdentifier]).Value
            } catch {
                $sidResolutionError = ('Failed to resolve SID for user: ' + $tokenReader + '. Error: ' + $_.Exception.Message)
                break
            }
            if ([string]::IsNullOrWhiteSpace($tokenSid)) {
                $sidResolutionError = ('Failed to resolve SID for user: ' + $tokenReader)
                break
            }
            $tokenSids[$tokenReader] = $tokenSid
            try {
                & icacls.exe $brokerToken /grant ('*' + $tokenSid + ':(R)') | Out-Null
            } catch {
                $sidResolutionError = ('Failed to grant token read to: ' + $tokenReader + '. Error: ' + $_.Exception.Message)
                break
            }
        }
        if (-not $sidResolutionError) {
            $missingReaders = @($tokenReaders | Where-Object { -not (Test-CyberButlerTokenReadAcl -Path $brokerToken -Account $_) })
        } else {
            $missingReaders = @()
        }
        if ($sidResolutionError) {
            $failure = [pscustomobject]@{
                step = 'acl'
                message = $sidResolutionError
                kind = 'security'
            }
            Write-InstallerLine $sidResolutionError -Level ERROR
        } elseif ($LASTEXITCODE -ne 0 -or $missingReaders.Count -gt 0) {
            $failure = [pscustomobject]@{
                step = 'acl'
                message = ('broker token ACL missing desktop read: ' + ($missingReaders -join ','))
                kind = 'security'
            }
            Write-InstallerLine ('Broker token desktop ACL FAILED: ' + ($missingReaders -join ',')) -Level ERROR
        } else {
            Write-InstallerLine ('Broker token desktop read granted: ' + ($tokenReaders -join ',')) -Level INFO
        }
    }
}

if (-not $failure -and -not (Test-MainStepDone -Journal $journal -Name 'shortcut')) {
    Add-MainJournalStep -Journal $journal -Name 'shortcut' -Status 'in_progress'
    try {
        $shortcutScript = Join-Path $InstallPath 'tools\create_dashboard_shortcut.ps1'
        if (-not (Test-Path -LiteralPath $shortcutScript)) { throw ('Desktop shortcut helper missing: ' + $shortcutScript) }
        & $shortcutScript -ProjectRoot $InstallPath | Out-Host
        Add-MainJournalStep -Journal $journal -Name 'shortcut' -Status 'completed' -Reason 'desktop shortcut created'
    } catch {
        Add-MainJournalStep -Journal $journal -Name 'shortcut' -Status 'completed' -Reason ('desktop shortcut warning: ' + $_.Exception.Message)
        Write-InstallerLine ('Desktop shortcut warning: ' + $_.Exception.Message) -Level WARN
    }
}

if ($failure -and [string]$failure.kind -eq 'needs_approval') {
    Write-InstallerLine 'Interactive approval is required.' -Level BLOCKING
    $report = Write-MainReport -Status 'needs_approval' -Diagnostics $diagnostics -Journal $journal -Approvals $approvals `
        -Steps @($journal.State.steps) -Failure $failure -Message 'Install is waiting for approval.' `
        -ReportDirectory $ReportDirectory -Tier $resolution.Tier -EffectiveTier $resolution.EffectiveLabel -Isolation $resolution.Isolation -Handlers $Handlers
    Write-Output ('REPORT ' + $report.json)
    exit (Get-InstallerExitCode -Name NeedsApproval)
}

if ($failure) {
    try { $rollbackResult = Invoke-CyberButlerRollback -Journal $journal -Handlers $RollbackHandlers } catch { $rollbackResult = [pscustomobject]@{ status = 'rollback_failed'; executed = @(); errors = @($_.Exception.Message) } }
    $manualPath = Join-Path $journal.RunRoot 'manual-recovery.txt'
    $manualText = "Manual recovery required.`r`nJournal: $($journal.StatePath)`r`nRollback status: $($rollbackResult.status)`r`nFailure: $($failure.step): $($failure.message)`r`n"
    [IO.File]::WriteAllText($manualPath, $manualText, (New-Object Text.UTF8Encoding($false)))
    $report = Write-MainReport -Status 'failed' -Diagnostics $diagnostics -Journal $journal -Approvals $approvals `
        -Steps @($journal.State.steps) -Failure $failure -Message ('Install failed; manual recovery: ' + $manualPath) `
        -ReportDirectory $ReportDirectory -Tier $resolution.Tier -EffectiveTier $resolution.EffectiveLabel -Isolation $resolution.Isolation -Handlers $Handlers
    Write-Output ('FAILED ' + $failure.step + ': ' + $failure.message)
    Write-Output ('REPORT ' + $report.json)
    Write-Output ('MANUAL ' + $manualPath)
    if ($rollbackResult.status -eq 'rollback_failed') { exit (Get-InstallerExitCode -Name RollbackFailed) }
    exit (Get-InstallerExitCode -Name ValidationFailed)
}

# External Agent detection: CBS never installs or manages AgentRuntime/AuxRuntimeApplication.
$detectedAgents = @()
foreach ($agentPort in @(6185, 5099)) {
    if (Get-NetTCPConnection -State Listen -LocalPort $agentPort -ErrorAction SilentlyContinue) {
        $detectedAgents += $agentPort
    }
}
if ($detectedAgents.Count -gt 0) {
    Write-InstallerLine ('检测到外部 Agent 正在运行（端口 ' + ($detectedAgents -join ', ') + '）。请参考 docs/API_SPEC.md 进行标准接入。') -Level INFO
    Write-Output ('EXTERNAL_AGENT detected=' + ($detectedAgents -join ','))
} else {
    Write-InstallerLine 'CBS 核心已就绪。请自行安装你喜欢的 Agent 框架（如 AgentRuntime/DSH），并接入 18090 端口。' -Level INFO
    Write-Output 'EXTERNAL_AGENT none'
}

# Diagnostics
if ($null -eq $diagnostics) {
    $diagnostics = Get-CyberButlerDiagnostics -Tier $resolution.Tier -EffectiveTier $resolution.EffectiveLabel `
        -Isolation $resolution.Isolation -Root $InstallPath -ServiceAccount $ServiceAccountName `
        -AgentRuntimeAccount $AgentRuntimeAccount -WebUIBind $resolution.WebUIBind -Handlers $Handlers
}
if (-not (Test-MainStepDone -Journal $journal -Name 'diagnostics')) {
    Add-MainJournalStep -Journal $journal -Name 'diagnostics' -Status 'completed'
}

# Report
$markerVersion = '1.6.3'
try {
    $releaseVersionPath = Join-Path (Split-Path -Parent $installerRoot) 'VERSION'
    if (Test-Path -LiteralPath $releaseVersionPath) {
        $markerVersion = (Get-Content -LiteralPath $releaseVersionPath -Raw -ErrorAction SilentlyContinue).Trim()
    }
} catch { Write-Verbose 'optional operation failed' }
try {
    $markerPath = Write-CyberButlerInstallStateMarker -InstallPath $InstallPath -Version $markerVersion -Tier $resolution.Tier -Isolation $resolution.Isolation -Source 'installer'
    Write-Output ('STATE ' + $markerPath)
} catch {
    Write-InstallerLine ('Install state marker was not written: ' + $_.Exception.Message) -Level WARN
}
$report = Write-MainReport -Status 'success' -Diagnostics $diagnostics -Journal $journal -Approvals $approvals `
    -Steps @($journal.State.steps) -Failure $null -Message 'Install completed.' -ReportDirectory $ReportDirectory `
    -Tier $resolution.Tier -EffectiveTier $resolution.EffectiveLabel -Isolation $resolution.Isolation -Handlers $Handlers
Add-MainJournalStep -Journal $journal -Name 'report' -Status 'completed' -Reason $report.json
Write-Output 'INSTALLER_OK'
Write-Output ('REPORT ' + $report.json)
exit (Get-InstallerExitCode -Name Success)
} catch {
    if ($null -eq $failure) {
        $failure = [pscustomobject]@{ step = 'unhandled'; message = $_.Exception.Message; kind = 'unexpected' }
    } else {
        $failure | Add-Member -NotePropertyName stack -NotePropertyValue $_.ScriptStackTrace -Force
    }
    if ($null -ne $journal) {
        try { Add-MainJournalStep -Journal $journal -Name ([string]$failure.step) -Status 'failed' -Reason ([string]$failure.message) } catch { Write-Verbose 'journal failure' }
    }
    $catchReportDir = if ($ReportDirectory) { $ReportDirectory } else { Join-Path $env:ProgramData 'CyberButler\installer-report' }
    try {
        New-Item -ItemType Directory -Path $catchReportDir -Force | Out-Null
        $catchReport = [ordered]@{
            schema = 1
            status = 'failed'
            failure = [ordered]@{ step = [string]$failure.step; message = [string]$failure.message; stack = $_.ScriptStackTrace }
            generated_at = (Get-Date).ToUniversalTime().ToString('o')
        }
        [IO.File]::WriteAllText((Join-Path $catchReportDir 'install-report.json'), ($catchReport | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
    } catch { Write-InstallerLine ('Failed to write failure report: ' + $_.Exception.Message) -Level ERROR }
    Write-Output ('FAILED ' + [string]$failure.step + ': ' + [string]$failure.message)
    Write-Output ('REPORT ' + (Join-Path $catchReportDir 'install-report.json'))
    exit (Get-InstallerExitCode -Name ValidationFailed)
}
