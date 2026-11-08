$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
. (Join-Path $root 'installer\lib\Installer.Core.ps1')

Describe 'Broker token ACL checks' {
    It 'accepts DOMAIN\User and User forms using the account SID' {
        $path = Join-Path $env:TEMP ('cbs-acl-' + [guid]::NewGuid().ToString('N') + '.txt')
        Set-Content -LiteralPath $path -Value 'token' -Encoding ASCII
        try {
            $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
            $sid = $identity.User.Value
            & icacls.exe $path /inheritance:r /grant:r ('*' + $sid + ':(R)') | Out-Null
            $LASTEXITCODE | Should Be 0
            (Test-CyberButlerTokenReadAcl -Path $path -Account $identity.Name) | Should Be $true
            (Test-CyberButlerTokenReadAcl -Path $path -Account $identity.Name.Split('\')[-1]) | Should Be $true
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not use unescaped display-name regex matching' {
        $source = Get-Content -LiteralPath (Join-Path $root 'installer\Install-CyberButler.ps1') -Raw
        $source | Should Not Match '\$aclText\s+-notmatch'
        $source | Should Match 'Test-CyberButlerTokenReadAcl'
        $source | Should Match 'Translate\(\[System\.Security\.Principal\.SecurityIdentifier\]\)'
    }

    It 'returns false for empty or invalid account names instead of throwing' {
        $path = Join-Path $env:TEMP ('cbs-acl-negative-' + [guid]::NewGuid().ToString('N') + '.txt')
        Set-Content -LiteralPath $path -Value 'token' -Encoding ASCII
        try {
            (Test-CyberButlerTokenReadAcl -Path $path -Account '') | Should Be $false
            (Test-CyberButlerTokenReadAcl -Path $path -Account 'NotARealDomain\NotAUser') | Should Be $false
        } finally {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }

    It 'wraps SID translation in try-catch in the installer' {
        $source = Get-Content -LiteralPath (Join-Path $root 'installer\Install-CyberButler.ps1') -Raw
        $source | Should Match 'try\s*\{[^}]*Translate'
        $source | Should Match 'Failed to resolve SID for user'
    }
}
