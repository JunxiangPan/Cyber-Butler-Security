$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
$scriptPath = Join-Path $installerRoot 'Install-CyberButler.ps1'
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')

function New-JournalTestRoot {
    $base = Join-Path $env:TEMP ('cb-journal-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    return $base
}

Describe 'Installer journal lifecycle' {
    It 'creates a run id and state.json' {
        $base = New-JournalTestRoot
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath (Join-Path $base 'install') -Tier Medium
            $journal.RunId.Length | Should BeGreaterThan 10
            (Test-Path -LiteralPath $journal.StatePath) | Should Be $true
            $journal.State.status | Should Be 'running'
            $journal.State.schema | Should Be 1
            (Test-Path -LiteralPath $journal.BackupRoot) | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'updates step status and supports resume from the unfinished step' {
        $base = New-JournalTestRoot
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath (Join-Path $base 'install') -Tier Medium
            Add-CyberButlerJournalStep -Journal $journal -Name 'step-a' -Status completed | Out-Null
            Add-CyberButlerJournalStep -Journal $journal -Name 'step-b' -Status in_progress | Out-Null
            Add-CyberButlerJournalStep -Journal $journal -Name 'step-c' -Status pending | Out-Null

            $read = Read-CyberButlerJournal -StatePath $journal.StatePath
            ($read.State.steps | Where-Object { $_.name -eq 'step-a' }).status | Should Be 'completed'
            ($read.State.steps | Where-Object { $_.name -eq 'step-b' }).status | Should Be 'in_progress'

            $resume = Get-CyberButlerResumeStep -Journal $read
            $resume.name | Should Be 'step-b'
            $resume.status | Should Be 'in_progress'

            Add-CyberButlerJournalStep -Journal $read -Name 'step-b' -Status completed | Out-Null
            $next = Get-CyberButlerResumeStep -Journal $read
            $next.name | Should Be 'step-c'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'preserves completed step output on rollback' {
        $base = New-JournalTestRoot
        try {
            $install = Join-Path $base 'install'
            New-Item -ItemType Directory -Path $install -Force | Out-Null
            $file = Join-Path $install 'config.txt'
            Set-Content -LiteralPath $file -Value 'original' -Encoding ASCII

            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $install -Tier Medium
            Add-CyberButlerJournalStep -Journal $journal -Name 'files' -Status in_progress | Out-Null
            $newDir = Join-Path $install 'created-by-installer'
            New-CyberButlerTrackedDirectory -Journal $journal -Step 'files' -Path $newDir -AllowedRoot $install | Out-Null
            Backup-CyberButlerFile -Journal $journal -Step 'files' -Path $file -AllowedRoot $install | Out-Null
            Set-Content -LiteralPath $file -Value 'changed' -Encoding ASCII
            Add-CyberButlerJournalStep -Journal $journal -Name 'files' -Status completed | Out-Null

            $result = Invoke-CyberButlerRollback -Journal $journal
            $result.status | Should Be 'rolled_back'
            $result.errors.Count | Should Be 0
            $result.executed.Count | Should Be 0
            (Test-Path -LiteralPath $newDir) | Should Be $true
            (Get-Content -LiteralPath $file -Raw).Trim() | Should Be 'changed'

            $read = Read-CyberButlerJournal -StatePath $journal.StatePath
            $read.State.status | Should Be 'rolled_back'
            ($read.State.steps | Where-Object { $_.name -eq 'files' }).status | Should Be 'completed'
            ($read.State.steps | Where-Object { $_.name -eq 'files' }).details.undo.status | Should Be 'preserved'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'still removes a failed step created by the installer' {
        $base = New-JournalTestRoot
        try {
            $install = Join-Path $base 'install'
            New-Item -ItemType Directory -Path $install -Force | Out-Null
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $install -Tier Medium
            Add-CyberButlerJournalStep -Journal $journal -Name 'core' -Status failed | Out-Null
            $newDir = Join-Path $install 'partial-core'
            New-CyberButlerTrackedDirectory -Journal $journal -Step 'core' -Path $newDir -AllowedRoot $install | Out-Null

            $result = Invoke-CyberButlerRollback -Journal $journal
            $result.status | Should Be 'rolled_back'
            $result.errors.Count | Should Be 0
            $result.executed.Count | Should Be 1
            (Test-Path -LiteralPath $newDir) | Should Be $false
            $read = Read-CyberButlerJournal -StatePath $journal.StatePath
            ($read.State.steps | Where-Object { $_.name -eq 'core' }).status | Should Be 'failed'
            ($read.State.steps | Where-Object { $_.name -eq 'core' }).details.undo.status | Should Be 'completed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'keeps Core output when Services fails during rollback' {
        $base = New-JournalTestRoot
        try {
            $install = Join-Path $base 'install'
            $astrbot = Join-Path $install 'ExternalAgent'
            New-Item -ItemType Directory -Path $astrbot -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $astrbot 'main.py') -Value 'fixture' -Encoding ASCII

            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $install -Tier Medium
            Add-CyberButlerJournalStep -Journal $journal -Name 'core' -Status completed | Out-Null
            Add-CyberButlerReverseAction -Journal $journal -Step 'core' -Action ([pscustomobject]@{
                type = 'delete-created-directory'
                path = $astrbot
                allowed_root = $install
            })
            Add-CyberButlerJournalStep -Journal $journal -Name 'services' -Status failed | Out-Null
            Add-CyberButlerReverseAction -Journal $journal -Step 'services' -Action ([pscustomobject]@{
                type = 'delete-created-scheduled-task'
                task_name = 'ExternalAgent Service'
            })

            $result = Invoke-CyberButlerRollback -Journal $journal -Handlers @{
                'delete-created-scheduled-task' = { param($action) }
            }
            $result.status | Should Be 'rolled_back'
            (Test-Path -LiteralPath (Join-Path $astrbot 'main.py')) | Should Be $true
            (Test-Path -LiteralPath $astrbot) | Should Be $true
            $read = Read-CyberButlerJournal -StatePath $journal.StatePath
            ($read.State.steps | Where-Object { $_.name -eq 'core' }).status | Should Be 'completed'
            ($read.State.steps | Where-Object { $_.name -eq 'services' }).status | Should Be 'failed'
            ($read.State.steps | Where-Object { $_.name -eq 'core' }).details.undo.status | Should Be 'preserved'
            ($read.State.steps | Where-Object { $_.name -eq 'services' }).details.undo.status | Should Be 'completed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'supports ACL and scheduled-task restore actions with handlers' {
        $base = New-JournalTestRoot
        try {
            $install = Join-Path $base 'install'
            New-Item -ItemType Directory -Path $install -Force | Out-Null
            $file = Join-Path $install 'acl-target.txt'
            Set-Content -LiteralPath $file -Value 'acl' -Encoding ASCII

            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $install -Tier Medium
            Add-CyberButlerJournalStep -Journal $journal -Name 'security' -Status failed | Out-Null
            $aclBackup = Backup-CyberButlerAcl -Journal $journal -Step 'security' -Path $file
            (Test-Path -LiteralPath $aclBackup) | Should Be $true

            $taskDir = Join-Path $journal.BackupRoot 'tasks'
            New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
            $taskXml = Join-Path $taskDir 'fake.xml'
            Set-Content -LiteralPath $taskXml -Value '<Task />' -Encoding UTF8
            Add-CyberButlerReverseAction -Journal $journal -Step 'security' -Action ([pscustomobject]@{
                type = 'restore-scheduled-task'
                task_name = 'Fake Task'
                backup = $taskXml
            })

            $step = Get-CyberButlerJournalStep -Journal $journal -Name 'security'
            $types = @($step.reverse_actions | ForEach-Object { $_.type })
            ($types -contains 'restore-acl') | Should Be $true
            ($types -contains 'restore-scheduled-task') | Should Be $true

            $handlers = @{
                'restore-acl' = { param($action) }
                'restore-scheduled-task' = { param($action) }
            }
            $result = Invoke-CyberButlerRollback -Journal $journal -Handlers $handlers
            $result.status | Should Be 'rolled_back'
            $result.errors.Count | Should Be 0
            $executedTypes = @($result.executed | ForEach-Object { $_.type })
            ($executedTypes -contains 'restore-acl') | Should Be $true
            ($executedTypes -contains 'restore-scheduled-task') | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'supports the installer -Resume switch' {
        $base = New-JournalTestRoot
        try {
            $install = Join-Path $base 'install'
            New-Item -ItemType Directory -Path $install -Force | Out-Null
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $install -Tier Medium
            Add-CyberButlerJournalStep -Journal $journal -Name 'prepare' -Status completed | Out-Null
            Add-CyberButlerJournalStep -Journal $journal -Name 'build' -Status in_progress | Out-Null

            $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Resume -StatePath $journal.StatePath 2>&1
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'RESUME next=build') | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'supports the installer -Rollback switch' {
        $base = New-JournalTestRoot
        try {
            $install = Join-Path $base 'install'
            New-Item -ItemType Directory -Path $install -Force | Out-Null
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $install -Tier Medium
            Add-CyberButlerJournalStep -Journal $journal -Name 'build' -Status in_progress | Out-Null
            $created = Join-Path $install 'created-by-install'
            New-CyberButlerTrackedDirectory -Journal $journal -Step 'build' -Path $created -AllowedRoot $install | Out-Null
            Add-CyberButlerJournalStep -Journal $journal -Name 'build' -Status failed | Out-Null

            $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Rollback -StatePath $journal.StatePath 2>&1
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'ROLLBACK rolled_back') | Should Be $true
            (Test-Path -LiteralPath $created) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
