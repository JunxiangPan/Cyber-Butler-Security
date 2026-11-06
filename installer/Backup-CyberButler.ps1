#requires -Version 5.1
<#
.SYNOPSIS
  Create an integrity-checked backup of Cyber-Butler user data.

.DESCRIPTION
  Copies only user-owned state into a temporary staging directory, writes a
  SHA-256 manifest, and creates a timestamped ZIP. It never includes the
  release signing private key. The archive is not encrypted; protect it as a
  secret and move it offline.
#>
[CmdletBinding()]
param(
    [string]$InstallPath = 'C:\CyberButler',
    [string]$OutputPath = '',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($InstallPath)
if (-not (Test-Path -LiteralPath $root)) { throw ('Install path not found: ' + $root) }
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path (Split-Path -Parent $root) ('CyberButler-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip')
}
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) { throw ('Backup already exists: ' + $OutputPath) }
$parent = Split-Path -Parent $OutputPath
if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
$staging = Join-Path ([IO.Path]::GetTempPath()) ('cbs-backup-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $staging -Force | Out-Null
$manifest = New-Object System.Collections.Generic.List[object]

try {
    $targets = @(
        @{ Source = (Join-Path $root 'AgentRuntime\data'); Dest = 'AgentRuntime/data' },
        @{ Source = (Join-Path $root 'AuxRuntime\config'); Dest = 'AuxRuntime/config' },
        @{ Source = (Join-Path $root 'AuxRuntime\data'); Dest = 'AuxRuntime/data' },
        @{ Source = (Join-Path $root 'AuxRuntime\logs'); Dest = 'AuxRuntime/logs' },
        @{ Source = (Join-Path $root 'tools\totp-vault'); Dest = 'tools/totp-vault' },
        @{ Source = (Join-Path $root 'webui\data'); Dest = 'webui/data' },
        @{ Source = (Join-Path $root 'data'); Dest = 'data' }
    )
    foreach ($target in $targets) {
        if (-not (Test-Path -LiteralPath $target.Source)) { continue }
        $source = $target.Source
        foreach ($file in @(Get-ChildItem -LiteralPath $source -Recurse -File -ErrorAction Stop)) {
            if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $relative = $file.FullName.Substring($source.Length).TrimStart('\')
            $destRelative = Join-Path $target.Dest $relative
            $dest = Join-Path $staging $destRelative
            New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
            [IO.File]::Copy($file.FullName, $dest, $true)
            $manifest.Add([pscustomobject]@{
                path = $destRelative.Replace('\', '/')
                size = [long]$file.Length
                sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            })
        }
    }
    foreach ($single in @(
        @{ Path = (Join-Path $root 'tools\broker_config.json'); Dest = 'tools/broker_config.json' },
        @{ Path = (Join-Path $root 'tools\broker_token.txt'); Dest = 'tools/broker_token.txt' }
    )) {
        if (-not (Test-Path -LiteralPath $single.Path)) { continue }
        $dest = Join-Path $staging $single.Dest
        New-Item -ItemType Directory -Path (Split-Path -Parent $dest) -Force | Out-Null
        Copy-Item -LiteralPath $single.Path -Destination $dest -Force
        $manifest.Add([pscustomobject]@{
            path = $single.Dest.Replace('\', '/')
            size = [long](Get-Item -LiteralPath $single.Path).Length
            sha256 = (Get-FileHash -LiteralPath $single.Path -Algorithm SHA256).Hash.ToLowerInvariant()
        })
    }
    $manifestObject = [pscustomobject]@{
        schema = 1
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        install_path = $root
        version = if (Test-Path -LiteralPath (Join-Path $root 'VERSION')) { (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw -Encoding UTF8).Trim() } else { '' }
        files = @($manifest | Sort-Object path)
    }
    $manifestPath = Join-Path $staging 'backup-manifest.json'
    $manifestObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $OutputPath -CompressionLevel Optimal -Force
    # Restrict the archive to the current user, SYSTEM and Administrators.
    $acl = New-Object System.Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($identity in @([Security.Principal.WindowsIdentity]::GetCurrent().Name, 'NT AUTHORITY\SYSTEM', 'BUILTIN\Administrators')) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($identity, 'FullControl', 'Allow')))
    }
    Set-Acl -LiteralPath $OutputPath -AclObject $acl
    $hash = (Get-FileHash -LiteralPath $OutputPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $fileCount = [int]$manifest.Count
    return [pscustomobject]@{ path = $OutputPath; sha256 = $hash; files = $fileCount; manifest = $manifestObject }
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
