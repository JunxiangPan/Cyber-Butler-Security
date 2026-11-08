$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Accounts.ps1')

function New-AccountTestResult {
    param(
        [bool]$Satisfied = $false,
        [bool]$Supported = $true,
        [bool]$CanManage = $true,
        [bool]$Exists = $false
    )
    return [pscustomobject]@{
        satisfied = $Satisfied
        supported = $Supported
        can_manage = $CanManage
        exists = $Exists
    }
}

Describe 'Installer account safety' {
    It 'skips when the account is already compliant' {
        $base = Join-Path $env:TEMP ('cb-account-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbAccountCalls = @{ create = 0; undo = 0 }
            $handlers = @{
                'accounts.test' = { param($c) New-AccountTestResult -Satisfied $true -Exists $true }
                'accounts.create' = { param($c) $global:cbAccountCalls.create++; [pscustomobject]@{ created = $true } }
                'accounts.undo' = { param($c) $global:cbAccountCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerAccountSetup -AccountName 'FakeSvc' -Approval 'APPROVE ACCOUNT' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'skipped'
            $global:cbAccountCalls.create | Should Be 0
            $global:cbAccountCalls.undo | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'creates a new account and records a delete reverse action' {
        $base = Join-Path $env:TEMP ('cb-account-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbAccountCalls = @{ create = 0; undo = 0 }
            $handlers = @{
                'accounts.test' = { param($c) New-AccountTestResult -Satisfied $false -Exists $false }
                'accounts.create' = { param($c) $global:cbAccountCalls.create++; [pscustomobject]@{ created = $true } }
                'accounts.assert' = { param($c) $true }
                'accounts.undo' = { param($c) $global:cbAccountCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerAccountSetup -AccountName 'FakeSvc' -Approval 'APPROVE ACCOUNT' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'completed'
            $result.changed | Should Be $true
            $global:cbAccountCalls.create | Should Be 1
            $step = Get-CyberButlerJournalStep -Journal $journal -Name 'account'
            $step.status | Should Be 'completed'
            $step.reverse_actions.Count | Should Be 1
            $step.reverse_actions[0].type | Should Be 'delete-created-account'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'runs Undo when Assert fails' {
        $base = Join-Path $env:TEMP ('cb-account-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbAccountCalls = @{ create = 0; undo = 0 }
            $handlers = @{
                'accounts.test' = { param($c) New-AccountTestResult -Satisfied $false -Exists $false }
                'accounts.create' = { param($c) $global:cbAccountCalls.create++; [pscustomobject]@{ created = $true } }
                'accounts.assert' = { param($c) $false }
                'accounts.undo' = { param($c) $global:cbAccountCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerAccountSetup -AccountName 'FakeSvc' -Approval 'APPROVE ACCOUNT' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'failed'
            $result.undo.action | Should Be 'removed'
            $global:cbAccountCalls.create | Should Be 1
            $global:cbAccountCalls.undo | Should Be 1
            (Get-CyberButlerJournalStep -Journal $journal -Name 'account').status | Should Be 'failed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'fails safe for existing non-compliant accounts' {
        $base = Join-Path $env:TEMP ('cb-account-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbAccountCalls = @{ create = 0; undo = 0 }
            $handlers = @{
                'accounts.test' = { param($c) New-AccountTestResult -Satisfied $false -Exists $true }
                'accounts.create' = { param($c) $global:cbAccountCalls.create++; [pscustomobject]@{ created = $true } }
                'accounts.undo' = { param($c) $global:cbAccountCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerAccountSetup -AccountName 'ExistingSvc' -Approval 'APPROVE ACCOUNT' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'existing_noncompliant'
            $global:cbAccountCalls.create | Should Be 0
            $global:cbAccountCalls.undo | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'fails safe on Windows Home style unsupported local-user management' {
        $base = Join-Path $env:TEMP ('cb-account-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $handlers = @{
                'accounts.test' = { param($c) New-AccountTestResult -Satisfied $false -Supported $false -Exists $false }
            }
            $result = Invoke-CyberButlerAccountSetup -AccountName 'FakeSvc' -Approval 'APPROVE ACCOUNT' -Handlers $handlers
            $result.status | Should Be 'unsupported'
            $result.exit_code | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'fails safe without administrator rights' {
        $base = Join-Path $env:TEMP ('cb-account-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbAccountCalls = @{ create = 0 }
            $handlers = @{
                'accounts.test' = { param($c) New-AccountTestResult -Satisfied $false -CanManage $false -Exists $false }
                'accounts.create' = { param($c) $global:cbAccountCalls.create++; [pscustomobject]@{ created = $true } }
            }
            $result = Invoke-CyberButlerAccountSetup -AccountName 'FakeSvc' -Approval 'APPROVE ACCOUNT' -Handlers $handlers
            $result.status | Should Be 'needs_elevation'
            $global:cbAccountCalls.create | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'returns NeedsApproval without executing under NonInteractive' {
        $base = Join-Path $env:TEMP ('cb-account-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbAccountCalls = @{ create = 0 }
            $handlers = @{
                'accounts.test' = { param($c) New-AccountTestResult -Satisfied $false -Exists $false }
                'accounts.create' = { param($c) $global:cbAccountCalls.create++; [pscustomobject]@{ created = $true } }
            }
            $result = Invoke-CyberButlerAccountSetup -AccountName 'FakeSvc' -NonInteractive -Handlers $handlers
            $result.status | Should Be 'needs_approval'
            $result.exit_code | Should Be 10
            $global:cbAccountCalls.create | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'plans without executing under PlanOnly' {
        $base = Join-Path $env:TEMP ('cb-account-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbAccountCalls = @{ create = 0 }
            $handlers = @{
                'accounts.test' = { param($c) New-AccountTestResult -Satisfied $false -Exists $false }
                'accounts.create' = { param($c) $global:cbAccountCalls.create++; [pscustomobject]@{ created = $true } }
            }
            $result = Invoke-CyberButlerAccountSetup -AccountName 'FakeSvc' -PlanOnly -Handlers $handlers
            $result.status | Should Be 'plan'
            $global:cbAccountCalls.create | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'does not delete a pre-existing account during Undo' {
        $result = Undo-CyberButlerAccount -AccountName 'ExistingSvc' -Created $false
        $result.action | Should Be 'none'
    }
}
