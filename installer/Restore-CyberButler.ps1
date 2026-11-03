#requires -Version 5.1
<#
.SYNOPSIS
  Restore a Cyber-Butler backup created by Backup-CyberButler.ps1.

.DESCRIPTION
  Validates the manifest and every payload hash before writing. Supports a
  dry-run. It does not restore the signing private key or silently recreate
  removed external applications.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BackupPath,
    [string]$InstallPath = 'C:\CyberButler',
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$zip = [IO.Path]::GetFullPath($BackupPath)
if (-not (Test-Path -LiteralPath $zip)) { throw ('Backup not found: ' + $zip) }
$root = [IO.Path]::GetFullPath($InstallPath)
if (-not (Test-Path -LiteralPath $root)) { throw ('Install path not found: ' + $root) }
$staging = Join-Path ([IO.Path]::GetTempPath()) ('cbs-restore-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
try {
    Expand-Archive -LiteralPath $zip -DestinationPath $staging -Force -ErrorAction Stop
    $manifestPath = Join-Path $staging 'backup-manifest.json'
    if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'backup-manifest.json is missing' }
    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if (-not $manifest.files) { throw 'Backup manifest contains no files' }
    foreach ($entry in @($manifest.files)) {
        $rel = [string]$entry.path
        if ([string]::IsNullOrWhiteSpace($rel) -or $rel.Contains('..') -or [IO.Path]::IsPathRooted($rel)) {
            throw ('Unsafe path in backup manifest: ' + $rel)
        }
        $source = Join-Path $staging ($rel.Replace('/', '\'))
        if (-not (Test-Path -LiteralPath $source)) { throw ('Backup payload missing: ' + $rel) }
        $actual = (Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($actual -ne [string]$entry.sha256) { throw ('Backup hash mismatch: ' + $rel) }
        if ([long](Get-Item -LiteralPath $source).Length -ne [long]$entry.size) { throw ('Backup size mismatch: ' + $rel) }
    }
    $running = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and ([string]$_.ExecutablePath).StartsWith($root, [StringComparison]::OrdinalIgnoreCase)
    })
    if ($running.Count -gt 0 -and -not $DryRun) {
        if (-not $Force) { throw ('CBS processes are running under ' + $root + '; stop them or pass -Force') }
        foreach ($proc in $running) { try { Stop-Process -Id ([int]$proc.ProcessId) -Force -ErrorAction Stop } catch { } }
    }
    if ($DryRun) {
        Write-Output ('RESTORE_DRY_RUN files=' + @($manifest.files).Count + ' target=' + $root)
        return [pscustomobject]@{ dry_run = $true; files = @($manifest.files).Count; target = $root }
    }
    foreach ($entry in @($manifest.files)) {
        $rel = ([string]$entry.path).Replace('/', '\')
        $source = Join-Path $staging $rel
        $dest = Join-Path $root $rel
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $dest -Force
    }
    Write-Output ('RESTORE_OK files=' + @($manifest.files).Count + ' target=' + $root)
    return [pscustomobject]@{ dry_run = $false; files = @($manifest.files).Count; target = $root }
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
