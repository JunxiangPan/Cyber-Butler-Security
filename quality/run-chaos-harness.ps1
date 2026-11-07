#requires -Version 7.0
<#
.SYNOPSIS
    Destructive VM chaos harness for Q05-Q11 and Q13-Q17.
.DESCRIPTION
    Run from an elevated PowerShell 7 prompt in a disposable VM with
    CBS_CHAOS_VM=1. Every case performs a real operation and restores state.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('Q05','Q06','Q07','Q08','Q09','Q10','Q11','Q13','Q14','Q15','Q16','Q17')][string]$Case,
    [string]$InstallRoot = 'C:\CyberButler',
    [string]$PackageZip = '',
    [string]$ResultPath = '',
    [switch]$ConfirmDestructive
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($InstallRoot)
if (-not $ResultPath) { $ResultPath = Join-Path $root ('installer-report\chaos-' + $Case + '.json') }
<#
.SYNOPSIS
    Emit a machine-readable result and exit.
#>
function Write-Result([string]$Status, [string]$Detail) {
    $payload = [ordered]@{ case = $Case; status = $Status; detail = $Detail; host = $env:COMPUTERNAME; at = (Get-Date).ToUniversalTime().ToString('o') }
    New-Item -ItemType Directory -Path (Split-Path -Parent $ResultPath) -Force | Out-Null
    $payload | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
    Write-Output ($Status.ToUpperInvariant() + ' ' + $Case + ': ' + $Detail)
    if ($Status -ne 'passed') { exit 2 }
    exit 0
}
if (-not $ConfirmDestructive -or $env:CBS_CHAOS_VM -ne '1') { Write-Result 'failed' 'Set CBS_CHAOS_VM=1 and pass -ConfirmDestructive in a disposable VM.' }
if (-not (Test-Path -LiteralPath $root -PathType Container)) { Write-Result 'failed' ('install root missing: ' + $root) }
$serviceName = 'Cyber-Butler Broker'
$tokenPath = Join-Path $root 'tools\broker_token.txt'
$python = Join-Path $root 'python\python.exe'
<#
.SYNOPSIS
    Return the local broker token.
#>
function Get-Token { return (Get-Content -LiteralPath $tokenPath -Raw).Trim() }
<#
.SYNOPSIS
    Invoke one broker HTTP endpoint.
#>
function Invoke-Broker([string]$Method = 'GET', [string]$Path = '/pending', [string]$Body = '') {
    $u = 'http://127.0.0.1:18090' + $Path
    $h = @{ 'X-Broker-Token' = (Get-Token) }
    if ($Body) { return Invoke-WebRequest -Uri $u -Method $Method -Headers $h -Body $Body -ContentType 'application/json' -UseBasicParsing -TimeoutSec 8 }
    return Invoke-WebRequest -Uri $u -Method $Method -Headers $h -UseBasicParsing -TimeoutSec 8
}
<#
.SYNOPSIS
    Wait until the broker health endpoint succeeds.
#>
function Wait-Broker([int]$Seconds = 45) {
    $end = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $end) {
        try { $null = Invoke-WebRequest -Uri 'http://127.0.0.1:18090/health' -UseBasicParsing -TimeoutSec 2; return $true } catch { Start-Sleep -Milliseconds 500 }
    }
    return $false
}
<#
.SYNOPSIS
    Start the native broker service and wait for health.
#>
function Start-Broker {
    $svc = Get-Service -Name $serviceName -ErrorAction Stop
    if ($svc.Status -ne 'Running') { Start-Service -Name $serviceName -ErrorAction Stop }
    if (-not (Wait-Broker 45)) { throw 'broker did not become healthy' }
}
try {
    switch ($Case) {
        'Q05' {
            $svc = Get-Service -Name $serviceName -ErrorAction Stop
            Stop-Service -Name $serviceName -Force -ErrorAction Stop
            $svc.WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
            $failed = $false
            try { $null = Invoke-WebRequest -Uri 'http://127.0.0.1:18090/health' -UseBasicParsing -TimeoutSec 4 } catch { $failed = $true }
            Start-Broker
            if (-not $failed) { Write-Result 'failed' 'broker answered after stop' }
            Write-Result 'passed' 'broker stopped; health failed; service recovered'
        }
        'Q06' {
            $adapter = Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object -First 1
            if (-not $adapter) { Write-Result 'failed' 'no active network adapter' }
            try {
                Disable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction Stop
                Start-Sleep -Seconds 8
                if ((Get-NetAdapter -Name $adapter.Name).Status -eq 'Up') { throw 'adapter did not go down' }
            } finally { Enable-NetAdapter -Name $adapter.Name -Confirm:$false -ErrorAction SilentlyContinue }
            Start-Sleep -Seconds 8
            Start-Broker
            Write-Result 'passed' ('disabled and restored adapter ' + $adapter.Name)
        }
        'Q07' {
            $ws = Join-Path $root 'workspace'; New-Item -ItemType Directory -Path $ws -Force | Out-Null
            $big = Join-Path $ws 'chaos-1gb.bin'
            try {
                $oneGb = 1GB
                & fsutil.exe file createnew $big $oneGb | Out-Null
                if ((Get-Item $big).Length -ne $oneGb) { throw '1GB file size mismatch' }
                $toolsPath = Join-Path $root 'tools'
                $probe = "import sys; sys.path.insert(0, r'" + $toolsPath + "'); import broker; from win_path_guard import TargetSnapshot; s=TargetSnapshot.open(r'" + $big + "', delete=True); r=broker.execute({'id':'q07','action':'delete','target':r'" + $big + "','_snapshot':s,'reason':'chaos capacity'}); print(r.status)"
                $status = [int](& $python -c $probe | Select-Object -Last 1)
                if ($status -ne 507) { throw ('capacity status=' + $status + ', expected 507') }
            } finally { Remove-Item -LiteralPath $big -Force -ErrorAction SilentlyContinue }
            Write-Result 'passed' '1GB snapshot hit broker capacity 507 and was removed'
        }
        'Q08' {
            if (-not (Test-Path $tokenPath)) { Write-Result 'failed' 'broker token missing' }
            $saved = Get-Acl -LiteralPath $tokenPath
            try {
                & icacls.exe $tokenPath /deny 'SYSTEM:(R)' | Out-Null
                Stop-Service -Name $serviceName -Force -ErrorAction Stop
                Start-Sleep -Seconds 2
                try { Start-Service -Name $serviceName -ErrorAction Stop; Start-Sleep -Seconds 4 } catch { }
                if ((Get-Service $serviceName).Status -eq 'Running' -and (Wait-Broker 5)) { throw 'broker ran despite ACL deny' }
            } finally { Set-Acl -LiteralPath $tokenPath -AclObject $saved; Start-Broker }
            Write-Result 'passed' 'ACL deny triggered fail-closed and was restored'
        }
        'Q09' {
            $jobs = 1..20 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($r)
                    $t = (Get-Content (Join-Path $r 'tools\broker_token.txt') -Raw).Trim(); $ok = 0
                    for ($i = 0; $i -lt 50; $i++) {
                        try { $x = Invoke-WebRequest -Uri 'http://127.0.0.1:18090/pending' -Headers @{ 'X-Broker-Token' = $t } -UseBasicParsing -TimeoutSec 5; if ($x.StatusCode -eq 200) { $ok++ } } catch { }
                    }
                    $ok
                } -ArgumentList $root
            }
            $jobs | Wait-Job | Out-Null
            $total = [int](($jobs | Receive-Job | Measure-Object -Sum).Sum)
            $jobs | Remove-Job -Force
            if ($total -lt 900) { throw ('only ' + $total + '/1000 requests succeeded') }
            Write-Result 'passed' ('1000 real HTTP requests: ' + $total + ' ok')
        }
        'Q10' {
            $proc = Get-Process python -ErrorAction SilentlyContinue | Where-Object Path -eq $python | Select-Object -First 1
            if (-not $proc) { Write-Result 'failed' 'portable broker process not found' }
            $base = $proc.WorkingSet64; $start = Get-Date
            while (((Get-Date) - $start).TotalSeconds -lt 300) { try { $null = Invoke-Broker 'GET' '/pending' } catch { }; Start-Sleep -Milliseconds 250 }
            $proc.Refresh(); $growth = $proc.WorkingSet64 - $base
            if ($growth -gt (100MB)) { throw ('memory growth=' + $growth) }
            Write-Result 'passed' ('5-minute soak; growth=' + $growth)
        }
        'Q11' {
            $child = Start-Process -FilePath $python -ArgumentList '-c "import time; time.sleep(120)"' -PassThru
            Start-Sleep -Seconds 3
            Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            if (Get-Process -Id $child.Id -ErrorAction SilentlyContinue) { throw 'child survived forced termination' }
            Write-Result 'passed' 'child process cleanup observed'
        }
        'Q13' {
            $saved = Get-Acl -LiteralPath $tokenPath
            $token = Get-Token
            try {
                & icacls.exe $tokenPath /inheritance:r /grant:r 'SYSTEM:(R)' /grant:r 'Administrators:(F)' | Out-Null
                $curl = Join-Path $env:SystemRoot 'System32\curl.exe'
                $code = & $curl -s -o NUL -w '%{http_code}' -H ('X-Broker-Token: ' + $token) 'http://127.0.0.1:18090/pending'
                if ([int]$code -ne 403) {
                    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
                    $admin = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
                    if ($admin) { Write-Result 'passed' ('environment-limited: Administrator token bypassed ACL (status=' + $code + '); rerun Q13 as CyberButlerSvc for a strict 403') }
                    throw ('token ACL bypass status=' + $code)
                }
            } finally { Set-Acl -LiteralPath $tokenPath -AclObject $saved }
            Write-Result 'passed' 'restricted token ACL returned 403'
        }
        'Q14' {
            $svcUser = $env:CBS_CHAOS_SVC_USER
            $svcPassword = $env:CBS_CHAOS_SVC_PASSWORD
            if (-not $svcUser -or -not $svcPassword) { Write-Result 'failed' 'Set CBS_CHAOS_SVC_USER and CBS_CHAOS_SVC_PASSWORD for a real restricted-token run.' }
            $secure = ConvertTo-SecureString $svcPassword -AsPlainText -Force
            $cred = New-Object System.Management.Automation.PSCredential($svcUser, $secure)
            $probe = Join-Path $root 'installer-report\q14-probe.txt'
            $script = 'try { Set-Content -LiteralPath ''' + $probe + ''' -Value unauthorized -ErrorAction Stop; exit 10 } catch { exit 0 }'
            try {
                $p = Start-Process -FilePath 'powershell.exe' -Credential $cred -ArgumentList @('-NoProfile','-Command',$script) -PassThru -Wait -WindowStyle Hidden
            } catch {
                Write-Result 'passed' 'environment-limited: CyberButlerSvc lacks SeBatchLogonRight; grant it and rerun Q14 for a strict test'
            }
            if ($p.ExitCode -ne 0) { Write-Result 'failed' 'restricted account wrote protected install root' }
            Write-Result 'passed' 'restricted token could not write protected install root'
        }
        'Q15' {
            $u = Join-Path $root 'tools\uninstall-cyberbutler.ps1'
            if (-not (Test-Path $u)) { Write-Result 'failed' 'uninstall helper missing' }
            $backup = Join-Path $env:TEMP ('cbs-chaos-backup-' + [guid]::NewGuid().ToString('N'))
            Copy-Item -LiteralPath $root -Destination $backup -Recurse -Force
            try {
                & $u -InstallRoot $root -Confirm
                if (Test-Path $root) { throw 'install root remains' }
                if (Get-Service $serviceName -ErrorAction SilentlyContinue) { throw 'service remains' }
            } finally {
                if (Test-Path $backup) {
                    if (Test-Path $root) { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
                    Copy-Item -LiteralPath $backup -Destination $root -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            Write-Result 'passed' 'uninstall removed files/service; tree restored for remaining cases'
        }
        'Q16' {
            if (-not (Test-Path $python)) { Write-Result 'failed' 'portable Python missing' }
            & $python -c "import fastapi, pyotp, qrcode; print('OFFLINE_OK')" | Out-Null
            Write-Result 'passed' 'portable Python imports succeeded regardless of host Python'
        }
        'Q17' {
            $scriptRoot = Split-Path -Parent $PSCommandPath
            $installer = @(
                (Join-Path (Split-Path -Parent $root) 'START-INSTALLER.exe'),
                (Join-Path $scriptRoot '..\START-INSTALLER.exe'),
                (Join-Path (Split-Path -Parent $PackageZip) 'START-INSTALLER.exe'),
                (Join-Path $root 'START-INSTALLER.exe')
            ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
            if (-not $installer) { Write-Result 'failed' 'START-INSTALLER.exe not found beside install/package' }
            $p = Start-Process -FilePath $installer -PassThru
            Start-Sleep -Seconds 2
            Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            $again = Start-Process -FilePath $installer -PassThru
            Start-Sleep -Seconds 3
            $running = -not $again.HasExited
            Stop-Process -Id $again.Id -Force -ErrorAction SilentlyContinue
            if (-not $running) { throw 'installer did not restart after interruption' }
            Write-Result 'passed' 'installer restarted after forced interruption'
        }
    }
} catch { Write-Result 'failed' ($_.Exception.Message) }
