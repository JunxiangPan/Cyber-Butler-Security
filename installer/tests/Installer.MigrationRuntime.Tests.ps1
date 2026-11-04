$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')

Describe 'v1.6.2 -> v1.6.3 migration backup' {
    It 'backs up user data before any service removal' {
        $base = Join-Path $env:TEMP ('cb-migrate-' + [guid]::NewGuid().ToString('N'))
        $root = Join-Path $base 'CyberButler'
        New-Item -ItemType Directory -Path (Join-Path $root 'data') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'AstrBot\data') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'SnowLuma\config') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'tools\totp-vault') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'webui\data') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'VERSION') -Value '1.6.2' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $root 'data\keep.txt') -Value 'cbs-data' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $root 'AstrBot\data\memory.txt') -Value 'memory' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $root 'SnowLuma\config\webui.json') -Value '{}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $root 'tools\totp-vault\secret') -Value 'secret' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $root 'webui\data\webui.db') -Value 'db' -Encoding UTF8
        $backup = Join-Path $base 'preupgrade.zip'
        try {
            $result = & (Join-Path $installerRoot 'Migrate-v1.6.2-to-v1.6.3.ps1') `
                -InstallPath $root -BackupPath $backup -BackupOnly
            $result.status | Should Be 'backup_done'
            (Test-Path -LiteralPath $backup) | Should Be $true
            $extract = Join-Path $base 'extract'
            Expand-Archive -LiteralPath $backup -DestinationPath $extract -Force
            (Get-Content -LiteralPath (Join-Path $extract 'data\keep.txt') -Raw).Trim() | Should Be 'cbs-data'
            (Get-Content -LiteralPath (Join-Path $extract 'AstrBot\data\memory.txt') -Raw).Trim() | Should Be 'memory'
            (Get-Content -LiteralPath (Join-Path $extract 'tools\totp-vault\secret') -Raw).Trim() | Should Be 'secret'
            $manifest = Get-Content -LiteralPath (Join-Path $extract 'backup-manifest.json') -Raw | ConvertFrom-Json
            @($manifest.files).Count | Should BeGreaterThan 0
            $dry = & (Join-Path $installerRoot 'Restore-CyberButler.ps1') -BackupPath $backup -InstallPath $root -DryRun
            $dry.dry_run | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'does not recreate or delete data when already at 1.6.3' {
        $base = Join-Path $env:TEMP ('cb-migrate-noop-' + [guid]::NewGuid().ToString('N'))
        $root = Join-Path $base 'CyberButler'
        New-Item -ItemType Directory -Path (Join-Path $root 'data') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'VERSION') -Value '1.6.3' -Encoding ASCII
        try {
            $result = & (Join-Path $installerRoot 'Migrate-v1.6.2-to-v1.6.3.ps1') -InstallPath $root -BackupOnly
            $result.status | Should Be 'not_required'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
