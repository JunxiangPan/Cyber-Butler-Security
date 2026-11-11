# Dynamic feature selection dialog for the v1.7.0 WPF installer UI.
# Uses the same Resolve-CyberButlerFeatures resolver as the CLI.

function Show-CyberButlerFeatureDialog {
    param(
        [ValidateSet('High', 'Medium', 'Light')]
        [string]$Tier = 'Medium',
        [string]$OwnerQQ = '',
        [string]$WebUIAdminEmail = '',
        [string]$SmtpHost = 'smtp.163.com',
        [string]$SmtpPort = '465',
        [string]$SmtpUser = '',
        [string]$SmtpAuth = ''
    )
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    . (Join-Path $PSScriptRoot 'Installer.Features.ps1')
    $manifestPath = Join-Path $PSScriptRoot '..\features.v1.json'
    $loaded = Get-CyberButlerFeatureManifest -ManifestPath $manifestPath
    $manifest = $loaded.Data

    $form = New-Object System.Windows.Forms.Form
    $form.Text = 'Cyber-Butler features / 功能选择'
    $form.Size = New-Object System.Drawing.Size(720, 680)
    $form.StartPosition = 'CenterParent'
    $form.Topmost = $true

    $top = New-Object System.Windows.Forms.Panel
    $top.Dock = 'Top'; $top.Height = 76
    $form.Controls.Add($top)
    $tierLabel = New-Object System.Windows.Forms.Label
    $tierLabel.Text = 'Tier'; $tierLabel.Left = 12; $tierLabel.Top = 14; $tierLabel.Width = 40
    $top.Controls.Add($tierLabel)
    $tierBox = New-Object System.Windows.Forms.ComboBox
    $tierBox.Left = 58; $tierBox.Top = 10; $tierBox.Width = 160; $tierBox.DropDownStyle = 'DropDownList'
    [void]$tierBox.Items.AddRange(@('High','Medium','Light')); $tierBox.SelectedItem = $Tier
    $top.Controls.Add($tierBox)
    $channelLabel = New-Object System.Windows.Forms.Label
    $channelLabel.Text = 'Approval'; $channelLabel.Left = 240; $channelLabel.Top = 14; $channelLabel.Width = 70
    $top.Controls.Add($channelLabel)
    $channelBox = New-Object System.Windows.Forms.ComboBox
    $channelBox.Left = 312; $channelBox.Top = 10; $channelBox.Width = 120; $channelBox.DropDownStyle = 'DropDownList'
    [void]$channelBox.Items.AddRange(@('QQ','Email')); $channelBox.SelectedItem = if ($WebUIAdminEmail) { 'Email' } else { 'QQ' }
    $top.Controls.Add($channelBox)
    $customLabel = New-Object System.Windows.Forms.Label
    $customLabel.Left = 450; $customLabel.Top = 14; $customLabel.Width = 240; $customLabel.Text = 'Preset'; $customLabel.ForeColor = [Drawing.Color]::DarkSlateGray
    $top.Controls.Add($customLabel)

    $list = New-Object System.Windows.Forms.FlowLayoutPanel
    $list.Left = 12; $list.Top = 82; $list.Width = 330; $list.Height = 430; $list.AutoScroll = $true; $list.FlowDirection = 'TopDown'
    $form.Controls.Add($list)
    $checks = @{}
    foreach ($feature in @($manifest.features)) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = [string]$feature.label
        $cb.Tag = [string]$feature.id
        $cb.Width = 300; $cb.Height = 24
        $list.Controls.Add($cb)
        $checks[[string]$feature.id] = $cb
    }

    $fields = New-Object System.Windows.Forms.Panel
    $fields.Left = 355; $fields.Top = 82; $fields.Width = 340; $fields.Height = 430; $fields.AutoScroll = $true
    $form.Controls.Add($fields)
    $fieldBoxes = @{}
    $fieldDefs = @(
        @{ Name='OwnerQQ'; Label='Owner QQ'; Text=$OwnerQQ; Secret=$false },
        @{ Name='WebUIAdminEmail'; Label='WebUI email'; Text=$WebUIAdminEmail; Secret=$false },
        @{ Name='SmtpHost'; Label='SMTP host'; Text=$SmtpHost; Secret=$false },
        @{ Name='SmtpPort'; Label='SMTP port'; Text=$SmtpPort; Secret=$false },
        @{ Name='SmtpUser'; Label='SMTP user'; Text=$SmtpUser; Secret=$false },
        @{ Name='SmtpAuthCode'; Label='SMTP auth code'; Text=$SmtpAuth; Secret=$true }
    )
    $y = 8
    foreach ($def in $fieldDefs) {
        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = [string]$def.Label; $lbl.Left = 8; $lbl.Top = $y; $lbl.Width = 320
        $fields.Controls.Add($lbl)
        if ($def.Secret) {
            $tb = New-Object System.Windows.Forms.TextBox; $tb.UseSystemPasswordChar = $true
        } else {
            $tb = New-Object System.Windows.Forms.TextBox
        }
        $tb.Left = 8; $tb.Top = $y + 20; $tb.Width = 320; $tb.Text = [string]$def.Text
        $fields.Controls.Add($tb)
        $fieldBoxes[[string]$def.Name] = $tb
        $y += 52
    }
    $fieldHint = New-Object System.Windows.Forms.Label
    $fieldHint.Left = 8; $fieldHint.Top = $y + 4; $fieldHint.Width = 320; $fieldHint.Height = 60
    $fieldHint.Text = 'QQ approval does not require SMTP. Email approval does not require OwnerQQ.'
    $fields.Controls.Add($fieldHint)

    $summary = New-Object System.Windows.Forms.Label
    $summary.Left = 12; $summary.Top = 520; $summary.Width = 680; $summary.Height = 64
    $form.Controls.Add($summary)
    $ok = New-Object System.Windows.Forms.Button
    $ok.Text = 'OK'; $ok.Left = 520; $ok.Top = 590; $ok.Width = 80
    $cancel = New-Object System.Windows.Forms.Button
    $cancel.Text = 'Cancel'; $cancel.Left = 610; $cancel.Top = 590; $cancel.Width = 80
    $form.Controls.Add($ok); $form.Controls.Add($cancel)
    $form.AcceptButton = $ok; $form.CancelButton = $cancel

    $script:dialogResult = $null
    function Update-Fields {
        $isEmail = ($channelBox.SelectedItem -eq 'Email')
        foreach ($name in @('WebUIAdminEmail','SmtpHost','SmtpPort','SmtpUser','SmtpAuthCode')) {
            $fieldBoxes[$name].Visible = $isEmail
            $fieldBoxes[$name].Enabled = $isEmail
        }
        $fieldBoxes['OwnerQQ'].Visible = -not $isEmail
        $fieldBoxes['OwnerQQ'].Enabled = -not $isEmail
        foreach ($ctrl in @($fields.Controls)) {
            if ($ctrl -is [Windows.Forms.Label]) { $ctrl.Visible = $true }
        }
        if ($isEmail) { $customLabel.Text = 'Custom (based on ' + $tierBox.SelectedItem + ')' }
    }
    function Apply-Preset {
        $tier = [string]$tierBox.SelectedItem
        $preset = @($manifest.presets.$tier)
        foreach ($id in $checks.Keys) {
            $feature = @($manifest.features | Where-Object { $_.id -eq $id })[0]
            $checks[$id].Checked = ($preset -contains $id)
            $checks[$id].Enabled = -not [bool]$feature.required
        }
        $channelBox.SelectedItem = if ($preset -contains 'approval.email') { 'Email' } else { 'QQ' }
        $customLabel.Text = $tier
        Update-Fields
        Update-Summary
    }
    function Selected-Ids {
        return @($checks.Keys | Where-Object { $checks[$_].Checked })
    }
    function Update-Summary {
        $ids = Selected-Ids
        $channel = [string]$channelBox.SelectedItem
        $requiredMissing = @($manifest.features | Where-Object { $_.required -and -not ($ids -contains $_.id) } | ForEach-Object { $_.id })
        $approved = @($ids | Where-Object { $_ -like 'approval.*' })
        $summary.Text = 'Selected: ' + ($ids -join ', ') + "`r`nApproval: " + $channel + ' | Required missing: ' + ($requiredMissing -join ',')
    }

    $tierBox.Add_SelectedIndexChanged({ Apply-Preset })
    $channelBox.Add_SelectedIndexChanged({ Update-Fields; Update-Summary })
    foreach ($cb in $checks.Values) { $cb.Add_CheckedChanged({ $customLabel.Text = 'Custom (based on ' + $tierBox.SelectedItem + ')'; Update-Summary }) }
    $cancel.Add_Click({ $script:dialogResult = $null; $form.Close() })
    $ok.Add_Click({
        $ids = @(Selected-Ids)
        $fieldValues = @{}
        foreach ($name in $fieldBoxes.Keys) { $fieldValues[$name] = [string]$fieldBoxes[$name].Text }
        $resolved = Resolve-CyberButlerFeatures -Tier ([string]$tierBox.SelectedItem) -FeatureIds $ids -ApprovalChannel ([string]$channelBox.SelectedItem) -Fields $fieldValues -ManifestPath $manifestPath
        if ($resolved.Errors.Count -gt 0) {
            $below = @($resolved.Errors | Where-Object { $_ -match 'Below Light minimum' })
            if ($below.Count -gt 0) {
                $answer = [Windows.Forms.MessageBox]::Show(('Below Light minimum: ' + ($resolved.SecurityFloor.missing -join ', ') + "`r`n`r`nContinue as Custom and record SecurityFloorWaived?"), 'Security floor', 'YesNo', 'Warning')
                if ($answer -eq 'Yes') {
                    $resolved = Resolve-CyberButlerFeatures -Tier ([string]$tierBox.SelectedItem) -FeatureIds $ids -ApprovalChannel ([string]$channelBox.SelectedItem) -Fields $fieldValues -AcceptBelowMinimum -ManifestPath $manifestPath
                } else { return }
            }
        }
        if ($resolved.Errors.Count -gt 0) {
            [Windows.Forms.MessageBox]::Show(($resolved.Errors -join "`r`n"), 'Feature selection', 'OK', 'Warning') | Out-Null
            return
        }
        $script:dialogResult = [pscustomobject]@{ FeatureIds = @($resolved.FeatureIds); ApprovalChannel = $resolved.ApprovalChannel; AcceptBelowMinimum = [bool]$resolved.SecurityFloorWaived; Fields = $fieldValues; TierLabel = $resolved.TierLabel; SecurityFloorWaived = $resolved.SecurityFloorWaived }
        $form.Close()
    })
    Apply-Preset
    [void]$form.ShowDialog()
    return $script:dialogResult
}
