# Windows Firewall rule lifecycle for the Cyber-Butler installer.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

<#
.SYNOPSIS
    Get-CyberButlerFirewallState performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Get-CyberButlerFirewallState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleName
    )

    $rule = Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
    if (-not $rule) { return $null }
    $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
    $addressFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
    return [pscustomobject][ordered]@{
        rule_name = $RuleName
        enabled = [string]$rule.Enabled
        direction = [string]$rule.Direction
        action = [string]$rule.Action
        profile = [string]$rule.Profile
        protocol = if ($portFilter) { [string]($portFilter.Protocol -join ',') } else { $null }
        port = if ($portFilter) { [string]($portFilter.LocalPort -join ',') } else { $null }
        remote_address = if ($addressFilter) { [string]($addressFilter.RemoteAddress -join ',') } else { $null }
    }
}

<#
.SYNOPSIS
    Test-CyberButlerFirewallRule performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Test-CyberButlerFirewallRule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleName,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Inbound', 'Outbound')]
        [string]$Direction,
        [Parameter(Mandatory = $true)]
        [ValidateSet('Domain', 'Private', 'Public', 'Any')]
        [string]$FirewallProfile,
        [Parameter(Mandatory = $true)]
        [string]$RemoteAddress,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [ValidateSet('TCP', 'UDP')]
        [string]$Protocol = 'TCP',
        [ValidateSet('Allow', 'Block')]
        [string]$Action = 'Allow',
        $Handlers = @{}
    )

    $context = [pscustomobject]@{
        RuleName = $RuleName; Direction = $Direction; Profile = $FirewallProfile
        RemoteAddress = $RemoteAddress; Port = $Port; Protocol = $Protocol; Action = $Action
    }
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'firewall.test') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'firewall.test' -Context $context)
    }

    $result = [ordered]@{
        rule_name = $RuleName
        supported = $null -ne (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue)
        can_manage = [bool](Test-InstallerAdministrator)
        exists = $false
        satisfied = $false
        state = $null
        reason = ''
    }
    if (-not $result.supported) {
        $result.reason = 'net-firewall-module-unavailable'
        return [pscustomobject]$result
    }

    $state = Get-CyberButlerFirewallState -RuleName $RuleName
    if ($null -eq $state) {
        $result.reason = 'rule-missing'
        return [pscustomobject]$result
    }
    $result.exists = $true
    $result.state = $state
    $ports = @(([string]$state.port) -split ',')
    $addresses = @(([string]$state.remote_address) -split ',')
    $result.satisfied = (
        ([string]$state.enabled -eq 'True') -and
        ([string]$state.direction -eq $Direction) -and
        ([string]$state.action -eq $Action) -and
        ([string]$state.profile -eq $FirewallProfile -or [string]$state.profile -eq 'Any') -and
        ($addresses -contains $RemoteAddress -or $addresses -contains 'Any') -and
        ($ports -contains [string]$Port)
    )
    if (-not $result.satisfied) { $result.reason = 'rule-not-matching' }
    return [pscustomobject]$result
}

<#
.SYNOPSIS
    Assert-CyberButlerFirewallRule performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Assert-CyberButlerFirewallRule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleName,
        [Parameter(Mandatory = $true)]
        [string]$Direction,
        [Parameter(Mandatory = $true)]
        [string]$FirewallProfile,
        [Parameter(Mandatory = $true)]
        [string]$RemoteAddress,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [string]$Protocol = 'TCP',
        [string]$Action = 'Allow',
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'firewall.assert') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'firewall.assert' -Context ([pscustomobject]@{
            RuleName = $RuleName; Direction = $Direction; Profile = $FirewallProfile
            RemoteAddress = $RemoteAddress; Port = $Port; Protocol = $Protocol; Action = $Action
        }))
    }
    $test = Test-CyberButlerFirewallRule -RuleName $RuleName -Direction $Direction -FirewallProfile $FirewallProfile `
        -RemoteAddress $RemoteAddress -Port $Port -Protocol $Protocol -Action $Action -Handlers $Handlers
    return [bool]$test.satisfied
}

<#
.SYNOPSIS
    Set-CyberButlerFirewallRule performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Set-CyberButlerFirewallRule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleName,
        [Parameter(Mandatory = $true)]
        [string]$DisplayName,
        [Parameter(Mandatory = $true)]
        [string]$Direction,
        [Parameter(Mandatory = $true)]
        [string]$FirewallProfile,
        [Parameter(Mandatory = $true)]
        [string]$RemoteAddress,
        [Parameter(Mandatory = $true)]
        [int]$Port,
        [string]$Protocol = 'TCP',
        [string]$Action = 'Allow',
        $Handlers = @{}
    )

    $context = [pscustomobject]@{
        RuleName = $RuleName; DisplayName = $DisplayName; Direction = $Direction
        Profile = $FirewallProfile; RemoteAddress = $RemoteAddress; Port = $Port
        Protocol = $Protocol; Action = $Action
    }
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'firewall.apply') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'firewall.apply' -Context $context)
    }

    $existing = Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue
    if ($existing) {
        Set-NetFirewallRule -Name $RuleName -Enabled True -Direction $Direction -Action $Action -Profile $FirewallProfile -ErrorAction Stop
        Set-NetFirewallAddressFilter -Name $RuleName -RemoteAddress $RemoteAddress -ErrorAction Stop
        Set-NetFirewallPortFilter -Name $RuleName -Protocol $Protocol -LocalPort ([string]$Port) -ErrorAction Stop
        return [pscustomobject]@{ created = $false; rule_name = $RuleName }
    }

    New-NetFirewallRule -Name $RuleName -DisplayName $DisplayName -Direction $Direction `
        -Action $Action -Protocol $Protocol -LocalPort ([string]$Port) `
        -RemoteAddress $RemoteAddress -Profile $FirewallProfile -Enabled True -ErrorAction Stop | Out-Null
    return [pscustomobject]@{ created = $true; rule_name = $RuleName }
}

<#
.SYNOPSIS
    Undo-CyberButlerFirewallRule performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Undo-CyberButlerFirewallRule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleName,
        [bool]$Created = $false,
        $PreviousState = $null,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'firewall.undo') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'firewall.undo' -Context ([pscustomobject]@{
            RuleName = $RuleName; Created = $Created; PreviousState = $PreviousState
        }))
    }

    try {
        if ($Created) {
            if (Get-NetFirewallRule -Name $RuleName -ErrorAction SilentlyContinue) {
                Remove-NetFirewallRule -Name $RuleName -ErrorAction Stop
            }
            return [pscustomobject]@{ action = 'removed'; rule_name = $RuleName }
        }
        if ($null -eq $PreviousState) {
            return [pscustomobject]@{ action = 'failed'; rule_name = $RuleName; reason = 'previous-state-missing' }
        }
        $state = $PreviousState
        Set-NetFirewallRule -Name $RuleName -Enabled ([bool]$state.enabled) -Direction ([string]$state.direction) `
            -Action ([string]$state.action) -Profile ([string]$state.profile) -ErrorAction Stop
        Set-NetFirewallAddressFilter -Name $RuleName -RemoteAddress ([string]$state.remote_address) -ErrorAction Stop
        Set-NetFirewallPortFilter -Name $RuleName -Protocol ([string]$state.protocol) -LocalPort ([string]$state.port) -ErrorAction Stop
        return [pscustomobject]@{ action = 'restored'; rule_name = $RuleName }
    } catch {
        return [pscustomobject]@{ action = 'failed'; rule_name = $RuleName; reason = $_.Exception.Message }
    }
}

<#
.SYNOPSIS
    Invoke-CyberButlerFirewallRule performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Invoke-CyberButlerFirewallRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RuleName,
        [string]$DisplayName = '',
        [ValidateSet('Inbound', 'Outbound')]
        [string]$Direction = 'Inbound',
        [ValidateSet('Domain', 'Private', 'Public', 'Any')]
        [string]$FirewallProfile = 'Private',
        [string]$RemoteAddress = '127.0.0.1',
        [int]$Port = 8765,
        [ValidateSet('TCP', 'UDP')]
        [string]$Protocol = 'TCP',
        [ValidateSet('Allow', 'Block')]
        [string]$Action = 'Allow',
        [string]$JournalStep = 'firewall',
        $Journal = $null,
        [string]$Approval = '',
        [switch]$NonInteractive,
        [switch]$PlanOnly,
        $Handlers = @{}
    )

    if ([string]::IsNullOrWhiteSpace($DisplayName)) { $DisplayName = $RuleName }
    try {
    $test = Test-CyberButlerFirewallRule -RuleName $RuleName -Direction $Direction -FirewallProfile $FirewallProfile `
        -RemoteAddress $RemoteAddress -Port $Port -Protocol $Protocol -Action $Action -Handlers $Handlers
    $base = [ordered]@{
        module = 'firewall'
        step = $JournalStep
        rule_name = $RuleName
        test = $test
        changed = $false
    }

    if ($test.satisfied) {
        $base.status = 'skipped'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if (-not $test.supported) {
        $base.status = 'unsupported'
        $base.message = 'NetFirewall cmdlets are unavailable; apply the firewall rule manually.'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if (-not $test.can_manage) {
        $base.status = 'needs_elevation'
        $base.message = 'Firewall changes require administrator rights.'
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        return [pscustomobject]$base
    }

    $approvalState = Get-CyberButlerApprovalState -Required 'APPROVE FIREWALL' -Approval $Approval -NonInteractive:$NonInteractive -PlanOnly:$PlanOnly
    if ($approvalState -eq 'plan') {
        $base.status = 'plan'
        $base.message = 'Would create or update the requested firewall rule.'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if ($approvalState -ne 'approved') {
        $base.status = 'needs_approval'
        $base.exit_code = Get-InstallerExitCode -Name NeedsApproval
        return [pscustomobject]$base
    }

    if ($null -ne $Journal) {
        Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status in_progress | Out-Null
    }

    $previous = $test.state
    $created = $false
    try {
        $applied = Set-CyberButlerFirewallRule -RuleName $RuleName -DisplayName $DisplayName -Direction $Direction `
            -FirewallProfile $FirewallProfile -RemoteAddress $RemoteAddress -Port $Port -Protocol $Protocol -Action $Action -Handlers $Handlers
        $created = [bool]$applied.created
        $base.changed = $true
        if ($null -ne $Journal) {
            if ($created) {
                Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                    type = 'delete-created-firewall-rule'
                    rule_name = $RuleName
                })
            } elseif ($null -ne $previous) {
                Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                    type = 'restore-firewall-rule'
                    rule_name = $RuleName
                    state = $previous
                })
            }
        }

        $asserted = Assert-CyberButlerFirewallRule -RuleName $RuleName -Direction $Direction -FirewallProfile $FirewallProfile `
            -RemoteAddress $RemoteAddress -Port $Port -Protocol $Protocol -Action $Action -Handlers $Handlers
        if (-not $asserted) { throw 'Firewall rule assertion failed.' }

        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status completed | Out-Null
        }
        $base.status = 'completed'
        $base.created = $created
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    } catch {
        $undo = Undo-CyberButlerFirewallRule -RuleName $RuleName -Created $created -PreviousState $previous -Handlers $Handlers
        $base.status = 'failed'
        $base.message = $_.Exception.Message
        $base.undo = $undo
        $base.exit_code = if ($undo.action -eq 'failed') { Get-InstallerExitCode -Name RollbackFailed } else { Get-InstallerExitCode -Name ValidationFailed }
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ error = $_.Exception.Message; undo = $undo.action }) | Out-Null
        }
        return [pscustomobject]$base
    }
    } catch {
        $message = $_.Exception.Message
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ error = $message; stage = 'pre-apply' }) | Out-Null
        }
        return [pscustomobject]@{
            module = 'firewall'; step = $JournalStep; status = 'failed'; message = $message
            changed = $false; test = $null; exit_code = Get-InstallerExitCode -Name ValidationFailed
        }
    }
}
