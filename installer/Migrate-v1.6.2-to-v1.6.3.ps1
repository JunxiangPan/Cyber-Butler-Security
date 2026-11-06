#requires -Version 5.1
<#
.SYNOPSIS
  Migrate a v1.6.2 Cyber-Butler installation to the v1.6.3 independent model.

.DESCRIPTION
  This is the only supported bridge from v1.6.2 to v1.6.3.
  1. Back up user data with integrity manifest.
  2. Optionally stop and delete the retired CyberButlerAgentRuntime SCM service.
  3. Print the exact external-Agent reinstall/connection guide.

  It does not install AgentRuntime, AuxRuntime, or any other external application,
  and it does not delete AgentRuntime/AuxRuntime data directories.
#>
[CmdletBinding()]
param(
    [string]$InstallPath = 'C:\CyberButler',
    [string]$BackupPath = '',
    [switch]$BackupOnly,
    [switch]$RemoveLegacyService,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($InstallPath)
$versionPath = Join-Path $root 'VERSION'
if (-not (Test-Path -LiteralPath $versionPath)) { throw ('VERSION not found: ' + $versionPath) }
$installed = (Get-Content -LiteralPath $versionPath -Raw -Encoding UTF8).Trim()
try { $installedVersion = [version]$installed } catch { throw ('Invalid installed VERSION: ' + $installed) }
if ($installedVersion -ge [version]'1.6.3') {
    Write-Output ('MIGRATION_NOT_REQUIRED version=' + $installed)
    return [pscustomobject]@{ status = 'not_required'; version = $installed }
}

$backupScript = Join-Path $PSScriptRoot 'Backup-CyberButler.ps1'
if (-not (Test-Path -LiteralPath $backupScript)) { throw ('Backup script missing: ' + $backupScript) }
if ([string]::IsNullOrWhiteSpace($BackupPath)) {
    $BackupPath = Join-Path (Split-Path -Parent $root) ('CyberButler-v1.6.2-preupgrade-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
}
Write-Output ('MIGRATION_BACKUP_START ' + $BackupPath)
$backup = & $backupScript -InstallPath $root -OutputPath $BackupPath -Force:$Force
if (-not $backup -or -not $backup.path) { throw 'Backup did not return a path' }
Write-Output ('MIGRATION_BACKUP_OK path=' + $backup.path + ' sha256=' + $backup.sha256 + ' files=' + $backup.files)
if ($BackupOnly) {
    return [pscustomobject]@{ status = 'backup_done'; backup = $backup }
}

$serviceName = 'CyberButlerAgentRuntime'
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Output ('LEGACY_SCM_DETECTED ' + $serviceName + ' status=' + $service.Status)
    if (-not $RemoveLegacyService) {
        Write-Output 'LEGACY_SCM_REMOVAL_REQUIRED Re-run with -RemoveLegacyService after confirming the backup.'
        Write-Output ('RESTORE_COMMAND powershell -File "' + (Join-Path $PSScriptRoot 'Restore-CyberButler.ps1') + '" -BackupPath "' + $backup.path + '" -InstallPath "' + $root + '" -DryRun')
        return [pscustomobject]@{ status = 'backup_done_service_removal_required'; backup = $backup; service = $serviceName }
    }
    try { Stop-Service -Name $serviceName -Force -ErrorAction Stop } catch { Write-Verbose 'optional operation failed' }
    try { & sc.exe delete $serviceName | Out-Null } catch { Write-Verbose 'optional operation failed' }
    Start-Sleep -Seconds 2
    if (Get-Service -Name $serviceName -ErrorAction SilentlyContinue) {
        throw ('Could not remove legacy SCM service: ' + $serviceName + '. Reboot and rerun.')
    }
    Write-Output ('LEGACY_SCM_REMOVED ' + $serviceName)
} else {
    Write-Output 'LEGACY_SCM_ABSENT'
}

Write-Output 'MIGRATION_EXTERNAL_AGENT_GUIDE'
Write-Output '1. Install AgentRuntime (or another agent) separately under its own installer/account.'
Write-Output '2. Do not re-register it as CyberButlerAgentRuntime.'
Write-Output '3. Point the agent at the CBS Broker on http://127.0.0.1:18090/.'
Write-Output '4. Read docs/API_SPEC.md for the standard integration contract.'
Write-Output '5. CBS no longer manages the external application or its data directory.'
Write-Output ('BACKUP_KEEP ' + $backup.path)
Write-Output ('RESTORE_DRY_RUN powershell -File "' + (Join-Path $PSScriptRoot 'Restore-CyberButler.ps1') + '" -BackupPath "' + $backup.path + '" -InstallPath "' + $root + '" -DryRun')
return [pscustomobject]@{ status = 'migrated'; backup = $backup; external_agent = 'manual'; service_removed = [bool]$service }
