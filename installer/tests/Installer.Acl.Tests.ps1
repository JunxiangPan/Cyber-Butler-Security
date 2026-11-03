$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Acl.ps1')

function New-AclTestResult {
    param(
        [bool]$Satisfied = $false,
        [bool]$Exists = $true,
        [bool]$CanManage = $true
    )
    return [pscustomobject]@{
        satisfied = $Satisfied
        exists = $Exists
        can_manage = $CanManage
    }
}

Describe 'Installer ACL safety' {
    It 'skips when the ACL already satisfies the request' {
        $base = Join-Path $env:TEMP ('cb-acl-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbAclCalls = @{ backup = 0; apply = 0; undo = 0 }
            $handlers = @{
                'acl.test' = { param($c) New-AclTestResult -Satisfied $true }
                'acl.backup' = { param($c) $global:cbAclCalls.backup++; $null }
                'acl.apply' = { param($c) $global:cbAclCalls.apply++; $true }
                'acl.undo' = { param($c) $global:cbAclCalls.undo++; [pscustomobject]@{ action = 'restored' } }
            }
            $result = Invoke-CyberButlerAcl -Path $base -Identity 'Test\Fake' -Mode RX -Approval 'APPROVE ACL' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'skipped'
            $global:cbAclCalls.apply | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'backs up and applies an ACL, recording a restore action' {
        $base = Join-Path $env:TEMP ('cb-acl-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbAclBackup = Join-Path $base 'acl.clixml'
            Set-Content -LiteralPath $global:cbAclBackup -Value 'fake-acl' -Encoding ASCII
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbAclCalls = @{ backup = 0; apply = 0; undo = 0 }
            $handlers = @{
                'acl.test' = { param($c) New-AclTestResult -Satisfied $false }
                'acl.backup' = { param($c) $global:cbAclCalls.backup++; $global:cbAclBackup }
                'acl.apply' = { param($c) $global:cbAclCalls.apply++; $true }
                'acl.assert' = { param($c) $true }
                'acl.undo' = { param($c) $global:cbAclCalls.undo++; [pscustomobject]@{ action = 'restored' } }
            }
            $result = Invoke-CyberButlerAcl -Path $base -Identity 'Test\Fake' -Mode RX -Approval 'APPROVE ACL' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'completed'
            $result.changed | Should Be $true
            $global:cbAclCalls.backup | Should Be 1
            $global:cbAclCalls.apply | Should Be 1
            $step = Get-CyberButlerJournalStep -Journal $journal -Name 'acl'
            $step.status | Should Be 'completed'
            $step.reverse_actions.Count | Should Be 1
            $step.reverse_actions[0].type | Should Be 'restore-acl'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'runs Undo when Assert fails' {
        $base = Join-Path $env:TEMP ('cb-acl-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbAclBackup = Join-Path $base 'acl.clixml'
            Set-Content -LiteralPath $global:cbAclBackup -Value 'fake-acl' -Encoding ASCII
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbAclCalls = @{ undo = 0 }
            $handlers = @{
                'acl.test' = { param($c) New-AclTestResult -Satisfied $false }
                'acl.backup' = { param($c) $global:cbAclBackup }
                'acl.apply' = { param($c) $true }
                'acl.assert' = { param($c) $false }
                'acl.undo' = { param($c) $global:cbAclCalls.undo++; [pscustomobject]@{ action = 'restored' } }
            }
            $result = Invoke-CyberButlerAcl -Path $base -Identity 'Test\Fake' -Mode RW -Approval 'APPROVE ACL' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'failed'
            $result.undo.action | Should Be 'restored'
            $global:cbAclCalls.undo | Should Be 1
            (Get-CyberButlerJournalStep -Journal $journal -Name 'acl').status | Should Be 'failed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'returns NeedsApproval without executing under NonInteractive' {
        $base = Join-Path $env:TEMP ('cb-acl-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbAclCalls = @{ apply = 0 }
            $handlers = @{
                'acl.test' = { param($c) New-AclTestResult -Satisfied $false }
                'acl.apply' = { param($c) $global:cbAclCalls.apply++; $true }
            }
            $result = Invoke-CyberButlerAcl -Path $base -Identity 'Test\Fake' -Mode RX -NonInteractive -Handlers $handlers
            $result.status | Should Be 'needs_approval'
            $result.exit_code | Should Be 10
            $global:cbAclCalls.apply | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'plans without backup or apply under PlanOnly' {
        $base = Join-Path $env:TEMP ('cb-acl-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbAclCalls = @{ backup = 0; apply = 0 }
            $handlers = @{
                'acl.test' = { param($c) New-AclTestResult -Satisfied $false }
                'acl.backup' = { param($c) $global:cbAclCalls.backup++; $null }
                'acl.apply' = { param($c) $global:cbAclCalls.apply++; $true }
            }
            $result = Invoke-CyberButlerAcl -Path $base -Identity 'Test\Fake' -Mode RX -PlanOnly -Handlers $handlers
            $result.status | Should Be 'plan'
            $global:cbAclCalls.backup | Should Be 0
            $global:cbAclCalls.apply | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'lists only core outputs and excludes the later TOTP vault' {
        $targets = @(Get-CyberButlerAclTargets -InstallPath 'C:\CyberButler')
        $targets.Count | Should Be 4
        ($targets -join ';') | Should Not Match 'AstrBot'
        ($targets -join ';') | Should Not Match 'SnowLuma'
        ($targets -join ';') | Should Match 'tools'
        ($targets -join ';') | Should Match 'webui'
        ($targets -join ';') | Should Match 'data'
        ($targets -join ';') | Should Match 'workspace'
        ($targets -join ';') | Should Not Match 'totp-vault'
    }

    It 'reports the missing ACL target path explicitly' {
        $missing = Join-Path $env:TEMP ('cb-acl-missing-' + [guid]::NewGuid().ToString('N'))
        $result = Invoke-CyberButlerAcl -Path $missing -Identity 'Test\Fake' -Mode RX
        $result.status | Should Be 'failed'
        ([string]$result.message).Contains($missing) | Should Be $true
    }

    It 'restores an ACL through the Undo handler' {
        $global:cbAclCalls = @{ undo = 0 }
        $handlers = @{
            'acl.undo' = { param($c) $global:cbAclCalls.undo++; [pscustomobject]@{ action = 'restored' } }
        }
        $result = Undo-CyberButlerAcl -Path 'C:\fake' -BackupPath 'C:\fake.clixml' -Handlers $handlers
        $result.action | Should Be 'restored'
        $global:cbAclCalls.undo | Should Be 1
    }
}
