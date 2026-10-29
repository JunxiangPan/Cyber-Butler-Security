#Requires -Version 5.1
<#
Read-only core helpers for the Cyber-Butler dashboard.

These functions are intentionally read-only. They never stop services, write
configuration, call AstrBot tools, or register anything in the LLM tool list.
#>

function Get-DashboardRoot {
    param([string]$ProjectRoot = '')
    if ($ProjectRoot) { return (Resolve-Path -LiteralPath $ProjectRoot).Path }
    return (Split-Path -Parent $PSScriptRoot)
}

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

function Get-GpuInfo {
    try {
        $line = (& nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>$null | Select-Object -First 1)
        if (-not $line) { return $null }
        $parts = @($line -split ',' | ForEach-Object { $_.Trim() })
        if ($parts.Count -lt 2) { return $null }
        $util = $null
        if ($parts.Count -ge 3 -and $parts[2]) { $util = [int]$parts[2] }
        return [pscustomobject]@{
            UsedMB = [int]$parts[0]
            TotalMB = [int]$parts[1]
            UtilPct = $util
        }
    } catch { return $null }
}

function Get-ProviderInfo {
    param([string]$ProjectRoot)
    $config = Join-Path $ProjectRoot 'AstrBot\data\cmd_config.json'
    if (-not (Test-Path -LiteralPath $config)) {
        return [pscustomobject]@{ Name = '未知'; Model = ''; Mode = '未知'; Source = 'missing config' }
    }
    try {
        $data = Get-Content -LiteralPath $config -Raw -Encoding UTF8 | ConvertFrom-Json
        $providers = @($data.provider)
        $local = $providers | Where-Object { $_.id -eq 'local_qwen36' -and $_.enable -ne $false } | Select-Object -First 1
        if ($local) {
            return [pscustomobject]@{
                Name = 'local_qwen36'
                Model = [string]$local.model
                Mode = '本地'
                Source = 'cmd_config.json'
            }
        }
        $cloud = $providers | Where-Object { $_.id -eq 'deepseek' -and $_.enable -ne $false } | Select-Object -First 1
        if ($cloud) {
            return [pscustomobject]@{
                Name = 'deepseek'
                Model = [string]$cloud.model
                Mode = '云端'
                Source = 'cmd_config.json'
            }
        }
    } catch { }
    return [pscustomobject]@{ Name = '未知'; Model = ''; Mode = '未知'; Source = 'config read failed' }
}

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
            } catch { }
        }
    } catch { }
    return @($rows | Select-Object -Last $Count)
}

function Get-GameWhitelist {
    param([string]$ProjectRoot)
    $result = @()
    $seen = @{}
    foreach ($spec in @(
        @{ File = 'tools\game-list.auto.txt'; Source = 'AUTO' },
        @{ File = 'tools\game-list.txt'; Source = 'MANUAL' }
    )) {
        $path = Join-Path $ProjectRoot $spec.File
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in @(Get-Content -LiteralPath $path -Encoding UTF8 -ErrorAction SilentlyContinue)) {
            $name = $line.Trim()
            if (-not $name -or $name.StartsWith('#')) { continue }
            $key = $name.ToLowerInvariant()
            if ($seen.ContainsKey($key)) { continue }
            $seen[$key] = $true
            $result += [pscustomobject]@{
                Name = $name
                Source = $spec.Source
                File = $spec.File
            }
        }
    }
    return @($result | Sort-Object Name)
}

function Get-GameIgnoreList {
    param([string]$ProjectRoot)
    $path = Join-Path $ProjectRoot 'tools\game-mode.ps1'
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    try {
        $text = Get-Content -LiteralPath $path -Raw -Encoding UTF8
        $names = New-Object System.Collections.Generic.List[string]
        foreach ($var in @('IgnoredProcesses', 'GpuIgnoredProcesses')) {
            $pattern = '(?s)\$' + $var + '\s*=\s*@\((.*?)\r?\n\)'
            $match = [regex]::Match($text, $pattern)
            if (-not $match.Success) { continue }
            foreach ($m in [regex]::Matches($match.Groups[1].Value, "'([^']+)'")) {
                $value = $m.Groups[1].Value.Trim()
                if ($value -and -not $names.Contains($value)) { $names.Add($value) }
            }
        }
        return @($names | Sort-Object)
    } catch { return @() }
}

function Get-PersonaPrompt {
    param([string]$ProjectRoot)
    $path = Join-Path $ProjectRoot '.persona_sujinyan.json'
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        return [string]$data.system_prompt
    } catch { return '' }
}
