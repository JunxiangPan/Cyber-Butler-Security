#Requires -Version 5.1
<#
Cyber-Butler dashboard core helpers.
Only status probing, version/root resolution and audit-tail reading remain.
#>

function Get-DashboardRoot {
    param([string]$ProjectRoot = '')
    if ($ProjectRoot) { return (Resolve-Path -LiteralPath $ProjectRoot).Path }
    return (Split-Path -Parent $PSScriptRoot)
}

<#
.SYNOPSIS
    Probe a loopback TCP port without throwing.
#>
function Test-Port {
    param([int]$Port, [int]$TimeoutMs = 800)
    $client = New-Object Net.Sockets.TcpClient
    try {
        $task = $client.ConnectAsync('127.0.0.1', $Port)
        if (-not $task.Wait($TimeoutMs)) { return $false }
        return $client.Connected
    } catch {
        return $false
    } finally {
        $client.Dispose()
    }
}

<#
.SYNOPSIS
    Read the latest broker audit rows for the dashboard.
#>
function Get-AuditTail {
    param([string]$ProjectRoot, [int]$Count = 10)
    $path = Join-Path $ProjectRoot 'tools\totp_broker_audit.jsonl'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    $rows = @()
    try {
        foreach ($line in @(Get-Content -LiteralPath $path -Tail $Count -Encoding UTF8 -ErrorAction Stop)) {
            if (-not $line.Trim()) { continue }
            try {
                $item = $line | ConvertFrom-Json
                $ok = $true
                if ($item.PSObject.Properties.Name -contains 'ok') { $ok = [bool]$item.ok }
                $rows += [pscustomobject]@{
                    At = [string]$item.at
                    Action = [string]$item.action
                    Target = [string]$item.target
                    Result = [string]$item.result
                    Ok = $ok
                    Status = if ($ok) { '已批准' } else { '已拦截' }
                }
            } catch { Write-Verbose 'optional operation failed' }
        }
    } catch { Write-Verbose 'optional operation failed' }
    return @($rows | Select-Object -Last $Count)
}
