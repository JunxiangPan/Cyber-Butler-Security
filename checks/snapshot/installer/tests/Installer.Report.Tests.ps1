$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Report.ps1')

function New-ReportDiagnostics {
    $items = @(
        [pscustomobject]@{ id = 'isolation'; label = '双账户隔离'; status = 'ENABLED'; reason = 'test' },
        [pscustomobject]@{ id = 'totp'; label = 'TOTP 审批'; status = 'ENABLED'; reason = 'test' },
        [pscustomobject]@{ id = 'router'; label = 'Router fail-closed'; status = 'ENABLED'; reason = 'test' },
        [pscustomobject]@{ id = 'webui'; label = 'Web UI 绑定'; status = 'ENABLED'; reason = 'test' },
        [pscustomobject]@{ id = 'api_key'; label = 'API Key 保护'; status = 'ENABLED'; reason = 'test' },
        [pscustomobject]@{ id = 'totp_vault'; label = 'TOTP 保险箱隔离'; status = 'PARTIAL'; reason = 'test' },
        [pscustomobject]@{ id = 'audit'; label = '审计'; status = 'ENABLED'; reason = 'test' },
        [pscustomobject]@{ id = 'firewall'; label = '防火墙'; status = 'ENABLED'; reason = 'test' }
    )
    return [pscustomobject]@{
        tier = 'Medium'
        effective_tier = 'Medium'
        isolation = $false
        read_only = $true
        items = $items
        summary = [pscustomobject]@{ enabled = 6; partial = 1; manual = 1; failed = 0 }
    }
}

Describe 'Installer reports' {
    It 'writes install-report.json and install-report.md with the defense checklist' {
        $base = Join-Path $env:TEMP ('cb-report-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $diagnostics = New-ReportDiagnostics
            $steps = @(
                [pscustomobject]@{ name = 'preflight'; status = 'completed'; reason = '' },
                [pscustomobject]@{ name = 'core'; status = 'completed'; reason = 'dry-run' }
            )
            $approvals = @([pscustomobject]@{ token = 'APPROVE PLAN'; step = 'plan'; at = 'now' })
            $model = New-CyberButlerReportModel -Tier Medium -EffectiveTier Medium -Isolation $false -Status success `
                -Diagnostics $diagnostics -Steps $steps -Approvals $approvals -Journal $null -Failure $null -Message 'ok'
            $paths = Write-CyberButlerReport -OutputDirectory $base -Report $model
            (Test-Path -LiteralPath $paths.json) | Should Be $true
            (Test-Path -LiteralPath $paths.markdown) | Should Be $true
            $json = Get-Content -LiteralPath $paths.json -Raw -Encoding UTF8 | ConvertFrom-Json
            $json.status | Should Be 'success'
            $json.effective_tier | Should Be 'Medium'
            @($json.diagnostics.items).Count | Should Be 8
            @($json.steps).Count | Should Be 2
            @($json.approvals).Count | Should Be 1
            $md = Get-Content -LiteralPath $paths.markdown -Raw -Encoding UTF8
            ($md -match 'Defense checklist') | Should Be $true
            ($md -match 'APPROVE PLAN') | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'does not write fake secret values into the report' {
        $base = Join-Path $env:TEMP ('cb-report-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $diagnostics = New-ReportDiagnostics
            $model = New-CyberButlerReportModel -Tier Medium -EffectiveTier Medium -Isolation $false -Status success `
                -Diagnostics $diagnostics -Steps @() -Approvals @() -Journal $null -Failure $null -Message 'ok'
            $paths = Write-CyberButlerReport -OutputDirectory $base -Report $model
            $text = (Get-Content -LiteralPath $paths.json -Raw) + (Get-Content -LiteralPath $paths.markdown -Raw)
            ($text -match 'fake-api-key-value|fake-smtp-password|totp_secret_value') | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
