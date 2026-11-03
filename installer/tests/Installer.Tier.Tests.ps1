$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
$profileRoot = Join-Path $installerRoot 'profiles'
$scriptPath = Join-Path $installerRoot 'Install-CyberButler.ps1'

. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Tier.ps1')

Describe 'Installer tier resolution' {
    It 'defaults to Medium without isolation' {
        $result = Resolve-CyberButlerTier -Tier Medium -ProfileRoot $profileRoot -InstallPath $TestDrive
        $result.Tier | Should Be 'Medium'
        $result.Isolation | Should Be $false
        $result.EffectiveLabel | Should Be 'Medium'
    }

    It 'lists the Medium approvals exactly as the pipeline requests them' {
        $result = Resolve-CyberButlerTier -Tier Medium -ProfileRoot $profileRoot -InstallPath $TestDrive
        ($result.BlockingApprovals -join ',') | Should Be 'APPROVE PLAN,APPROVE ACL,APPROVE TOTP,APPROVE FIREWALL,APPROVE SECRETS,APPROVE SERVICES'
        ($result.BlockingApprovals -contains 'APPROVE ACCOUNT') | Should Be $false
    }

    It 'includes SECRETS in High and Light approval lists' {
        $high = Resolve-CyberButlerTier -Tier High -ProfileRoot $profileRoot -InstallPath $TestDrive
        ($high.BlockingApprovals -join ',') | Should Be 'APPROVE PLAN,APPROVE ACCOUNT,APPROVE ACL,APPROVE TOTP,APPROVE FIREWALL,APPROVE SECRETS,APPROVE SERVICES'
        $light = Resolve-CyberButlerTier -Tier Light -AcceptLowerSecurity -ProfileRoot $profileRoot -InstallPath $TestDrive
        ($light.BlockingApprovals -join ',') | Should Be 'APPROVE PLAN,APPROVE ACL,APPROVE TOTP,APPROVE FIREWALL,APPROVE SECRETS,APPROVE SERVICES,APPROVE LIGHT'
    }

    It 'forces isolation for High' {
        $result = Resolve-CyberButlerTier -Tier High -ProfileRoot $profileRoot -InstallPath $TestDrive
        $result.Isolation | Should Be $true
        $result.EffectiveLabel | Should Be 'High'
        ($result.BlockingApprovals -contains 'APPROVE SERVICES') | Should Be $true
        ($result.BlockingApprovals -contains 'APPROVE BROKER') | Should Be $false
    }

    It 'rejects High with isolation disabled' {
        $result = Resolve-CyberButlerTier -Tier High -EnableIsolation $false -ProfileRoot $profileRoot -InstallPath $TestDrive
        (($result.Errors -join ' ') -match 'High requires') | Should Be $true
        $result.ExitCode | Should Be 20
    }

    It 'requires AcceptLowerSecurity for Light' {
        $result = Resolve-CyberButlerTier -Tier Light -ProfileRoot $profileRoot -InstallPath $TestDrive
        (($result.Errors -join ' ') -match 'AcceptLowerSecurity') | Should Be $true
        $result.ExitCode | Should Be 20
    }

    It 'labels Light plus isolation without upgrading it to High' {
        $result = Resolve-CyberButlerTier -Tier Light -AcceptLowerSecurity -EnableIsolation $true -ProfileRoot $profileRoot -InstallPath $TestDrive
        $result.EffectiveLabel | Should Be 'Light + Isolation'
        $result.Isolation | Should Be $true
    }

    It 'rejects LAN for High' {
        $result = Resolve-CyberButlerTier -Tier High -WebUIBind LAN -ProfileRoot $profileRoot -InstallPath $TestDrive
        (($result.Errors -join ' ') -match 'LAN') | Should Be $true
        $result.ExitCode | Should Be 20
    }

    It 'marks LAN as blocking for Medium' {
        $result = Resolve-CyberButlerTier -Tier Medium -WebUIBind LAN -ProfileRoot $profileRoot -InstallPath $TestDrive
        ($result.BlockingApprovals -contains 'APPROVE LAN') | Should Be $true
    }

    It 'exposes the explicit approval exit code' {
        (Get-InstallerExitCode -Name NeedsApproval) | Should Be 10
    }
}

Describe 'Installer PlanOnly' {
    It 'plans a fresh install without writing files' {
        $target = Join-Path $env:TEMP ('cb-installer-fresh-' + [guid]::NewGuid().ToString('N'))
        try {
            $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $scriptPath -PlanOnly -Tier Medium -InstallPath $target 2>&1
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'Existing install: None') | Should Be $true
            (Test-Path -LiteralPath $target) | Should Be $false
        } finally {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }

    It 'plans an existing install path as upgrade or repair' {
        $target = Join-Path $env:TEMP ('cb-installer-existing-' + [guid]::NewGuid().ToString('N'))
        try {
            New-Item -ItemType Directory -Path (Join-Path $target 'ExternalAgent') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'VERSION') -Value '1.6.0' -Encoding ASCII
            $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $scriptPath -PlanOnly -Tier Medium -InstallPath $target 2>&1
            $LASTEXITCODE | Should Be 0
            (($out -join "`n") -match 'Existing install: Legacy') | Should Be $true
            (($out -join "`n") -match 'upgrade / repair / migration') | Should Be $true
        } finally {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }

    It 'returns NeedsApproval for non-interactive install' {
        $out = & (Join-Path $PSHOME 'powershell.exe') -NoProfile -ExecutionPolicy Bypass -File $scriptPath -Tier High -NonInteractive 2>&1
        $LASTEXITCODE | Should Be 10
        (($out -join "`n") -match 'interactive approval') | Should Be $true
    }
}
