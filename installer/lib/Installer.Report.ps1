# Install report writer for the Cyber-Butler installer.
# Dot-source Installer.Common.ps1 first.

function New-CyberButlerReportModel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tier,
        [Parameter(Mandatory = $true)]
        [string]$EffectiveTier,
        [bool]$Isolation = $false,
        [string]$Status = 'unknown',
        $Diagnostics = $null,
        $Steps = @(),
        $Approvals = @(),
        $Journal = $null,
        $Failure = $null,
        [string]$Message = ''
    )

    $manual = New-Object System.Collections.Generic.List[object]
    $stepRows = New-Object System.Collections.Generic.List[object]
    $approvalRows = New-Object System.Collections.Generic.List[object]
    if ($Diagnostics) {
        foreach ($item in @($Diagnostics.items)) {
            if ([string]$item.status -in @('MANUAL', 'PARTIAL', 'FAILED')) {
                $manual.Add([pscustomobject]@{ id = $item.id; label = $item.label; status = $item.status; reason = $item.reason })
            }
        }
    }

    if ($null -ne $Steps) { foreach ($step in $Steps) { if ($null -ne $step) { $stepRows.Add($step) } } }
    if ($null -ne $Approvals) { foreach ($approval in $Approvals) { if ($null -ne $approval) { $approvalRows.Add($approval) } } }

    return [pscustomobject][ordered]@{
        schema = 1
        generated_at = Get-InstallerUtcTimestamp
        status = $Status
        tier = $Tier
        effective_tier = $EffectiveTier
        isolation = [bool]$Isolation
        message = $Message
        diagnostics = $Diagnostics
        steps = $stepRows.ToArray()
        approvals = $approvalRows.ToArray()
        journal_path = if ($Journal) { [string]$Journal.StatePath } else { $null }
        failure = $Failure
        manual = $manual.ToArray()
    }
}

function Format-CyberButlerReportMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        $Report
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('# Cyber-Butler Install Report')
    $lines.Add('')
    $lines.Add(('- Generated: {0}' -f $Report.generated_at))
    $lines.Add(('- Status: {0}' -f $Report.status))
    $lines.Add(('- Tier: {0}' -f $Report.tier))
    $lines.Add(('- Effective: {0}' -f $Report.effective_tier))
    $lines.Add(('- Isolation: {0}' -f $Report.isolation))
    if ($Report.journal_path) { $lines.Add(('- Journal: {0}' -f $Report.journal_path)) }
    if ($Report.message) { $lines.Add(('- Message: {0}' -f $Report.message)) }
    $lines.Add('')

    if ($Report.diagnostics) {
        $lines.Add('## Defense checklist')
        $lines.Add('')
        $lines.Add('| Item | Status | Reason |')
        $lines.Add('|---|---|---|')
        foreach ($item in @($Report.diagnostics.items)) {
            $lines.Add(('| {0} | {1} | {2} |' -f $item.label, $item.status, $item.reason))
        }
        $lines.Add('')
    }

    $lines.Add('## Steps')
    $lines.Add('')
    $lines.Add('| Step | Status | Reason |')
    $lines.Add('|---|---|---|')
    foreach ($step in @($Report.steps)) {
        $lines.Add(('| {0} | {1} | {2} |' -f $step.name, $step.status, $step.reason))
    }
    $lines.Add('')

    $lines.Add('## Approvals')
    $lines.Add('')
    if (@($Report.approvals).Count -eq 0) {
        $lines.Add('No approvals recorded.')
    } else {
        foreach ($approval in @($Report.approvals)) {
            $lines.Add(('- {0} at {1}' -f $approval.token, $approval.at))
        }
    }
    $lines.Add('')

    $lines.Add('## Manual / failures')
    $lines.Add('')
    if (@($Report.manual).Count -eq 0 -and -not $Report.failure) {
        $lines.Add('None.')
    } else {
        foreach ($item in @($Report.manual)) {
            $lines.Add(('- {0}: {1} ({2})' -f $item.label, $item.status, $item.reason))
        }
        if ($Report.failure) {
            $lines.Add(('- FAILED: {0}' -f $Report.failure.message))
        }
    }
    return ($lines -join [Environment]::NewLine)
}

function Write-CyberButlerReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,
        [Parameter(Mandatory = $true)]
        $Report,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'report.write') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'report.write' -Context ([pscustomobject]@{
            OutputDirectory = $OutputDirectory; Report = $Report
        }))
    }

    $dir = [IO.Path]::GetFullPath($OutputDirectory)
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $jsonPath = Join-Path $dir 'install-report.json'
    $mdPath = Join-Path $dir 'install-report.md'
    Write-InstallerJson -Path $jsonPath -Value $Report
    $markdown = Format-CyberButlerReportMarkdown -Report $Report
    [IO.File]::WriteAllText($mdPath, $markdown + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    return [pscustomobject]@{ json = $jsonPath; markdown = $mdPath; directory = $dir }
}
