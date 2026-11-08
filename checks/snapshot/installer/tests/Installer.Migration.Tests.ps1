$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
$migrationScript = Join-Path $installerRoot 'Migrate-EnableIsolation.ps1'
$psExe = Join-Path $PSHOME 'powershell.exe'

<#
.SYNOPSIS
    New-MigrationTestConfig performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function New-MigrationTestConfig {
    param(
        [string]$Base,
        [bool]$Verify = $true,
        [bool]$Approval = $true,
        [string]$FailStep = '',
        [bool]$Satisfied = $false
    )
    $template = @'
$global:cbMigrationBase = '__BASE__'
$global:cbMigrationVerify = '__VERIFY__' -eq 'true'
$global:cbMigrationSatisfied = '__SATISFIED__' -eq 'true'
$global:cbMigrationFailStep = '__FAIL__'
$global:cbMigrationCalls = @{ account = 0; stop = 0; tasks = 0; undo = 0; auxruntime = 0; broker = 0 }

$handlers = @{
    'migration.test' = {
        param($c)
        [pscustomobject]@{ satisfied = $global:cbMigrationSatisfied; account_exists = $false; agentruntime_principal = 'desktop'; webui_principal = 'desktop'; auxruntime = 'unchanged'; broker = 'unchanged' }
    }
    'migration.preflight' = { param($c) [pscustomobject]@{ install_path = [pscustomobject]@{ existing_state = 'Installed' } } }
    'migration.snapshot' = { param($c) [pscustomobject]@{ status = 'completed' } }
    'migration.account' = { param($c) $global:cbMigrationCalls.account++; [pscustomobject]@{ created = $true } }
    'migration.acl' = { param($c) [pscustomobject]@{ status = 'completed' } }
    'migration.dpapi' = { param($c) [pscustomobject]@{ status = 'completed' } }
    'migration.stop' = { param($c) $global:cbMigrationCalls.stop++; [pscustomobject]@{ status = 'completed'; auxruntime = 'unchanged'; broker = 'unchanged' } }
    'migration.tasks' = { param($c) $global:cbMigrationCalls.tasks++; [pscustomobject]@{ status = 'completed' } }
    'migration.start' = { param($c) [pscustomobject]@{ status = 'completed' } }
    'migration.verify' = { param($c) $global:cbMigrationVerify }
    'migration.undo' = { param($c) $global:cbMigrationCalls.undo++; [pscustomobject]@{ status = 'rolled_back'; executed = @(); errors = @() } }
    'migration.auxruntime' = { param($c) $global:cbMigrationCalls.auxruntime++; $null }
    'migration.broker' = { param($c) $global:cbMigrationCalls.broker++; $null }
}

$rollbackHandlers = @{
    'restore-acl' = { param($a) }
    'restore-file' = { param($a) }
    'restore-scheduled-task' = { param($a) }
    'delete-created-account' = { param($a) }
    'delete-created-file' = { param($a) }
    'delete-created-scheduled-task' = { param($a) }
    'stop-created-process' = { param($a) }
    'delete-created-directory' = { param($a) }
}

return @{
    Handlers = $handlers
    RollbackHandlers = $rollbackHandlers
    Approval = $(if ('__APPROVAL__' -eq 'true') { 'APPROVE MIGRATE-ISOLATION' } else { '' })
}
'@
    $text = $template.Replace('__BASE__', $Base).Replace('__VERIFY__', $Verify.ToString().ToLower()).Replace('__FAIL__', $FailStep).Replace('__SATISFIED__', $Satisfied.ToString().ToLower()).Replace('__APPROVAL__', $Approval.ToString().ToLower())
    $path = Join-Path $Base 'migration-test-config.ps1'
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($true)))
    return $path
}

function Invoke-Migration {
    param([string]$Base, [string]$Mode, [string]$Config, [string]$StatePath = '')
    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $migrationScript, $Mode,
        '-Tier', 'Medium', '-InstallPath', (Join-Path $Base 'install'),
        '-ServiceAccountName', 'FakeSvc', '-DesktopAccount', 'DESKTOP\Owner',
        '-AgentRuntimeAccount', 'DESKTOP\Owner', '-JournalRoot', (Join-Path $Base 'state'),
        '-ReportDirectory', (Join-Path $Base 'report'), '-TestConfigPath', $Config)
    if ($Mode -eq '-Apply' -or $Mode -eq '-PlanOnly' -or $Mode -eq '-Verify') { $args += '-NonInteractive' }
    if ($StatePath) { $args += @('-StatePath', $StatePath) }
    return (& $psExe @args 2>&1)
}

Describe 'Isolation migration' {
    It 'plans without changing state and documents AuxRuntimeApplication/Broker' {
        $base = Join-Path $env:TEMP ('cb-migrate-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MigrationTestConfig -Base $base
            $out = Invoke-Migration -Base $base -Mode '-PlanOnly' -Config $config
            $LASTEXITCODE | Should Be 0
            $text = $out -join "`n"
            ($text -match 'Downtime estimate') | Should Be $true
            ($text -match 'AuxRuntimeApplication: unchanged') | Should Be $true
            ($text -match 'Broker: unchanged') | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'report\migration-report.json')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $base 'state')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'applies with approval and writes a secret-free report' {
        $base = Join-Path $env:TEMP ('cb-migrate-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MigrationTestConfig -Base $base
            $out = Invoke-Migration -Base $base -Mode '-Apply' -Config $config
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'MIGRATION_OK') | Should Be $true
            $reportPath = Join-Path $base 'report\migration-report.json'
            $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.status | Should Be 'success'
            $report.auxruntime | Should Be 'unchanged'
            $report.broker | Should Be 'unchanged'
            $report.downtime_estimate | Should Not BeNullOrEmpty
            $reportText = Get-Content -LiteralPath $reportPath -Raw
            ($reportText -match 'fake-api-key-value|fake-smtp-password|totp_secret_value') | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'verifies an isolated state and rejects a non-isolated state' {
        $base = Join-Path $env:TEMP ('cb-migrate-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MigrationTestConfig -Base $base
            $out = Invoke-Migration -Base $base -Mode '-Verify' -Config $config
            $LASTEXITCODE | Should Be 20
            (($out -join "`n") -match 'ISOLATION_NOT_VERIFIED') | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'requires APPROVE MIGRATE-ISOLATION under NonInteractive' {
        $base = Join-Path $env:TEMP ('cb-migrate-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MigrationTestConfig -Base $base -Approval $false
            $out = Invoke-Migration -Base $base -Mode '-Apply' -Config $config
            $LASTEXITCODE | Should Be 10
            (($out -join "`n") -match 'APPROVE MIGRATE-ISOLATION') | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'report\migration-report.json')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'verifies an already isolated state' {
        $base = Join-Path $env:TEMP ('cb-migrate-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MigrationTestConfig -Base $base -Satisfied $true
            $out = Invoke-Migration -Base $base -Mode '-Verify' -Config $config
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'ISOLATION_VERIFIED') | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'rolls back a failed verification and reports the failed step' {
        $base = Join-Path $env:TEMP ('cb-migrate-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MigrationTestConfig -Base $base -Verify $false
            $out = Invoke-Migration -Base $base -Mode '-Apply' -Config $config
            $LASTEXITCODE | Should Not Be 0
            (($out -join "`n") -match 'FAILED verify') | Should Be $true
            $report = Get-Content -LiteralPath (Join-Path $base 'report\migration-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.status | Should Be 'failed'
            $report.failure.step | Should Be 'verify'
            (Test-Path -LiteralPath (Join-Path $base 'report\migration-report.md')) | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'rolls back an applied migration through the migration undo handler' {
        $base = Join-Path $env:TEMP ('cb-migrate-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MigrationTestConfig -Base $base
            $apply = Invoke-Migration -Base $base -Mode '-Apply' -Config $config
            $LASTEXITCODE | Should Be 0
            $report = Get-Content -LiteralPath (Join-Path $base 'report\migration-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $out = Invoke-Migration -Base $base -Mode '-Rollback' -Config $config -StatePath $report.journal_path
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'ROLLBACK rolled_back') | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'report\migration-report.md')) | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
