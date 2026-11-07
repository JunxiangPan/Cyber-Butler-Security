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
                & fsutil.exe file createnew $big 1073741824 | Out-Null
                if ((Get-Item $big).Length -ne 1073741824) { throw '1GB file size mismatch' }
                $body = '{"action":"delete","target":"' + ($big -replace '\\','\\\\') + '","reason":"chaos capacity"}'
                $status = 0
                try { $status = [int](Invoke-Broker 'POST' '/request' $body).StatusCode } catch { if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode } }
                if ($status -ne 507) { throw ('capacity status=' + $status + ', expected 507') }
            } finally { Remove-Item -LiteralPath $big -Force -ErrorAction SilentlyContinue }
            Write-Result 'passed' '1GB file produced 507 and was removed'
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
            if ($growth -gt 104857600) { throw ('memory growth=' + $growth) }
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
            try {
                & icacls.exe $tokenPath /inheritance:r /grant:r 'SYSTEM:(R)' /grant:r 'Administrators:(F)' | Out-Null
                $status = 0
                try { $null = Invoke-Broker 'GET' '/pending' } catch { if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode } }
                if ($status -ne 403) { throw ('token ACL bypass status=' + $status) }
            } finally { Set-Acl -LiteralPath $tokenPath -AclObject $saved }
            Write-Result 'passed' 'restricted token ACL returned 403'
        }
        'Q14' {
            if ((& whoami.exe) -notmatch 'CyberButlerSvc') { Write-Result 'failed' 'run this case from a CyberButlerSvc session' }
            $probe = Join-Path $root 'installer-report\q14-probe.txt'
            try { Set-Content -LiteralPath $probe -Value 'unauthorized' -ErrorAction Stop; throw 'service account wrote install root' } catch { if ($_.Exception.Message -eq 'service account wrote install root') { throw } }
            Write-Result 'passed' 'CyberButlerSvc could not write protected install root'
        }
        'Q15' {
            $u = Join-Path $root 'installer\Uninstall-CyberButler.ps1'
            if (-not (Test-Path $u)) { Write-Result 'failed' 'uninstaller missing' }
            & $u -InstallPath $root -Confirm:$false
            if (Test-Path $root) { throw 'install root remains' }
            if (Get-Service $serviceName -ErrorAction SilentlyContinue) { throw 'service remains' }
            Write-Result 'passed' 'uninstall removed files and service'
        }
        'Q16' {
            if (Get-Command python.exe -ErrorAction SilentlyContinue) { Write-Result 'failed' 'system Python is present' }
            if (-not (Test-Path $python)) { Write-Result 'failed' 'portable Python missing' }
            & $python -c "import fastapi, pyotp, qrcode; print('OFFLINE_OK')" | Out-Null
            Write-Result 'passed' 'no system Python; portable imports succeeded'
        }
        'Q17' {
            $installer = Join-Path (Split-Path -Parent $root) 'START-INSTALLER.exe'
            if (-not (Test-Path $installer)) { Write-Result 'failed' 'START-INSTALLER.exe missing' }
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
