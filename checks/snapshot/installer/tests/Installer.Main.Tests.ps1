$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
$mainScript = Join-Path $installerRoot 'Install-CyberButler.ps1'
$psExe = Join-Path $PSHOME 'pwsh.exe'

<#
.SYNOPSIS
    New-MainTestConfig performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function New-MainTestConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Base,
        [string]$FailStep = '',
        [ValidateSet('all', 'until-firewall', 'without-totp')]
        [string]$TokenMode = 'all',
        [bool]$PythonMissing = $false,
        [bool]$PythonTooNew = $false,
        [bool]$CoreFail = $false
    )

    $template = @'
$base = '__BASE__'
$failStep = '__FAIL__'
$tokenMode = '__TOKENS__'
$pythonMissing = '__PYTHON_MISSING__' -eq 'true'
$coreFail = '__CORE_FAIL__' -eq 'true'
$pythonTooNew = '__PYTHON_TOO_NEW__' -eq 'true'
$global:cbMainBase = $base
$global:cbFailStep = $failStep
$aclBackup = Join-Path $base 'acl.clixml'
$totpAcl = Join-Path $base 'totp.clixml'
$secretAcl = Join-Path $base 'secret.clixml'
$global:cbAclBackup = $aclBackup
$global:cbTotpAcl = $totpAcl
$global:cbSecretAcl = $secretAcl
New-Item -ItemType File -Path $aclBackup -Force | Out-Null
New-Item -ItemType File -Path $totpAcl -Force | Out-Null
New-Item -ItemType File -Path $secretAcl -Force | Out-Null

$handlers = @{
    'core.deploy' = { param($c) Set-Content -LiteralPath (Join-Path $global:cbMainBase 'core.marker') -Value 'called'; $root = $c.Root; foreach ($d in @('tools','webui','data','workspace','webui\.venv\Scripts')) { New-Item -ItemType Directory -Path (Join-Path $root $d) -Force | Out-Null }; [pscustomobject]@{ status = 'completed'; mode = 'test'; paths = [pscustomobject]@{ tools = (Join-Path $root 'tools'); webui = (Join-Path $root 'webui'); data = (Join-Path $root 'data'); workspace = (Join-Path $root 'workspace') } } }
    'accounts.test' = { param($c) [pscustomobject]@{ satisfied = $false; supported = $true; can_manage = $true; exists = $false } }
    'accounts.create' = { param($c) [pscustomobject]@{ created = $true } }
    'accounts.assert' = { param($c) $true }
    'accounts.undo' = { param($c) [pscustomobject]@{ action = 'removed' } }
    'acl.test' = { param($c) [pscustomobject]@{ satisfied = $false; exists = $true; can_manage = $true } }
    'acl.backup' = { param($c) $global:cbAclBackup }
    'acl.apply' = { param($c) Set-Content -LiteralPath (Join-Path $global:cbMainBase 'acl.marker') -Value 'called'; $true }
    'acl.assert' = { param($c) $global:cbFailStep -ne 'acl' }
    'acl.undo' = { param($c) [pscustomobject]@{ action = 'restored' } }
    'firewall.test' = { param($c) [pscustomobject]@{ satisfied = $false; supported = $true; can_manage = $true; exists = $false; state = $null } }
    'firewall.apply' = { param($c) [pscustomobject]@{ created = $true } }
    'firewall.assert' = { param($c) $true }
    'firewall.undo' = { param($c) [pscustomobject]@{ action = 'removed' } }
    'totp.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
    'totp.generate' = {
        param($c)
        Set-Content -LiteralPath (Join-Path $global:cbMainBase 'totp.marker') -Value 'called'
        New-Item -ItemType Directory -Path $c.VaultPath -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $c.VaultPath 'totp_secret.dpapi') -Value 'fake' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $c.VaultPath 'recovery_codes.txt') -Value 'fake' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $c.VaultPath 'totp_qr.png') -Value 'fake' -Encoding ASCII
        [pscustomobject]@{ created = $true }
    }
    'totp.acl' = { param($c) $global:cbTotpAcl }
    'totp.assert' = { param($c) $true }
    'totp.undo' = { param($c) [pscustomobject]@{ action = 'removed' } }
    'secrets.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
    'secrets.write' = {
        param($c)
        Set-Content -LiteralPath (Join-Path $global:cbMainBase 'secrets.marker') -Value 'called'
        New-Item -ItemType Directory -Path (Split-Path -Parent $c.Path) -Force | Out-Null
        Set-Content -LiteralPath $c.Path -Value 'fake' -Encoding ASCII
        $true
    }
    'secrets.acl' = { param($c) $global:cbSecretAcl }
    'secrets.assert' = { param($c) $global:cbFailStep -ne 'secrets' }
    'secrets.undo' = { param($c) [pscustomobject]@{ action = 'removed' } }
    'services.test' = { param($c) [pscustomobject]@{ satisfied = $false; supported = $true; can_manage = $true } }
    'services.apply' = { param($c) [pscustomobject]@{ created = @('AgentRuntime Service'); started_process_ids = @(4242) } }
    'services.assert' = { param($c) $true }
    'services.undo' = { param($c) [pscustomobject]@{ action = 'removed' } }
    'services.plugin-smoke' = { param($c) [pscustomobject]@{ ok = $true; reason = 'test'; failed = @(); lines = @(); tail = @() } }
    'diagnostics.run' = {
        param($c)
        $items = @(
            [pscustomobject]@{ id = 'isolation'; label = '双账户隔离'; status = $(if ($c.Isolation) { 'ENABLED' } else { 'MANUAL' }); reason = 'test' },
            [pscustomobject]@{ id = 'totp'; label = 'TOTP 审批'; status = 'ENABLED'; reason = 'test' },
            [pscustomobject]@{ id = 'router'; label = 'Router fail-closed'; status = 'ENABLED'; reason = 'test' },
            [pscustomobject]@{ id = 'webui'; label = 'Web UI 绑定'; status = 'ENABLED'; reason = 'test' },
            [pscustomobject]@{ id = 'api_key'; label = 'API Key 保护'; status = 'ENABLED'; reason = 'test' },
            [pscustomobject]@{ id = 'totp_vault'; label = 'TOTP 保险箱隔离'; status = $(if ($c.Isolation) { 'ENABLED' } else { 'PARTIAL' }); reason = 'test' },
            [pscustomobject]@{ id = 'audit'; label = '审计'; status = 'ENABLED'; reason = 'test' },
            [pscustomobject]@{ id = 'firewall'; label = '防火墙'; status = 'ENABLED'; reason = 'test' }
        )
        [pscustomobject]@{ items = $items }
    }
    'python.bootstrap' = {
        param($c)
        Set-Content -LiteralPath (Join-Path $global:cbMainBase 'python.marker') -Value 'called' -Encoding ASCII
        [pscustomobject]@{ status = 'completed'; reason = 'test bundle'; python_source = 'bundled'; python_path = (Join-Path $global:cbMainBase 'install\.python\python.exe'); python_version = 'Python 3.13.17'; created = $true }
    }
}

if ($pythonMissing) {
    $handlers['preflight.python'] = { param($c) @() }
}
if ($pythonTooNew) {
    $handlers['preflight.python'] = {
        param($c)
        @([pscustomobject]@{
            found = $true
            path = 'C:fake\python.exe'
            candidate_path = 'C:fake\python.exe'
            python_source = 'system'
            version = 'Python 3.15.2'
            version_ok = $false
            version_too_new = $true
        })
    }
}
if ($coreFail) {
    $handlers['core.deploy'] = { param($c) Set-Content -LiteralPath (Join-Path $global:cbMainBase 'core-failed.marker') -Value 'called'; [pscustomobject]@{ status = 'failed'; message = 'fake core failure' } }
}

$tokens = @{
    'APPROVE PLAN' = 'APPROVE PLAN'
    'APPROVE ACCOUNT' = 'APPROVE ACCOUNT'
    'APPROVE ACL' = 'APPROVE ACL'
    'APPROVE FIREWALL' = 'APPROVE FIREWALL'
    'APPROVE TOTP' = 'APPROVE TOTP'
    'APPROVE SECRETS' = 'APPROVE SECRETS'
    'APPROVE SERVICES' = 'APPROVE SERVICES'
    'SCANNED' = 'SCANNED'
    'RECOVERY-SAVED' = 'RECOVERY-SAVED'
}
if ($tokenMode -eq 'without-totp') {
    $tokens.Remove('APPROVE TOTP')
    $tokens.Remove('SCANNED')
    $tokens.Remove('RECOVERY-SAVED')
}
if ($tokenMode -eq 'until-firewall') {
    $tokens.Remove('APPROVE TOTP')
    $tokens.Remove('SCANNED')
    $tokens.Remove('RECOVERY-SAVED')
    $tokens.Remove('APPROVE SECRETS')
    $tokens.Remove('APPROVE SERVICES')
}

$rollbackHandlers = @{
    'restore-acl' = { param($a) }
    'delete-created-file' = { param($a) }
    'delete-created-account' = { param($a) }
    'delete-created-scheduled-task' = { param($a) }
    'stop-created-process' = { param($a) }
    'restore-scheduled-task' = { param($a) }
    'restore-file' = { param($a) }
    'delete-created-directory' = { param($a) }
}

return @{
    Handlers = $handlers
    ApprovalTokens = $tokens
    RollbackHandlers = $rollbackHandlers
    ApiKey = (ConvertTo-SecureString 'fake-api-key-value' -AsPlainText -Force)
    SmtpSecret = (ConvertTo-SecureString 'fake-smtp-password' -AsPlainText -Force)
}
'@
    $text = $template.Replace('__BASE__', $Base).Replace('__FAIL__', $FailStep).Replace('__TOKENS__', $TokenMode).Replace('__PYTHON_MISSING__', $PythonMissing.ToString().ToLower()).Replace('__CORE_FAIL__', $CoreFail.ToString().ToLower()).Replace('__PYTHON_TOO_NEW__', $PythonTooNew.ToString().ToLower())
    $path = Join-Path $Base 'test-config.ps1'
    [IO.File]::WriteAllText($path, $text, (New-Object Text.UTF8Encoding($true)))
    return $path
}

function Invoke-MainInstaller {
    param(
        [string]$Base,
        [string]$Tier = 'Medium',
        [string]$Extra = '',
        [string]$ConfigPath
    )
    $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $mainScript,
        '-Tier', $Tier, '-NonInteractive', '-InstallPath', (Join-Path $Base 'install'),
        '-OwnerQQ', '<QQ>', '-JournalRoot', (Join-Path $Base 'state'),
        '-ReportDirectory', (Join-Path $Base 'report'), '-TestConfigPath', $ConfigPath,
        '-Scanned', '-RecoverySaved')
    if ($Extra) { $arguments += $Extra.Split(' ') }
    return (& $psExe @arguments 2>&1)
}

Describe 'Installer main pipeline' {
    It 'accepts a plaintext ApiKey in -File mode' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $mainScript -PlanOnly -Tier Medium -InstallPath (Join-Path $base 'install') -ApiKey 'sk-plain-test-key' 2>&1
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'Mode: PlanOnly') | Should Be $true
            (($out -join "`n") -match 'SecureString') | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'prints a secure API key prompt when a value is missing' {
        $reader = { ConvertTo-SecureString 'test-api-key' -AsPlainText -Force }
        $global:cbPromptValue = $null
        $output = & { $global:cbPromptValue = Read-CyberButlerSecureSecret -Prompt 'API Key is required for AgentRuntime. Please enter your DeepSeek API Key:' -Reader $reader } 6>&1 | Out-String
        $output | Should Match 'API Key is required for AgentRuntime'
        $global:cbPromptValue.Length | Should Be 12
    }

    It 'plan-only runs preflight and plan without invoking any step' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base
            $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $mainScript -PlanOnly -Tier Medium -InstallPath (Join-Path $base 'install') -TestConfigPath $config 2>&1
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'Mode: PlanOnly') | Should Be $true
            (($out -join "`n") -match 'Install Python 3.10-3.13') | Should Be $false
            (($out -join "`n") -match 'Supply -PythonPackage') | Should Be $false
            (Test-Path -LiteralPath (Join-Path $base 'core.marker')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $base 'acl.marker')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'shows the bundled Python plan when Python is missing' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base -PythonMissing $true
            $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $mainScript -PlanOnly -Tier Medium -InstallPath (Join-Path $base 'install') -TestConfigPath $config 2>&1
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'No compatible system Python was found') | Should Be $true
            (($out -join "`n") -match 'Supply -PythonPackage') | Should Be $true
            (($out -join "`n") -match 'PREFLIGHT_BLOCKING') | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'runs Python bootstrap when the system Python is missing' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base -PythonMissing $true
            $out = Invoke-MainInstaller -Base $base -Tier Medium -ConfigPath $config
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'PYTHON bootstrap required') | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'python.marker')) | Should Be $true
            $report = Get-Content -LiteralPath (Join-Path $base 'report\install-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $pythonStep = @($report.steps | Where-Object { $_.name -eq 'python' })[0]
            $pythonStep.status | Should Be 'completed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'shows Python manual only when the system Python is too new' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base -PythonTooNew $true
            $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $mainScript -PlanOnly -Tier Medium -InstallPath (Join-Path $base 'install') -TestConfigPath $config 2>&1
            $LASTEXITCODE | Should Be 0
            $text = $out -join "`n"
            ($text -match 'Install Python 3.10-3.13') | Should Be $true
            ($text -match 'Python 3.14\+') | Should Be $true
            ($text -match 'Supply -PythonPackage') | Should Be $true
            ($text -match 'PREFLIGHT_BLOCKING') | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'requires APPROVE TOTP before firewall on a Medium install' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base -TokenMode 'without-totp'
            $out = Invoke-MainInstaller -Base $base -Tier Medium -ConfigPath $config
            $LASTEXITCODE | Should Be 10
            (($out -join "`n") -match 'Interactive approval is required') | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'acl.marker')) | Should Be $true
            $stateFile = Get-ChildItem -LiteralPath (Join-Path $base 'state') -Directory |
                Sort-Object LastWriteTime -Descending |
                ForEach-Object { Join-Path $_.FullName 'state.json' } |
                Where-Object { Test-Path -LiteralPath $_ } |
                Select-Object -First 1
            $state = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
            $totp = @($state.steps | Where-Object { $_.name -eq 'totp' })[0]
            $totp.status | Should Be 'failed'
            $totp.details.reason | Should Be 'needs approval'
            @($state.steps | Where-Object { $_.name -eq 'firewall' }).Count | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'stops before ACL when Core Deploy fails' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base -CoreFail $true
            $out = Invoke-MainInstaller -Base $base -Tier Medium -ConfigPath $config
            $LASTEXITCODE | Should Be 20
            (($out -join "`n") -match 'FAILED core') | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'core-failed.marker')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'acl.marker')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'completes a Medium install and writes a secret-free report' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base
            $out = Invoke-MainInstaller -Base $base -Tier Medium -ConfigPath $config
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'INSTALLER_OK') | Should Be $true
            $reportPath = Join-Path $base 'report\install-report.json'
            (Test-Path -LiteralPath $reportPath) | Should Be $true
            $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.status | Should Be 'success'
            $report.tier | Should Be 'Medium'
            $report.effective_tier | Should Be 'Medium'
            $report.isolation | Should Be $false
            @($report.diagnostics.items).Count | Should Be 8
            $reportText = Get-Content -LiteralPath $reportPath -Raw
            ($reportText -match 'fake-api-key-value|fake-smtp-password') | Should Be $false
            (Get-CyberButlerExistingState -InstallPath (Join-Path $base 'install')) | Should Be 'Installed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'runs High, Medium and Light with the correct effective tier' {
        foreach ($tier in @('High', 'Medium', 'Light')) {
            $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $base -Force | Out-Null
            try {
                $config = New-MainTestConfig -Base $base
                $extra = if ($tier -eq 'High') { '-EnableIsolation true' } elseif ($tier -eq 'Light') { '-AcceptLowerSecurity' } else { '' }
                $out = Invoke-MainInstaller -Base $base -Tier $tier -Extra $extra -ConfigPath $config
                $LASTEXITCODE | Should Be 0
                $report = Get-Content -LiteralPath (Join-Path $base 'report\install-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
                $report.effective_tier | Should Be $tier
                @($report.diagnostics.items).Count | Should Be 8
            } finally {
                Remove-Item -LiteralPath $base -Recurse -Force
            }
        }
    }

    It 'returns 10 and stops when NonInteractive lacks a mid-pipeline approval' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base -TokenMode 'until-firewall'
            $out = Invoke-MainInstaller -Base $base -Tier Medium -ConfigPath $config
            $LASTEXITCODE | Should Be 10
            (($out -join "`n") -match 'interactive approval') | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'totp.marker')) | Should Be $false
            $report = Get-Content -LiteralPath (Join-Path $base 'report\install-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.status | Should Be 'needs_approval'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'keeps completed TOTP and Firewall steps when Secrets fails' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base -FailStep 'secrets'
            $out = Invoke-MainInstaller -Base $base -Tier Medium -ConfigPath $config
            $LASTEXITCODE | Should Be 20
            $report = Get-Content -LiteralPath (Join-Path $base 'report\install-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.status | Should Be 'failed'
            $report.failure.step | Should Be 'secrets'
            $totp = @($report.steps | Where-Object { $_.name -eq 'totp' })[0]
            $firewall = @($report.steps | Where-Object { $_.name -eq 'firewall' })[0]
            $totp.status | Should Be 'completed'
            $firewall.status | Should Be 'completed'
            ($null -ne $totp.details.undo) | Should Be $true
            ($null -ne $firewall.details.undo) | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'rolls back and reports a failed step when Assert fails' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base -FailStep 'acl'
            $out = Invoke-MainInstaller -Base $base -Tier Medium -ConfigPath $config
            $LASTEXITCODE | Should Not Be 0
            (($out -join "`n") -match 'FAILED acl') | Should Be $true
            $report = Get-Content -LiteralPath (Join-Path $base 'report\install-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.status | Should Be 'failed'
            $report.failure.step | Should Be 'acl'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'repair mode runs diagnostics without invoking security steps' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base
            $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $mainScript -Repair -Tier Medium -InstallPath (Join-Path $base 'install') -ReportDirectory (Join-Path $base 'report') -TestConfigPath $config 2>&1
            $LASTEXITCODE | Should Be 0
            (Test-Path -LiteralPath (Join-Path $base 'report\install-report.json')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'core.marker')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $base 'acl.marker')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'resumes from the last unfinished main step without reinstalling' {
        $base = Join-Path $env:TEMP ('cb-main-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $config = New-MainTestConfig -Base $base
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state-resume') -InstallPath (Join-Path $base 'install') -Tier Medium
            foreach ($name in @('preflight', 'plan', 'core', 'accounts', 'acl', 'firewall', 'totp', 'secrets', 'services')) {
                Add-CyberButlerJournalStep -Journal $journal -Name $name -Status completed | Out-Null
            }
            $out = & $psExe -NoProfile -ExecutionPolicy Bypass -File $mainScript -Resume -StatePath $journal.StatePath -Tier Medium -NonInteractive -InstallPath (Join-Path $base 'install') -OwnerQQ '<QQ>' -JournalRoot (Join-Path $base 'state') -ReportDirectory (Join-Path $base 'report') -TestConfigPath $config -Scanned -RecoverySaved 2>&1
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'INSTALLER_OK') | Should Be $true
            $report = Get-Content -LiteralPath (Join-Path $base 'report\install-report.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            $report.status | Should Be 'success'
            (Test-Path -LiteralPath (Join-Path $base 'core.marker')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $base 'totp.marker')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
