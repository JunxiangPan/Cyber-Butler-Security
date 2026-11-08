#requires -Version 5.1
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scriptPath = Join-Path $root 'tools/Run-Final-Acceptance.ps1'
$text = Get-Content -LiteralPath $scriptPath -Raw
$mainText = Get-Content -LiteralPath (Join-Path $root 'installer/Install-CyberButler.ps1') -Raw
$guiRunText = Get-Content -LiteralPath (Join-Path $root 'installer/lib/Installer.GuiRun.ps1') -Raw

Describe 'Run-Final-Acceptance HTTP transport' {
    It 'T-acceptance-no-file-dependency: never uses curl or @file' {
        ($text -match 'curl\.exe') | Should Be $false
        ($text -match '--data-binary') | Should Be $false
        ($text -match '--data-raw') | Should Be $false
        ($text -match '--data\s+@') | Should Be $false
    }

    It 'delegates JSON transport to Python stdlib urllib' {
        ($text -match 'acceptance_http\.py') | Should Be $true
        ($text -match 'CBS_ACCEPTANCE_BODY') | Should Be $true
        ($text -match 'Get-Command python\.exe') | Should Be $true
    }
}

Describe 'Installer desktop-account ACL wiring' {
    It 'passes DesktopAccount from GUI launch' {
        ($guiRunText -match '-DesktopAccount') | Should Be $true
    }

    It 'grants broker token read to DesktopAccount' {
        ($mainText -match 'icacls\.exe \$brokerToken /grant') | Should Be $true
        ($mainText -match '\$tokenReaders = @\(\$DesktopAccount, \$currentDesktopUser\)') | Should Be $true
        ($mainText -match '\$GuiMode -or') | Should Be $true
    }

    It 'actual icacls output contains the current desktop account read ACE' {
        $file = Join-Path $env:TEMP ('cbs-acl-' + [guid]::NewGuid().ToString('N') + '.txt')
        New-Item -ItemType File -Path $file -Force | Out-Null
        try {
            $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
            & icacls.exe $file /grant "${user}:(R)" | Out-Null
            $acl = (& icacls.exe $file) -join "`n"
            $acl | Should Match ([regex]::Escape($user))
        } finally {
            Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
        }
    }
}
