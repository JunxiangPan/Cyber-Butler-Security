$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Secrets.ps1')

Describe 'Installer secrets safety' {
    It 'skips when all secret files and ACLs are already satisfied' {
        $base = Join-Path $env:TEMP ('cb-secrets-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbSecretCalls = @{ write = 0; undo = 0 }
            $handlers = @{
                'secrets.test' = { param($c) [pscustomobject]@{ satisfied = $true; can_manage = $true } }
                'secrets.write' = { param($c) $global:cbSecretCalls.write++; $true }
                'secrets.undo' = { param($c) $global:cbSecretCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $api = ConvertTo-SecureString 'fake-api-key' -AsPlainText -Force
            $smtp = ConvertTo-SecureString 'fake-smtp' -AsPlainText -Force
            $result = Invoke-CyberButlerSecrets -Root $base -ReaderAccount 'Reader' -OwnerQQ '<QQ>' -ApiKey $api -SmtpSecret $smtp -Approval 'APPROVE SECRETS' -Handlers $handlers
            $result.status | Should Be 'skipped'
            $global:cbSecretCalls.write | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'fails fast when stdin is not interactive' {
        $base = Join-Path $env:TEMP ('cb-secrets-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $handlers = @{
                'secrets.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'secrets.write' = { param($c) $true }
                'secrets.acl' = { param($c) $true }
            }
            $result = Invoke-CyberButlerSecrets -Root $base -ReaderAccount 'Reader' -OwnerQQ '<QQ>' -Approval 'APPROVE SECRETS' -StdinInteractive $false -Handlers $handlers
            $result.status | Should Be 'needs_configuration'
            $result.message | Should Match 'stdin is not interactive; pass -ApiKey / -SmtpSecret instead'
            $result.exit_code | Should Be (Get-InstallerExitCode -Name ValidationFailed)
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'writes fake secret files and never records the secret values' {
        $base = Join-Path $env:TEMP ('cb-secrets-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbSecretAcl = Join-Path $base 'secret.clixml'
            Set-Content -LiteralPath $global:cbSecretAcl -Value 'fake-acl' -Encoding ASCII
            $global:cbSecretCalls = @{ write = 0; undo = 0 }
            $handlers = @{
                'secrets.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'secrets.write' = {
                    param($c)
                    $global:cbSecretCalls.write++
                    New-Item -ItemType Directory -Path (Split-Path -Parent $c.Path) -Force | Out-Null
                    Set-Content -LiteralPath $c.Path -Value 'fake-secret-bytes' -Encoding ASCII
                    $true
                }
                'secrets.acl' = { param($c) $global:cbSecretAcl }
                'secrets.assert' = { param($c) $true }
                'secrets.undo' = { param($c) $global:cbSecretCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $api = ConvertTo-SecureString 'fake-api-key-value' -AsPlainText -Force
            $smtp = ConvertTo-SecureString 'fake-smtp-password' -AsPlainText -Force
            $result = Invoke-CyberButlerSecrets -Root $base -ReaderAccount 'Reader' -OwnerQQ '<QQ>' -ApiKey $api -SmtpSecret $smtp -Approval 'APPROVE SECRETS' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'completed'
            $result.changed | Should Be $true
            $global:cbSecretCalls.write | Should Be 3
            $step = Get-CyberButlerJournalStep -Journal $journal -Name 'secrets'
            $step.status | Should Be 'completed'
            $types = @($step.reverse_actions | ForEach-Object { $_.type })
            ($types -contains 'delete-created-file') | Should Be $true
            ($types -contains 'restore-acl') | Should Be $true
            $journalText = Get-Content -LiteralPath $journal.StatePath -Raw
            ($journalText -match 'fake-api-key-value|fake-smtp-password') | Should Be $false
            $resultText = $result | ConvertTo-Json -Depth 6
            ($resultText -match 'fake-api-key-value|fake-smtp-password') | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'accepts plaintext ApiKey and SmtpSecret parameters' {
        $base = Join-Path $env:TEMP ('cb-secrets-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbSecretAcl = Join-Path $base 'secret.clixml'
            Set-Content -LiteralPath $global:cbSecretAcl -Value 'fake-acl' -Encoding ASCII
            $handlers = @{
                'secrets.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'secrets.write' = { param($c) New-Item -ItemType Directory -Path (Split-Path -Parent $c.Path) -Force | Out-Null; Set-Content -LiteralPath $c.Path -Value 'fake' -Encoding ASCII; $true }
                'secrets.acl' = { param($c) $global:cbSecretAcl }
                'secrets.assert' = { param($c) $true }
            }
            $result = Invoke-CyberButlerSecrets -Root $base -ReaderAccount 'Reader' -OwnerQQ '<QQ>' -ApiKey 'sk-plain' -SmtpSecret 'smtp-plain' -Approval 'APPROVE SECRETS' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'completed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'allows skipping missing secrets interactively and records PARTIAL' {
        $base = Join-Path $env:TEMP ('cb-secrets-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbSecretAcl = Join-Path $base 'secret.clixml'
            Set-Content -LiteralPath $global:cbSecretAcl -Value 'fake-acl' -Encoding ASCII
            $global:cbSecretCalls = @{ write = 0 }
            $handlers = @{
                'secrets.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'secrets.write' = { param($c) $global:cbSecretCalls.write++; New-Item -ItemType Directory -Path (Split-Path -Parent $c.Path) -Force | Out-Null; Set-Content -LiteralPath $c.Path -Value 'fake' -Encoding ASCII; $true }
                'secrets.acl' = { param($c) $global:cbSecretAcl }
            }
            $emptyReader = { New-Object Security.SecureString }
            $result = Invoke-CyberButlerSecrets -Root $base -ReaderAccount 'Reader' -OwnerQQ '<QQ>' -Approval 'APPROVE SECRETS' -Reader $emptyReader -Journal $journal -Handlers $handlers
            $result.status | Should Be 'skipped'
            $result.partial | Should Be $true
            ([string]$result.message) | Should Match 'ApiKey: PARTIAL'
            $statusPath = Join-Path $base 'tools\secrets-status.json'
            (Test-Path -LiteralPath $statusPath) | Should Be $true
            $status = Get-Content -LiteralPath $statusPath -Raw | ConvertFrom-Json
            $status.api_key | Should Match 'PARTIAL'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'runs Undo when Assert fails' {
        $base = Join-Path $env:TEMP ('cb-secrets-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbSecretAcl = Join-Path $base 'secret.clixml'
            Set-Content -LiteralPath $global:cbSecretAcl -Value 'fake-acl' -Encoding ASCII
            $global:cbSecretCalls = @{ write = 0; undo = 0 }
            $handlers = @{
                'secrets.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'secrets.write' = { param($c) $global:cbSecretCalls.write++; New-Item -ItemType Directory -Path (Split-Path -Parent $c.Path) -Force | Out-Null; Set-Content -LiteralPath $c.Path -Value 'fake' -Encoding ASCII; $true }
                'secrets.acl' = { param($c) $global:cbSecretAcl }
                'secrets.assert' = { param($c) $false }
                'secrets.undo' = { param($c) $global:cbSecretCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $api = ConvertTo-SecureString 'fake-api' -AsPlainText -Force
            $smtp = ConvertTo-SecureString 'fake-smtp' -AsPlainText -Force
            $result = Invoke-CyberButlerSecrets -Root $base -ReaderAccount 'Reader' -OwnerQQ '<QQ>' -ApiKey $api -SmtpSecret $smtp -Approval 'APPROVE SECRETS' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'failed'
            $result.undo.action | Should Be 'removed'
            $global:cbSecretCalls.undo | Should Be 1
            (Get-CyberButlerJournalStep -Journal $journal -Name 'secrets').status | Should Be 'failed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'returns NeedsApproval without executing under NonInteractive' {
        $base = Join-Path $env:TEMP ('cb-secrets-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbSecretCalls = @{ write = 0 }
            $handlers = @{
                'secrets.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'secrets.write' = { param($c) $global:cbSecretCalls.write++; $true }
            }
            $api = ConvertTo-SecureString 'fake-api' -AsPlainText -Force
            $smtp = ConvertTo-SecureString 'fake-smtp' -AsPlainText -Force
            $result = Invoke-CyberButlerSecrets -Root $base -ReaderAccount 'Reader' -OwnerQQ '<QQ>' -ApiKey $api -SmtpSecret $smtp -NonInteractive -Handlers $handlers
            $result.status | Should Be 'needs_approval'
            $result.exit_code | Should Be 10
            $global:cbSecretCalls.write | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'plans without writing under PlanOnly' {
        $base = Join-Path $env:TEMP ('cb-secrets-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbSecretCalls = @{ write = 0 }
            $handlers = @{
                'secrets.test' = { param($c) [pscustomobject]@{ satisfied = $false; can_manage = $true } }
                'secrets.write' = { param($c) $global:cbSecretCalls.write++; $true }
            }
            $api = ConvertTo-SecureString 'fake-api' -AsPlainText -Force
            $smtp = ConvertTo-SecureString 'fake-smtp' -AsPlainText -Force
            $result = Invoke-CyberButlerSecrets -Root $base -ReaderAccount 'Reader' -OwnerQQ '<QQ>' -ApiKey $api -SmtpSecret $smtp -PlanOnly -Handlers $handlers
            $result.status | Should Be 'plan'
            $global:cbSecretCalls.write | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'restores through the Undo handler' {
        $handlers = @{ 'secrets.undo' = { param($c) [pscustomobject]@{ action = 'restored' } } }
        $result = Undo-CyberButlerSecrets -Root 'C:\fake' -Created $false -Handlers $handlers
        $result.action | Should Be 'restored'
    }
}
