$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Firewall.ps1')

function New-FirewallTestResult {
    param(
        [bool]$Satisfied = $false,
        [bool]$Supported = $true,
        [bool]$CanManage = $true,
        [bool]$Exists = $false,
        $State = $null
    )
    return [pscustomobject]@{
        satisfied = $Satisfied
        supported = $Supported
        can_manage = $CanManage
        exists = $Exists
        state = $State
    }
}

Describe 'Installer firewall safety' {
    It 'skips when the firewall rule already matches' {
        $base = Join-Path $env:TEMP ('cb-fw-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbFwCalls = @{ apply = 0; undo = 0 }
            $handlers = @{
                'firewall.test' = { param($c) New-FirewallTestResult -Satisfied $true -Exists $true }
                'firewall.apply' = { param($c) $global:cbFwCalls.apply++; [pscustomobject]@{ created = $false } }
                'firewall.undo' = { param($c) $global:cbFwCalls.undo++; [pscustomobject]@{ action = 'restored' } }
            }
            $result = Invoke-CyberButlerFirewallRule -RuleName 'Fake Rule' -Approval 'APPROVE FIREWALL' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'skipped'
            $global:cbFwCalls.apply | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'creates a new rule and records a delete reverse action' {
        $base = Join-Path $env:TEMP ('cb-fw-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbFwCalls = @{ apply = 0; undo = 0 }
            $handlers = @{
                'firewall.test' = { param($c) New-FirewallTestResult -Satisfied $false -Exists $false }
                'firewall.apply' = { param($c) $global:cbFwCalls.apply++; [pscustomobject]@{ created = $true } }
                'firewall.assert' = { param($c) $true }
                'firewall.undo' = { param($c) $global:cbFwCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerFirewallRule -RuleName 'Fake Rule' -Approval 'APPROVE FIREWALL' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'completed'
            $result.created | Should Be $true
            $global:cbFwCalls.apply | Should Be 1
            $step = Get-CyberButlerJournalStep -Journal $journal -Name 'firewall'
            $step.status | Should Be 'completed'
            $step.reverse_actions[0].type | Should Be 'delete-created-firewall-rule'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'restores an existing rule and records a restore action' {
        $base = Join-Path $env:TEMP ('cb-fw-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $previous = [pscustomobject]@{ enabled = 'False'; direction = 'Inbound'; action = 'Block'; profile = 'Public'; remote_address = 'Any'; port = '8765'; protocol = 'TCP' }
            $global:cbFwCalls = @{ apply = 0; undo = 0 }
            $handlers = @{
                'firewall.test' = { param($c) New-FirewallTestResult -Satisfied $false -Exists $true -State $previous }
                'firewall.apply' = { param($c) $global:cbFwCalls.apply++; [pscustomobject]@{ created = $false } }
                'firewall.assert' = { param($c) $true }
                'firewall.undo' = { param($c) $global:cbFwCalls.undo++; [pscustomobject]@{ action = 'restored' } }
            }
            $result = Invoke-CyberButlerFirewallRule -RuleName 'Fake Rule' -Approval 'APPROVE FIREWALL' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'completed'
            $step = Get-CyberButlerJournalStep -Journal $journal -Name 'firewall'
            $step.reverse_actions[0].type | Should Be 'restore-firewall-rule'
            $step.reverse_actions[0].state.enabled | Should Be 'False'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'runs Undo when Assert fails' {
        $base = Join-Path $env:TEMP ('cb-fw-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbFwCalls = @{ apply = 0; undo = 0 }
            $handlers = @{
                'firewall.test' = { param($c) New-FirewallTestResult -Satisfied $false -Exists $false }
                'firewall.apply' = { param($c) $global:cbFwCalls.apply++; [pscustomobject]@{ created = $true } }
                'firewall.assert' = { param($c) $false }
                'firewall.undo' = { param($c) $global:cbFwCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerFirewallRule -RuleName 'Fake Rule' -Approval 'APPROVE FIREWALL' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'failed'
            $result.undo.action | Should Be 'removed'
            $global:cbFwCalls.undo | Should Be 1
            (Get-CyberButlerJournalStep -Journal $journal -Name 'firewall').status | Should Be 'failed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'returns NeedsApproval without executing under NonInteractive' {
        $base = Join-Path $env:TEMP ('cb-fw-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbFwCalls = @{ apply = 0 }
            $handlers = @{
                'firewall.test' = { param($c) New-FirewallTestResult -Satisfied $false }
                'firewall.apply' = { param($c) $global:cbFwCalls.apply++; [pscustomobject]@{ created = $true } }
            }
            $result = Invoke-CyberButlerFirewallRule -RuleName 'Fake Rule' -NonInteractive -Handlers $handlers
            $result.status | Should Be 'needs_approval'
            $result.exit_code | Should Be 10
            $global:cbFwCalls.apply | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'plans without applying under PlanOnly' {
        $base = Join-Path $env:TEMP ('cb-fw-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbFwCalls = @{ apply = 0 }
            $handlers = @{
                'firewall.test' = { param($c) New-FirewallTestResult -Satisfied $false }
                'firewall.apply' = { param($c) $global:cbFwCalls.apply++; [pscustomobject]@{ created = $true } }
            }
            $result = Invoke-CyberButlerFirewallRule -RuleName 'Fake Rule' -PlanOnly -Handlers $handlers
            $result.status | Should Be 'plan'
            $global:cbFwCalls.apply | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'restores through the Undo handler' {
        $global:cbFwCalls = @{ undo = 0 }
        $handlers = @{
            'firewall.undo' = { param($c) $global:cbFwCalls.undo++; [pscustomobject]@{ action = 'restored' } }
        }
        $result = Undo-CyberButlerFirewallRule -RuleName 'Fake Rule' -Created $false -PreviousState ([pscustomobject]@{ enabled = 'True' }) -Handlers $handlers
        $result.action | Should Be 'restored'
        $global:cbFwCalls.undo | Should Be 1
    }
}
