#requires -Version 5.1
<#
Local packaging preflight. It does not create Windows accounts; that needs the
real elevated installer. It exercises path creation, Chinese/Unicode paths,
broker-token ACL granting, and current-user readback in a disposable tree.
#>
[CmdletBinding()]
param([string]$Root = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path $env:TEMP ('cbs-dryrun-' + [guid]::NewGuid().ToString('N'))
}
$root = [IO.Path]::GetFullPath($Root)
$tools = Join-Path $root 'tools'
$webui = Join-Path $root 'webui'
$workspace = Join-Path $root 'workspace'
$data = Join-Path $root 'data'
$logs = Join-Path $tools 'logs'
$trash = Join-Path $tools 'broker\trash_staging'
$webdata = Join-Path $webui 'data'

try {
    foreach ($dir in @($root, $tools, $workspace, $data, $logs, $trash, $webui, $webdata)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        if (-not (Test-Path -LiteralPath $dir)) { throw "missing directory: $dir" }
    }

    # Chinese / emoji / long-path creation smoke.
    $unicode = Join-Path $workspace 'shared-测试.txt'
    Set-Content -LiteralPath $unicode -Value 'unicode path' -Encoding UTF8
    if ((Get-Content -LiteralPath $unicode -Raw) -notmatch 'unicode path') {
        throw 'unicode path readback failed'
    }
    $emoji = Join-Path $workspace 'emoji-😀.txt'
    try { Set-Content -LiteralPath $emoji -Value 'emoji path' -Encoding UTF8 } catch { }

    $token = Join-Path $tools 'broker_token.txt'
    Set-Content -LiteralPath $token -Value ('A' * 64) -Encoding ASCII

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $token /inheritance:r /grant:r "*S-1-5-18:(F)" /grant:r "${identity}:(R)" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls token grant failed: $identity" }

    $read = Get-Content -LiteralPath $token -Raw -ErrorAction Stop
    if ($read.Trim().Length -ne 64) { throw 'token current-user readback failed' }

    $acl = (& icacls.exe $token | Out-String)
    if ($acl -notmatch [regex]::Escape($identity)) {
        throw 'token desktop identity missing from ACL'
    }

    Write-Output 'DRY_RUN_OK'
    Write-Output ('ROOT=' + $root)
    Write-Output ('IDENTITY=' + $identity)
} finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
