# Feature manifest resolver for Cyber-Butler v1.7.0.
# Dot-source Installer.Common.ps1 first for Get-InstallerExitCode (not required by tests).

function Get-CyberButlerFeatureManifest {
    param([string]$ManifestPath)
    if (-not $ManifestPath) { $ManifestPath = Join-Path $PSScriptRoot '..\features.v1.json' }
    if (-not (Test-Path -LiteralPath $ManifestPath)) { throw ('Feature manifest missing: ' + $ManifestPath) }
    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    if (-not $manifest.features -or -not $manifest.presets) { throw 'Feature manifest is missing features or presets.' }
    return [pscustomobject]@{ Path = (Resolve-Path $ManifestPath).Path; Data = $manifest }
}

function Get-CyberButlerFeatureById {
    param($Manifest, [string]$Id)
    return @($Manifest.features | Where-Object { $_.id -eq $Id })[0]
}

function Resolve-CyberButlerFeatures {
    [CmdletBinding()]
    param(
        [ValidateSet('High', 'Medium', 'Light')]
        [string]$Tier = 'Medium',

        [string[]]$FeatureIds = @(),

        [ValidateSet('QQ', 'Email', '')]
        [string]$ApprovalChannel = '',

        [switch]$AcceptBelowMinimum,

        [hashtable]$Fields = @{},

        [string]$ManifestPath = ''
    )

    $loaded = Get-CyberButlerFeatureManifest -ManifestPath $ManifestPath
    $manifest = $loaded.Data
    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $allIds = @($manifest.features | ForEach-Object { $_.id })
    $isCustom = @($FeatureIds).Count -gt 0

    if ($isCustom) {
        $selected = New-Object System.Collections.Generic.List[string]
        foreach ($id in $FeatureIds) { if ($id) { $selected.Add([string]$id) } }
    } else {
        $preset = @($manifest.presets.$Tier)
        if ($preset.Count -eq 0) { $errors.Add('Unknown tier preset: ' + $Tier) }
        $selected = New-Object System.Collections.Generic.List[string]
        foreach ($id in $preset) { $selected.Add([string]$id) }
    }

    foreach ($id in @($selected)) {
        if ($allIds -notcontains $id) { $errors.Add(('Unknown feature: ' + $id)); $selected.Remove($id) | Out-Null }
    }

    # Resolve approval channel. An explicit channel wins; otherwise infer from selected features/fields.
    if ($ApprovalChannel) {
        $channelFeature = if ($ApprovalChannel -eq 'QQ') { 'approval.qq' } else { 'approval.email' }
        $bothExplicit = (@($FeatureIds) -contains 'approval.qq') -and (@($FeatureIds) -contains 'approval.email')
        foreach ($other in @('approval.qq', 'approval.email')) {
            if ($other -ne $channelFeature -and $selected -contains $other) {
                if ($bothExplicit) { $errors.Add(('Approval channels are mutually exclusive: ' + $other + ' and ' + $channelFeature)) }
                else { $selected.Remove($other) | Out-Null }
            }
        }
        if ($selected -notcontains $channelFeature) { $selected.Add($channelFeature) }
        if ($channelFeature -eq 'approval.email' -and $selected -notcontains 'otp_mailer') { $selected.Add('otp_mailer') }
    } else {
        $hasQq = $selected -contains 'approval.qq'
        $hasEmail = $selected -contains 'approval.email'
        if ($hasQq -and $hasEmail) {
            $errors.Add('Approval channels are mutually exclusive: approval.qq and approval.email')
        } elseif (-not $hasQq -and -not $hasEmail) {
            $ApprovalChannel = ''
        } else {
            $ApprovalChannel = if ($hasQq) { 'QQ' } else { 'Email' }
        }
    }

    # Transitively add declared dependencies and check exclusions.
    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($id in @($selected)) {
            $feature = Get-CyberButlerFeatureById -Manifest $manifest -Id $id
            if (-not $feature) { continue }
            foreach ($dep in @($feature.requires)) {
                if ($dep -and $selected -notcontains $dep) { $selected.Add([string]$dep); $changed = $true }
            }
            foreach ($excluded in @($feature.excludes)) {
                if ($excluded -and $selected -contains $excluded) {
                    $errors.Add(('Features {0} and {1} exclude each other.' -f $id, $excluded))
                }
            }
        }
    }

    $requiredIds = @($manifest.features | Where-Object { $_.required } | ForEach-Object { $_.id })
    $channelIds = @('approval.qq', 'approval.email')
    $selectedChannels = @($selected | Where-Object { $channelIds -contains $_ })
    if ($selectedChannels.Count -eq 0) { $errors.Add('Exactly one approval channel is required (approval.qq or approval.email).') }
    if ($selectedChannels.Count -gt 1) { $errors.Add('Exactly one approval channel is allowed; got: ' + ($selectedChannels -join ',')) }

    $floorMissing = New-Object System.Collections.Generic.List[string]
    foreach ($id in $requiredIds) { if ($selected -notcontains $id) { $floorMissing.Add($id) } }
    if ($selectedChannels.Count -ne 1) { $floorMissing.Add('approval.channel') }

    if ($floorMissing.Count -gt 0 -and -not $AcceptBelowMinimum) {
        $errors.Add('Below Light minimum; missing: ' + ($floorMissing -join ',') + '. Pass -AcceptBelowMinimum to waive.')
    }
    if ($floorMissing.Count -gt 0) {
        $warnings.Add('SecurityFloorWaived: below Light minimum (' + ($floorMissing -join ',') + ')')
    }

    $fieldValues = @{}
    $requiredFields = New-Object System.Collections.Generic.List[string]
    foreach ($id in @($selected)) {
        $feature = Get-CyberButlerFeatureById -Manifest $manifest -Id $id
        if (-not $feature) { continue }
        foreach ($field in @($feature.fields)) {
            $name = [string]$field.name
            if ($requiredFields -notcontains $name) { $requiredFields.Add($name) }
            $value = [string]($Fields[$name])
            if ($field.required -and [string]::IsNullOrWhiteSpace($value)) {
                $errors.Add(('Missing required field {0} for feature {1}.' -f $name, $id))
            }
            if ($value) { $fieldValues[$name] = $value }
        }
    }

    $selectedOrdered = @($manifest.features | Where-Object { $selected -contains $_.id } | ForEach-Object { $_.id })
    $tierLabel = if ($isCustom) { 'Custom (based on ' + $Tier + ')' } else { $Tier }

    return [pscustomobject][ordered]@{
        Tier = $Tier
        TierLabel = $tierLabel
        IsCustom = [bool]$isCustom
        Preset = @($manifest.presets.$Tier)
        FeatureIds = $selectedOrdered
        SelectedFeatures = $selectedOrdered
        RequiredFeatures = $requiredIds
        ApprovalChannel = $ApprovalChannel
        ApprovalFeatures = $selectedChannels
        SecurityFloor = [pscustomobject]@{
            met = ($floorMissing.Count -eq 0)
            missing = @($floorMissing.ToArray())
            ids = @($manifest.minimum)
        }
        SecurityFloorWaived = [bool]($floorMissing.Count -gt 0 -and $AcceptBelowMinimum)
        FieldNames = @($requiredFields.ToArray())
        Fields = $fieldValues
        Errors = @($errors.ToArray())
        Warnings = @($warnings.ToArray())
        ManifestPath = $loaded.Path
    }
}
