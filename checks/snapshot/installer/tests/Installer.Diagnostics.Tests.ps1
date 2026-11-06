$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Tier.ps1')
. (Join-Path $installerRoot 'lib\Installer.Diagnostics.ps1')

function New-DiagnosticHandlers {
    return @{
        'diagnostics.run' = {
            param($c)
            $items = @(
                [pscustomobject]@{ id = 'isolation'; label = '双账户隔离'; status = $(if ($c.Isolation) { 'ENABLED' } else { 'MANUAL' }); reason = 'test' },
                [pscustomobject]@{ id = 'totp'; label = 'TOTP 审批'; status = 'ENABLED'; reason = 'test' },
                [pscustomobject]@{ id = 'router'; label = 'Router fail-closed'; status = 'ENABLED'; reason = 'test' },
                [pscustomobject]@{ id = 'webui'; label = 'Web UI 绑定'; status = 'ENABLED'; reason = 'test' },
                [pscustomobject]@{ id = 'api_key'; label = 'API Key 保护'; status = 'ENABLED'; reason = 'test' },
                [pscustomobject]@{ id = 'totp_vault'; label = 'TOTP 保险箱隔离'; status = $(if ($c.Isolation) { 'ENABLED' } else { 'PARTIAL' }); reason = 'test' },
                [pscustomobject]@{ id = 'audit'; label = '审计'; status = 'ENABLED'; reason = 'test' },
                [pscustomobject]@{ id = 'firewall'; label = '防火墙'; status = 'ENABLED'; reason = 'test' }
            )
            [pscustomobject]@{ items = $items }
        }
    }
}

Describe 'Installer diagnostics' {
    It 'covers High, Medium, Light, Medium+Isolation and Light+Isolation' {
        $cases = @(
            @{ Tier = 'High'; Effective = 'High'; Isolation = $true },
            @{ Tier = 'Medium'; Effective = 'Medium'; Isolation = $false },
            @{ Tier = 'Light'; Effective = 'Light'; Isolation = $false },
            @{ Tier = 'Medium'; Effective = 'Medium + Isolation'; Isolation = $true },
            @{ Tier = 'Light'; Effective = 'Light + Isolation'; Isolation = $true }
        )
        foreach ($case in $cases) {
            $result = Get-CyberButlerDiagnostics -Tier $case.Tier -EffectiveTier $case.Effective -Isolation $case.Isolation -Root $env:TEMP -Handlers (New-DiagnosticHandlers)
            $result.effective_tier | Should Be $case.Effective
            $result.isolation | Should Be $case.Isolation
            $result.read_only | Should Be $true
            @($result.items).Count | Should Be 8
        }
    }

    It 'marks all eight defense items with a valid status and reason' {
        $result = Get-CyberButlerDiagnostics -Tier Medium -EffectiveTier Medium -Isolation $false -Root $env:TEMP -Handlers (New-DiagnosticHandlers)
        $valid = @('ENABLED', 'PARTIAL', 'MANUAL', 'FAILED')
        foreach ($item in @($result.items)) {
            ($valid -contains [string]$item.status) | Should Be $true
            ([string]::IsNullOrWhiteSpace([string]$item.reason)) | Should Be $false
        }
        $result.summary.enabled + $result.summary.partial + $result.summary.manual + $result.summary.failed | Should Be 8
    }

    It 'fills missing diagnostics as MANUAL rather than omitting them' {
        $handlers = @{ 'diagnostics.run' = { param($c) [pscustomobject]@{ items = @([pscustomobject]@{ id = 'isolation'; label = '双账户隔离'; status = 'ENABLED'; reason = 'test' }) } } }
        $result = Get-CyberButlerDiagnostics -Tier Medium -EffectiveTier Medium -Isolation $false -Root $env:TEMP -Handlers $handlers
        @($result.items).Count | Should Be 8
        @($result.items | Where-Object { $_.status -eq 'MANUAL' }).Count | Should BeGreaterThan 0
    }
}
