#requires -Version 5.1
<#
.SYNOPSIS
  Windows acceptance probe for Two-Stage Delayed Delete ACL isolation.

.DESCRIPTION
  Creates a disposable staging entry, applies the SYSTEM-only ACL, and probes:
    * current desktop user read -> Access Denied
    * SYSTEM scheduled-task read -> success
    * SYSTEM scheduled-task secure purge -> success
    * CyberButlerSvc deny ACE -> recorded (credentialed read is SKIP unless
      -ServiceAccountPassword is supplied)

  The SYSTEM probe runs the installed Broker Python and its quarantine module,
  so it tests the real runtime instead of a PowerShell-only imitation.

  Run elevated on a disposable VM. It does not touch live CBS data.
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [string]$InstallRoot = 'C:\CyberButler',
    [Security.SecureString]$ServiceAccountPassword = $null
)

$ErrorActionPreference = 'Stop'
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'Run this acceptance probe as administrator.'
}
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Join-Path $env:ProgramData ('CyberButler/acl-accept-' + [guid]::NewGuid().ToString('N'))
}
$root = [IO.Path]::GetFullPath($Root)
$entry = Join-Path $root 'trash_staging\acceptance-request'
$payload = Join-Path $entry 'payload.txt'
$manifestPath = Join-Path $entry 'manifest.json'
$systemRead = Join-Path $root 'system-read.txt'
$systemPurge = Join-Path $root 'system-purge.txt'
$probeScript = Join-Path $root 'system-probe.ps1'
$taskName = 'CBS-Trash-Acceptance-' + [guid]::NewGuid().ToString('N')
$python = Join-Path $InstallRoot 'webui\.venv\Scripts\python.exe'
$tools = Join-Path $InstallRoot 'tools'
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
    if (-not (Test-Path -LiteralPath $python)) { throw "missing installed Python: $python" }
    if (-not (Test-Path -LiteralPath (Join-Path $tools 'quarantine.py'))) { throw "missing quarantine.py under $tools" }

    New-Item -ItemType Directory -Path $entry -Force | Out-Null
    Set-Content -LiteralPath $payload -Value 'acceptance-secret' -Encoding UTF8
    [ordered]@{
        request_id = 'acceptance-request'
        original_path = $payload
        quarantine_path = $payload
        state = 'pending_delete'
        expires_epoch = 0
        expires_at = 'expired-for-acceptance'
        size = (Get-Item -LiteralPath $payload).Length
    } | ConvertTo-Json | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    # SYSTEM-side probe. It reads the denied payload, then calls the real
    # quarantine purge with the same staging layout as production.
    $probe = @'
param(
    [string]$Source,
    [string]$Entry,
    [string]$Staging,
    [string]$ReadOut,
    [string]$PurgeOut,
    [string]$Python,
    [string]$Tools
)
$ErrorActionPreference = 'Stop'
try {
    Get-Content -LiteralPath $Source -Raw -ErrorAction Stop |
        Set-Content -LiteralPath $ReadOut -Encoding UTF8 -ErrorAction Stop
    $code = @"
import sys
from pathlib import Path
sys.path.insert(0, r'$Tools')
import quarantine
quarantine.TRASH_STAGING = Path(r'$Staging')
quarantine.purge_expired(secure=True)
Path(r'$PurgeOut').write_text('PURGED' if not Path(r'$Entry').exists() else 'NOT_PURGED', encoding='utf-8')
"@
    & $Python -c $code 2>&1 | Set-Content -LiteralPath ($PurgeOut + '.log') -Encoding UTF8
} catch {
    $_ | Out-String | Set-Content -LiteralPath ($PurgeOut + '.err') -Encoding UTF8
    exit 1
}
'@
    Set-Content -LiteralPath $probeScript -Value $probe -Encoding UTF8

    $owner = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    & icacls.exe $entry /inheritance:r /grant:r '*S-1-5-18:(OI)(CI)(F)' `
        /deny "${owner}:(R,W,D)" /deny 'CyberButlerSvc:(R,W,D)' | Out-Null
    & icacls.exe $payload /inheritance:r /grant:r '*S-1-5-18:(F)' `
        /deny "${owner}:(R,W,D)" /deny 'CyberButlerSvc:(R,W,D)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'icacls failed' }
    $result.service_deny_ace = ((& icacls.exe $entry | Out-String) -match 'CyberButlerSvc')

    try {
        $null = Get-Content -LiteralPath $payload -Raw -ErrorAction Stop
        $result.owner_read_denied = $false
        $result.notes += 'Owner read unexpectedly succeeded; this probe may be running as SYSTEM.'
    } catch {
        $result.owner_read_denied = $true
    }

    $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (
        '-NoProfile -ExecutionPolicy Bypass -File "' + $probeScript + '"' +
        ' -Source "' + $payload + '"' +
        ' -Entry "' + $entry + '"' +
        ' -Staging "' + (Join-Path $root 'trash_staging') + '"' +
        ' -ReadOut "' + $systemRead + '"' +
        ' -PurgeOut "' + $systemPurge + '"' +
        ' -Python "' + $python + '"' +
        ' -Tools "' + $tools + '"'
    )
    $principal = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 2)
    Register-ScheduledTask -TaskName $taskName -Action $action -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $systemPurge)) { Start-Sleep -Milliseconds 500 }
    $taskInfo = Get-ScheduledTaskInfo -TaskName $taskName -ErrorAction SilentlyContinue
    $result.notes += ('task_result: ' + [string]$taskInfo.LastTaskResult)

    if ((Test-Path -LiteralPath $systemRead) -and ((Get-Content -LiteralPath $systemRead -Raw).Trim() -eq 'acceptance-secret')) {
        $result.system_read_ok = $true
    } else {
        $readText = if (Test-Path -LiteralPath $systemRead) { (Get-Content -LiteralPath $systemRead -Raw) } else { 'missing' }
        $result.notes += ('system_read: ' + $readText)
    }

    $purgeText = if (Test-Path -LiteralPath $systemPurge) { (Get-Content -LiteralPath $systemPurge -Raw).Trim() } else { '' }
    $result.secure_purge_ok = ($purgeText -eq 'PURGED' -and -not (Test-Path -LiteralPath $entry))
    $result.notes += ('purge: ' + $purgeText)

    if ($ServiceAccountPassword) {
        $cred = New-Object System.Management.Automation.PSCredential('CyberButlerSvc', $ServiceAccountPassword)
        try {
            $probeProcess = Start-Process -FilePath 'powershell.exe' -Credential $cred -WindowStyle Hidden -PassThru -Wait `
                -ArgumentList @('-NoProfile', '-Command', 'Get-Content -LiteralPath ''' + $payload + ''' -Raw')
            $result.service_read = if ($probeProcess.ExitCode -eq 0) { 'SUCCEEDED (FAIL)' } else { 'DENIED' }
        } catch {
            $result.service_read = 'DENIED'
        }
    }
} catch {
    $result.notes += ('error: ' + $_.Exception.Message)
} finally {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    $probeFailed = -not ($result.owner_read_denied -and $result.system_read_ok -and $result.secure_purge_ok)
    if ($probeFailed) {
        $result.notes += ('kept_for_diagnostics: ' + $root)
    } else {
    if (Test-Path -LiteralPath $entry) {
        & takeown.exe /f $entry /a /r /d Y | Out-Null
        & icacls.exe $entry /reset /t /c | Out-Null
        Remove-Item -LiteralPath $entry -Recurse -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$result | ConvertTo-Json -Depth 6
if (-not ($result.owner_read_denied -and $result.system_read_ok -and $result.secure_purge_ok)) { exit 1 }
