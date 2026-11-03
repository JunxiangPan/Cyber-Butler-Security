param(
    [Parameter(Mandatory = $true)][string]$Root,
    [string]$ServiceAccount = 'CyberButlerSvc',
    [string]$ServiceAccountPassword = '',
    [switch]$ProbeOnly
)

$ErrorActionPreference = 'Stop'
$data = Join-Path $Root 'ExternalAgent\data'
if (-not (Test-Path -LiteralPath $data)) { throw "ExternalAgent data directory missing: $data" }
$svc = if ($ServiceAccount -match '\\') { $ServiceAccount } else { $env:COMPUTERNAME + '\' + $ServiceAccount }
$pluginsProbe = Join-Path $data 'plugins\astrbot_plugin_totp_broker\main.py'
$t2iProbe = Join-Path $data 't2i_templates\base.html'

function Invoke-AclStep([string]$label, [string[]]$arguments) {
    Write-Host ("ACL: " + $label)
    & takeown.exe @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Host ("ACL WARN: " + $label + " exit=" + $LASTEXITCODE) }
}

if (-not $ProbeOnly) {
    Write-Host ("Repairing ExternalAgent data ACL: " + $data)
    # 1. Take ownership of the whole data tree. This is intentionally the
    # first operation: inherited/denied ACEs can otherwise survive every grant.
    & takeown.exe /f $data /r /d y | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "takeown failed for $data" }

    # 2. Re-enable inheritance, then reset inherited/child ACLs.
    & icacls.exe $data /inheritance:e /t /c | Out-Null
    & icacls.exe $data /reset /t /c | Out-Null

    # 3. Re-apply explicit access. W is required for Python __pycache__ and
    # SQLite WAL/temp files; RX alone is not enough for plugin imports.
    & icacls.exe $data /grant:r "${svc}:(OI)(CI)M" /t /c | Out-Null
    & icacls.exe $data /grant:r 'NT AUTHORITY\SYSTEM:(OI)(CI)F' /t /c | Out-Null
    & icacls.exe $data /grant:r 'BUILTIN\Administrators:(OI)(CI)F' /t /c | Out-Null

    # 4. Logs must be writable, not just readable.
    $logs = Join-Path $data 'logs'
    if (Test-Path -LiteralPath $logs) {
        & icacls.exe $logs /grant:r "${svc}:(OI)(CI)M" /t /c | Out-Null
    }
}

# A probe that actually runs as the service account. Start-Process -Credential
# can be unavailable when the account has SeDenyInteractiveLogonRight; the
# caller still gets a deterministic ACL check in that case.
$probeDir = Join-Path $env:ProgramData 'CyberButler\acl-probe'
New-Item -ItemType Directory -Force -Path $probeDir | Out-Null
$probeScript = Join-Path $probeDir 'read-probe.ps1'
$probeResult = Join-Path $probeDir 'read-probe.json'
$probeCode = @"
`$ErrorActionPreference = 'Stop'
try {
    `$p = Get-Content -LiteralPath '$($pluginsProbe.Replace("'", "''"))' -Raw -Encoding UTF8
    `$t = Get-Content -LiteralPath '$($t2iProbe.Replace("'", "''"))' -Raw -Encoding UTF8
    [ordered]@{ ok = (`$p.Length -gt 0 -and `$t.Length -gt 0); plugin_bytes = `$p.Length; t2i_bytes = `$t.Length } |
        ConvertTo-Json | Set-Content -LiteralPath '$($probeResult.Replace("'", "''"))' -Encoding UTF8
    exit 0
} catch {
    [ordered]@{ ok = `$false; error = `$_.Exception.Message } |
        ConvertTo-Json | Set-Content -LiteralPath '$($probeResult.Replace("'", "''"))' -Encoding UTF8
    exit 1
}
"@
Set-Content -LiteralPath $probeScript -Value $probeCode -Encoding UTF8
& icacls.exe $probeDir /grant:r "${svc}:(OI)(CI)M" 'NT AUTHORITY\SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' /t /c | Out-Null
Remove-Item -LiteralPath $probeResult -Force -ErrorAction SilentlyContinue

$probeLaunched = $false
if ($ServiceAccountPassword) {
    try {
        $secure = ConvertTo-SecureString $ServiceAccountPassword -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential($svc, $secure)
        $proc = Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $probeScript) `
            -Credential $cred -WindowStyle Hidden -Wait -PassThru
        $probeLaunched = $true
        $probeExit = $proc.ExitCode
    } catch {
        Write-Host ('ACL probe could not launch as service account: ' + $_.Exception.Message)
    }
}

if ($probeLaunched) {
    $result = if (Test-Path -LiteralPath $probeResult) {
        Get-Content -LiteralPath $probeResult -Raw -Encoding UTF8 | ConvertFrom-Json
    } else { $null }
    if (-not $result -or -not $result.ok) {
        $detail = if ($result -and $result.error) { [string]$result.error } else { 'probe returned no success result' }
        throw ('服务账户读取插件失败，ACL 重置未生效: ' + $detail)
    }
    Write-Host ('ACL PROBE OK plugin_bytes=' + $result.plugin_bytes + ' t2i_bytes=' + $result.t2i_bytes)
} else {
    # Deterministic fallback: resolve the service SID and verify it has read
    # access on both probe files. This cannot fully replace a live token, but
    # it prevents installs that are known to be unreadable by the service.
    Write-Host 'ACL probe running as administrator; checking service SID access instead.'
    $account = New-Object System.Security.Principal.NTAccount($svc)
    $sid = $account.Translate([System.Security.Principal.SecurityIdentifier]).Value
    foreach ($path in @($pluginsProbe, $t2iProbe)) {
        $acl = Get-Acl -LiteralPath $path
        $allowed = @($acl.Access | Where-Object {
            $_.AccessControlType -eq 'Allow' -and
            $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq $sid -and
            (($_.FileSystemRights -band [System.Security.AccessControl.FileSystemRights]::ReadData) -ne 0)
        }).Count -gt 0
        if (-not $allowed) { throw ('服务账户读取插件失败，ACL 重置未生效: no read ACE for ' + $svc + ' on ' + $path) }
    }
    Write-Host 'ACL PROBE OK (SID fallback)'
}

if ($ProbeOnly) { Write-Host 'ACL PROBE ONLY complete.' }
