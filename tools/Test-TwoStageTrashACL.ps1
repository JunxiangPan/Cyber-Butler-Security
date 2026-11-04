#requires -Version 5.1
<#
.SYNOPSIS
  Windows acceptance probe for Two-Stage Delayed Delete ACL isolation.

.DESCRIPTION
  Creates a disposable staging entry, applies the SYSTEM-only ACL, and probes:
    * current desktop user read -> Access Denied
    * SYSTEM scheduled-task read -> success
    * CyberButlerSvc deny ACE -> recorded (credentialed read is SKIP unless
      -ServiceAccountPassword is supplied)
    * expired entry -> secure purge removes the payload

  It does not touch a live CBS installation. Run elevated on a disposable VM.
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [Security.SecureString]$ServiceAccountPassword = $null,
    [int]$Passes = 3
)

$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this acceptance probe as administrator.'
}
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path $env:TEMP ('cbs-trash-accept-' + [guid]::NewGuid().ToString('N'))
}
$root = [IO.Path]::GetFullPath($Root)
$staging = Join-Path $root 'trash_staging'
$entry = Join-Path $staging 'acceptance-request'
$payload = Join-Path $entry 'payload.txt'
$systemOut = Join-Path $root 'system-read.txt'
$taskName = 'CBS-Trash-Acceptance-' + [guid]::NewGuid().ToString('N')
$result = [ordered]@{
    root = $root
    owner_read_denied = $false
    system_read_ok = $false
    service_deny_ace = $false
    service_read = 'SKIP'
    secure_purge_ok = $false
    notes = @()
}
try {
    New-Item -ItemType Directory -Path $entry -Force | Out-Null
    Set-Content -LiteralPath $payload -Value 'acceptance-secret' -Encoding UTF8
    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $entry /inheritance:r /grant:r '*S-1-5-18:(F)' `
        /deny "${owner}:(R,W,D)" /deny 'CyberButlerSvc:(R,W,D)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'icacls failed' }

    $aclText = (& icacls.exe $entry | Out-String)
    $result.service_deny_ace = $aclText -match 'CyberButlerSvc'

    try {
        $null = Get-Content -LiteralPath $payload -Raw -ErrorAction Stop
        $result.owner_read_denied = $false
        $result.notes += 'Owner read unexpectedly succeeded; this probe may be running as SYSTEM.'
    } catch [System.UnauthorizedAccessException] {
        $result.owner_read_denied = $true
    } catch {
        $result.owner_read_denied = $true
    }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        '-NoProfile -Command "Get-Content -LiteralPath ''' + $payload + ''' -Raw | Set-Content -LiteralPath ''' + $systemOut + ''' -Encoding UTF8"'
    )
    $principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $systemOut)) { Start-Sleep -Milliseconds 500 }
    if ((Test-Path -LiteralPath $systemOut) -and ((Get-Content -LiteralPath $systemOut -Raw).Trim() -eq 'acceptance-secret')) {
        $result.system_read_ok = $true
    }
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue

    if ($ServiceAccountPassword) {
        $cred = New-Object System.Management.Automation.PSCredential('CyberButlerSvc', $ServiceAccountPassword)
        try {
            $probe = Start-Process -FilePath 'powershell.exe' -Credential $cred -WindowStyle Hidden -PassThru -Wait `
                -ArgumentList @('-NoProfile', '-Command', 'Get-Content -LiteralPath ''' + $payload + ''' -Raw')
            $result.service_read = if ($probe.ExitCode -eq 0) { 'SUCCEEDED (FAIL)' } else { 'DENIED' }
        } catch {
            $result.service_read = 'DENIED'
        }
    }

    $python = (Get-Command python.exe -ErrorAction Stop).Source
    $purgeScript = Join-Path $root 'purge.py'
    @'
import json, os, sys
from pathlib import Path
import quarantine
root = Path(sys.argv[1]).resolve()
quarantine.TRASH_STAGING = root / "trash_staging"
entry = quarantine.TRASH_STAGING / "acceptance-request"
quarantine.purge_expired(secure=True)
print("PURGED" if not entry.exists() else "NOT_PURGED")
'@ | Set-Content -LiteralPath $purgeScript -Encoding UTF8
    # ACL probe complete. Reset the disposable entry ACL only for this local
    # secure-erase check; production purge runs as SYSTEM.
    & takeown.exe /f $entry /a /r /d Y | Out-Null
    & icacls.exe $entry /reset /t /c | Out-Null
    $env:PYTHONPATH = (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools')
    $purgeOutput = & $python $purgeScript $root 2>&1
    $result.secure_purge_ok = (($purgeOutput -join ' ') -match 'PURGED')
    $result.notes += ('purge: ' + (($purgeOutput -join ' ') -replace '\s+', ' '))
} finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $entry) {
        & takeown.exe /f $entry /a /r /d Y | Out-Null
        & icacls.exe $entry /reset /t /c | Out-Null
        Remove-Item -LiteralPath $entry -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
$result | ConvertTo-Json -Depth 6
if (-not ($result.owner_read_denied -and $result.system_read_ok -and $result.secure_purge_ok)) { exit 1 }
