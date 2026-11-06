$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
$repoRoot = Split-Path -Parent $installerRoot
$gui = Join-Path $installerRoot 'CyberButler.Installer.GUI.ps1'
$helper = Join-Path $installerRoot 'lib\Installer.Gui.ps1'
$startServices = Join-Path $repoRoot 'webui\start-services.ps1'

Describe 'Visual installer' {
    It 'builds a safely quoted installer command' {
        . $helper
        $command = New-CyberButlerInteractiveInstallCommand `
            -InstallerPath "C:\A B\Install-CyberButler.ps1" `
            -Tier Medium `
            -InstallPath "C:\Cyber'Butler" `
            -OwnerQQ "10001" `
            -WebUIBind Loopback
        $command | Should Match "-Tier 'Medium'"
        $command | Should Match "C:\\A B\\Install-CyberButler.ps1"
        $command | Should Match "C:\\Cyber''Butler"
        $command | Should Match "-WebUIBind 'Loopback'"
        $command | Should Not Match 'ApiKeyFile'
    }

    It 'loads its WPF XAML in a self-test' {
        (Test-Path -LiteralPath $gui) | Should Be $true
        $output = & pwsh.exe -NoProfile -STA -ExecutionPolicy Bypass -File $gui -SelfTest 2>&1
        $LASTEXITCODE | Should Be 0
        (($output | ForEach-Object { [string]$_ }) -join "`n") | Should Match 'GUI_XAML_OK'
    }

    It 'keeps the web UI service compatible with both install layouts' {
        $text = Get-Content -LiteralPath $startServices -Raw
        $text | Should Match 'webui-config\.json'
        $text | Should Match 'mailer_token'
        $text | Should Match 'WARN: OTP mailer'
    }
}
