$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
$manifestPath = Join-Path $installerRoot 'features.v1.json'
. (Join-Path $installerRoot 'lib\Installer.Features.ps1')
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Core.ps1')

Describe 'Cyber-Butler feature resolver v1.7.0' {
    It 'Light preset is the minimum feature set' {
        $r = Resolve-CyberButlerFeatures -Tier Light -Fields @{ OwnerQQ = '10001' } -ManifestPath $manifestPath
        ($r.FeatureIds -join ',') | Should Be 'core,broker,audit,approval.totp,approval.qq'
        $r.SecurityFloor.met | Should Be $true
        $r.SecurityFloorWaived | Should Be $false
    }

    It 'Medium preset adds WebUI' {
        $r = Resolve-CyberButlerFeatures -Tier Medium -Fields @{ OwnerQQ = '10001' } -ManifestPath $manifestPath
        ($r.FeatureIds -contains 'webui') | Should Be $true
        ($r.FeatureIds -contains 'wfp_guard') | Should Be $false
    }

    It 'High preset adds WFP guard' {
        $r = Resolve-CyberButlerFeatures -Tier High -Fields @{ OwnerQQ = '10001' } -ManifestPath $manifestPath
        ($r.FeatureIds -contains 'wfp_guard') | Should Be $true
        $r.TierLabel | Should Be 'High'
    }

    It 'QQ approval does not require email or SMTP' {
        $r = Resolve-CyberButlerFeatures -Tier Light -ApprovalChannel QQ -Fields @{ OwnerQQ = '10001' } -ManifestPath $manifestPath
        $r.ApprovalChannel | Should Be 'QQ'
        ($r.Errors -join ' ') | Should Be ''
        ($r.FieldNames -contains 'SmtpHost') | Should Be $false
    }

    It 'Email approval does not require OwnerQQ' {
        $fields = @{ WebUIAdminEmail = 'owner@example.com'; SmtpHost = 'smtp.163.com'; SmtpPort = '465'; SmtpUser = 'owner@example.com'; SmtpAuthCode = 'secret' }
        $r = Resolve-CyberButlerFeatures -Tier Medium -ApprovalChannel Email -Fields $fields -ManifestPath $manifestPath
        $r.ApprovalChannel | Should Be 'Email'
        ($r.Errors -join ' ') | Should Be ''
        ($r.FieldNames -contains 'OwnerQQ') | Should Be $false
        ($r.FeatureIds -contains 'approval.qq') | Should Be $false
        ($r.FeatureIds -contains 'otp_mailer') | Should Be $true
    }

    It 'Rejects both approval channels at once' {
        $r = Resolve-CyberButlerFeatures -Tier Medium -FeatureIds core,broker,audit,approval.totp,approval.qq,approval.email -Fields @{ OwnerQQ = '1'; WebUIAdminEmail = 'a@b.c'; SmtpHost = 'h'; SmtpPort = '465'; SmtpUser = 'u'; SmtpAuthCode = 'x' } -ManifestPath $manifestPath
        (($r.Errors -join ' ') -match 'mutually exclusive|Exactly one') | Should Be $true
    }

    It 'Rejects no approval channel in custom selection' {
        $r = Resolve-CyberButlerFeatures -Tier Medium -FeatureIds core,broker,audit,approval.totp -ManifestPath $manifestPath
        (($r.Errors -join ' ') -match 'approval channel') | Should Be $true
    }

    It 'Rejects custom selection below minimum without waiver' {
        $r = Resolve-CyberButlerFeatures -Tier Medium -FeatureIds core -ManifestPath $manifestPath
        (($r.Errors -join ' ') -match 'Below Light minimum') | Should Be $true
        $r.SecurityFloorWaived | Should Be $false
    }

    It 'Allows explicit below-minimum waiver and records it' {
        $r = Resolve-CyberButlerFeatures -Tier Medium -FeatureIds core -AcceptBelowMinimum -ManifestPath $manifestPath
        $r.SecurityFloorWaived | Should Be $true
        ($r.Warnings -join ' ') | Should Match 'SecurityFloorWaived'
        $r.TierLabel | Should Be 'Custom (based on Medium)'
    }

    It 'Keeps old Tier-only behavior resolving a preset' {
        # Legacy Tier-only call: preset path, not Custom.
        $legacy = Resolve-CyberButlerFeatures -Tier Light -Fields @{ OwnerQQ = '10001' } -ManifestPath $manifestPath
        $legacy.IsCustom | Should Be $false
        $legacy.TierLabel | Should Be 'Light'
    }

    It 'Uses the same resolver module for GUI and CLI' {
        $gui = Get-Content -LiteralPath (Join-Path $installerRoot 'CyberButler.Installer.GUI.ps1') -Raw
        (($gui -match 'Installer.Features.ps1') -or ($gui -match 'Resolve-CyberButlerFeatures')) | Should Be $true
    }


    It 'Does not leave unselected WebUI/Mailer/WFP/AuxRuntime payload on disk' {
        $root = Join-Path $TestDrive 'payload'
        New-Item -ItemType Directory -Path (Join-Path $root 'webui') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'tools') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $root 'AgentRuntime') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'webui/run.py') -Value 'x' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $root 'webui/otp_mailer.py') -Value 'x' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $root 'tools/wfp_guard.py') -Value 'x' -Encoding ASCII
        $removed = @(Remove-CyberButlerUnselectedPayload -Root $root -Features @('core','broker','audit','approval.totp','approval.qq','webui'))
        (Test-Path (Join-Path $root 'webui/run.py')) | Should Be $true
        (Test-Path (Join-Path $root 'webui/otp_mailer.py')) | Should Be $false
        (Test-Path (Join-Path $root 'tools/wfp_guard.py')) | Should Be $false
        (Test-Path (Join-Path $root 'AgentRuntime')) | Should Be $false
        ($removed -contains 'webui/otp_mailer.py') | Should Be $true
    }

    It 'Removes the whole WebUI tree when neither webui nor otp_mailer is selected' {
        $root = Join-Path $TestDrive 'payload2'
        New-Item -ItemType Directory -Path (Join-Path $root 'webui') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $root 'webui/run.py') -Value 'x' -Encoding ASCII
        $null = Remove-CyberButlerUnselectedPayload -Root $root -Features @('core','broker','audit','approval.totp','approval.qq')
        (Test-Path (Join-Path $root 'webui')) | Should Be $false
    }

    It 'Report model contains feature fields' {
        $report = Get-Content -LiteralPath (Join-Path $installerRoot 'lib\Installer.Report.ps1') -Raw
        (($report -match 'selected_features') -and ($report -match 'security_floor_waived')) | Should Be $true
    }
}
