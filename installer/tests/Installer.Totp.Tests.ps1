$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Totp.ps1')

Describe 'Installer TOTP safety' {
    It 'skips when TOTP material and vault ACL are already present' {
        $base = Join-Path $env:TEMP ('cb-totp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbTotpCalls = @{ generate = 0; undo = 0 }
            $handlers = @{
                'totp.test' = { param($c) [pscustomobject]@{ satisfied = $true; can_manage = $true } }
                'totp.generate' = { param($c) $global:cbTotpCalls.generate++; [pscustomobject]@{ created = $true } }
                'totp.undo' = { param($c) $global:cbTotpCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerTotp -Root $base -VaultPath (Join-Path $base 'vault') -ReaderAccount 'Reader' -AstrBotAccount 'AstrBot' -Approval 'APPROVE TOTP' -Scanned -RecoverySaved -Journal $journal -Handlers $handlers
            $result.status | Should Be 'skipped'
            $global:cbTotpCalls.generate | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'generates material, hardens ACL, and records reverse actions' {
        $base = Join-Path $env:TEMP ('cb-totp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $vault = Join-Path $base 'vault'
            $global:cbTotpAcl = Join-Path $base 'vault.clixml'
            Set-Content -LiteralPath $global:cbTotpAcl -Value 'fake-acl' -Encoding ASCII
            $global:cbTotpCalls = @{ generate = 0; undo = 0 }
            $handlers = @{
                'totp.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'totp.generate' = {
                    param($c)
                    $global:cbTotpCalls.generate++
                    New-Item -ItemType Directory -Path $c.VaultPath -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $c.VaultPath 'totp_secret.dpapi') -Value 'fake-secret' -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $c.VaultPath 'recovery_codes.txt') -Value 'fake-recovery' -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $c.VaultPath 'totp_qr.png') -Value 'fake-qr' -Encoding ASCII
                    [pscustomobject]@{ created = $true }
                }
                'totp.acl' = { param($c) $global:cbTotpAcl }
                'totp.assert' = { param($c) $true }
                'totp.undo' = { param($c) $global:cbTotpCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerTotp -Root $base -VaultPath $vault -ReaderAccount 'Reader' -AstrBotAccount 'AstrBot' -Approval 'APPROVE TOTP' -Scanned -RecoverySaved -Journal $journal -Handlers $handlers
            $result.status | Should Be 'completed'
            $result.changed | Should Be $true
            $global:cbTotpCalls.generate | Should Be 1
            $step = Get-CyberButlerJournalStep -Journal $journal -Name 'totp'
            $step.status | Should Be 'completed'
            $types = @($step.reverse_actions | ForEach-Object { $_.type })
            ($types -contains 'delete-created-file') | Should Be $true
            ($types -contains 'restore-acl') | Should Be $true
            $journalText = Get-Content -LiteralPath $journal.StatePath -Raw
            ($journalText -match 'fake-secret|fake-recovery|fake-qr') | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'returns the enrollment secret and recovery codes for display' {
        $base = Join-Path $env:TEMP ('cb-totp-display-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $handlers = @{
                'totp.generate' = {
                    param($c)
                    [pscustomobject]@{
                        created = $true
                        secret = 'JBSWY3DPEHPK3PXP'
                        uri = 'otpauth://totp/Cyber-Butler:owner?secret=JBSWY3DPEHPK3PXP'
                        recovery_codes = @('AAAA1111', 'BBBB2222', 'CCCC3333')
                    }
                }
            }
            $material = Show-CyberButlerTotpEnrollment -Root $base -VaultPath (Join-Path $base 'vault') -Issuer 'Cyber-Butler' -Account 'owner' -Handlers $handlers
            $material.secret | Should Be 'JBSWY3DPEHPK3PXP'
            @($material.recovery_codes).Count | Should Be 3
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'never denies the current installer account in the vault ACL' {
        $base = Join-Path $env:TEMP ('cb-totp-current-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $base 'vault') -Force | Out-Null
        try {
            $current = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            Set-CyberButlerTotpVaultAcl -VaultPath (Join-Path $base 'vault') -ReaderAccount 'BUILTIN\Administrators' -AstrBotAccount $current -RequireAstrBotDeny $false -Journal $journal | Out-Null
            $acl = Get-Acl -LiteralPath (Join-Path $base 'vault')
            $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            $denyCurrent = @($acl.Access | Where-Object {
                [string]$_.AccessControlType -eq 'Deny' -and
                ([string]$_.IdentityReference.Value -eq $current -or ([string]$_.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value -eq $currentSid))
            }).Count
            $denyCurrent | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'does not require an AstrBot deny for a single-account vault' {
        $base = Join-Path $env:TEMP ('cb-totp-acl-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $acl = Test-CyberButlerTotpVaultAcl -VaultPath $base -ReaderAccount 'BUILTIN\Administrators' -AstrBotAccount 'NT AUTHORITY\SYSTEM' -RequireAstrBotDeny $false
            $acl.satisfied | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'treats an access-denied path probe as present' {
        $denied = { param($p) throw [System.UnauthorizedAccessException]::new('denied') }
        (Test-CyberButlerPathExists -Path 'C:\denied' -AssumeExistsOnError -Probe $denied) | Should Be $true
        (Test-CyberButlerPathExists -Path 'C:\denied' -Probe $denied) | Should Be $false
    }

    It 'requires scanned and recovery confirmation after approval' {
        $base = Join-Path $env:TEMP ('cb-totp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbTotpCalls = @{ generate = 0 }
            $handlers = @{
                'totp.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'totp.generate' = { param($c) $global:cbTotpCalls.generate++; [pscustomobject]@{ created = $true } }
            }
            $result = Invoke-CyberButlerTotp -Root $base -VaultPath (Join-Path $base 'vault') -ReaderAccount 'Reader' -AstrBotAccount 'AstrBot' -Approval 'APPROVE TOTP' -Handlers $handlers
            $result.status | Should Be 'needs_confirmation'
            $result.exit_code | Should Be 10
            $global:cbTotpCalls.generate | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'returns NeedsApproval without executing under NonInteractive' {
        $base = Join-Path $env:TEMP ('cb-totp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbTotpCalls = @{ generate = 0 }
            $handlers = @{
                'totp.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'totp.generate' = { param($c) $global:cbTotpCalls.generate++; [pscustomobject]@{ created = $true } }
            }
            $result = Invoke-CyberButlerTotp -Root $base -VaultPath (Join-Path $base 'vault') -ReaderAccount 'Reader' -AstrBotAccount 'AstrBot' -NonInteractive -Handlers $handlers
            $result.status | Should Be 'needs_approval'
            $result.exit_code | Should Be 10
            $global:cbTotpCalls.generate | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'plans without generating under PlanOnly' {
        $base = Join-Path $env:TEMP ('cb-totp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbTotpCalls = @{ generate = 0 }
            $handlers = @{
                'totp.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'totp.generate' = { param($c) $global:cbTotpCalls.generate++; [pscustomobject]@{ created = $true } }
            }
            $result = Invoke-CyberButlerTotp -Root $base -VaultPath (Join-Path $base 'vault') -ReaderAccount 'Reader' -AstrBotAccount 'AstrBot' -PlanOnly -Handlers $handlers
            $result.status | Should Be 'plan'
            $global:cbTotpCalls.generate | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'runs Undo when Assert fails' {
        $base = Join-Path $env:TEMP ('cb-totp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $vault = Join-Path $base 'vault'
            $global:cbTotpAcl = Join-Path $base 'vault.clixml'
            Set-Content -LiteralPath $global:cbTotpAcl -Value 'fake-acl' -Encoding ASCII
            $global:cbTotpCalls = @{ undo = 0 }
            $handlers = @{
                'totp.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'totp.generate' = {
                    param($c)
                    New-Item -ItemType Directory -Path $c.VaultPath -Force | Out-Null
                    Set-Content -LiteralPath (Join-Path $c.VaultPath 'totp_secret.dpapi') -Value 'fake-secret' -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $c.VaultPath 'recovery_codes.txt') -Value 'fake-recovery' -Encoding ASCII
                    Set-Content -LiteralPath (Join-Path $c.VaultPath 'totp_qr.png') -Value 'fake-qr' -Encoding ASCII
                    [pscustomobject]@{ created = $true }
                }
                'totp.acl' = { param($c) $global:cbTotpAcl }
                'totp.assert' = { param($c) $false }
                'totp.undo' = { param($c) $global:cbTotpCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerTotp -Root $base -VaultPath $vault -ReaderAccount 'Reader' -AstrBotAccount 'AstrBot' -Approval 'APPROVE TOTP' -Scanned -RecoverySaved -Journal $journal -Handlers $handlers
            $result.status | Should Be 'failed'
            $result.undo.action | Should Be 'removed'
            $global:cbTotpCalls.undo | Should Be 1
            (Get-CyberButlerJournalStep -Journal $journal -Name 'totp').status | Should Be 'failed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'fails closed when the vault reader and AstrBot account are the same' {
        $base = Join-Path $env:TEMP ('cb-totp-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbTotpCalls = @{ generate = 0 }
            $handlers = @{
                'totp.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'totp.generate' = { param($c) $global:cbTotpCalls.generate++; [pscustomobject]@{ created = $true } }
            }
            $result = Invoke-CyberButlerTotp -Root $base -VaultPath (Join-Path $base 'vault') -ReaderAccount 'SameAccount' -AstrBotAccount 'SameAccount' -Approval 'APPROVE TOTP' -Scanned -RecoverySaved -Handlers $handlers
            $result.status | Should Be 'conflict'
            $result.exit_code | Should Be 20
            $global:cbTotpCalls.generate | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'keeps pre-existing or uncertain material for manual handling' {
        $paths = [pscustomobject]@{ secret = 'C:\fake\secret'; recovery = 'C:\fake\recovery'; qr = 'C:\fake\qr' }
        $handlers = @{ 'totp.undo' = { param($c) [pscustomobject]@{ action = 'manual' } } }
        $result = Undo-CyberButlerTotp -Paths $paths -Created $false -Uncertain $true -Handlers $handlers
        $result.action | Should Be 'manual'
    }
}
