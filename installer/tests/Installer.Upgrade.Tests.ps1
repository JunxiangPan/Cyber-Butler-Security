$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Upgrade.ps1')

Describe 'Installer upgrade path gate' {
    It 'blocks a direct v1.6.2 -> v1.7.0 upgrade with the required message' {
        $result = Test-CyberButlerUpgradePath -PackageVersion '1.7.0' -InstalledVersion '1.6.2'
        $result.status | Should Be 'blocked'
        $result.message | Should Match 'upgrade to v1.6.3 first'
    }

    It 'requires v1.6.3 migration for a v1.6.2 install' {
        $result = Test-CyberButlerUpgradePath -PackageVersion '1.6.3' -InstalledVersion '1.6.2'
        $result.status | Should Be 'migration_required'
        $result.message | Should Match 'Migrate-v1.6.2-to-v1.6.3'
    }

    It 'allows v1.6.3 -> v1.7.0' {
        (Test-CyberButlerUpgradePath -PackageVersion '1.7.0' -InstalledVersion '1.6.3').status | Should Be 'ok'
    }

    It 'fails closed when a v1.7 installer cannot read the installed version' {
        (Test-CyberButlerUpgradePath -PackageVersion '1.7.0' -InstalledVersion '').status | Should Be 'blocked'
    }
}

Describe 'Cross-version backup and restore' {
    It 'creates a manifest-backed backup and dry-runs restore' {
        $base = Join-Path $env:TEMP ('cb-backup-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $base 'install\data') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $base 'install\data\memory.txt') -Value 'remember me' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $base 'install\VERSION') -Value '1.6.2' -Encoding ASCII
        $backupPath = Join-Path $base 'upgrade.zip'
        try {
            $backup = & (Join-Path $installerRoot 'Backup-CyberButler.ps1') -InstallPath (Join-Path $base 'install') -OutputPath $backupPath -Force
            (Test-Path -LiteralPath $backupPath) | Should Be $true
            $backup.files | Should BeGreaterThan 0
            $restore = & (Join-Path $installerRoot 'Restore-CyberButler.ps1') -BackupPath $backupPath -InstallPath (Join-Path $base 'install') -DryRun
            $restore.dry_run | Should Be $true
            ($restore.files -gt 0) | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
