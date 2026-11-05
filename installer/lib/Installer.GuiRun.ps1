# GUI orchestration helpers for the Cyber-Butler installer.
# Keep the privileged install in a hidden child process and surface only the
# approval/TOTP steps through the WPF window.


function Get-CyberButlerSafeLogLine([string]$Line) {
    if ($Line -match '(?i)(recovery codes|qr image|base32 secret|grouped:|otpauth uri|TOTP_(SECRET|URI|RECOVERY)|^\s*\d+\.\s+[A-Z0-9]{8})') {
        return '[TOTP output redacted]'
    }
    return $Line
}

function Write-CyberButlerGuiError {
    param([string]$Message)
    try {
        $path = Join-Path $env:TEMP 'CyberButler-Installer-GUI-error.log'
        Add-Content -LiteralPath $path -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message) -Encoding UTF8
    } catch { Write-Verbose 'optional operation failed' }
}

<#
.SYNOPSIS
    Show-CyberButlerTotpDialog performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Show-CyberButlerTotpDialog {
    param(
        [Parameter(Mandatory = $true)][string]$ReadyPath,
        [Parameter(Mandatory = $true)]$Owner,
        [string]$Title = 'TOTP Enrollment',
        [string]$Hint = '',
        [string]$Scanned = 'I scanned the QR code',
        [string]$Recovery = 'I saved the recovery codes offline',
        [string]$Confirm = 'Confirm and continue',
        [string]$Cancel = 'Cancel'
    )
    $ready = Get-Content -LiteralPath $ReadyPath -Raw | ConvertFrom-Json
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="TOTP Enrollment" Width="560" Height="760"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="#0F172A">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="TotpTitle" Text="TOTP Enrollment" Foreground="#F8FAFC" FontSize="24" FontWeight="SemiBold"/>
    <TextBlock x:Name="TotpHint" Grid.Row="1" Text="" Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,10,0,0"/>
    <Border Grid.Row="2" Background="#FFFFFF" Padding="8" HorizontalAlignment="Left" Margin="0,16,0,0">
      <Image x:Name="QrImage" Width="220" Height="220" Stretch="Uniform"/>
    </Border>
    <TextBox x:Name="RecoveryText" Grid.Row="3" IsReadOnly="True" AcceptsReturn="True"
             VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="13"
             Background="#020617" Foreground="#CBD5E1" BorderBrush="#1E293B"
             Padding="12" TextWrapping="Wrap" Margin="0,16,0,0"/>
    <StackPanel Grid.Row="4" Margin="0,16,0,0">
      <CheckBox x:Name="ScannedCheck" Content="I scanned the QR code" Foreground="#F8FAFC" Margin="0,0,0,10"/>
      <CheckBox x:Name="RecoveryCheck" Content="I saved the recovery codes offline" Foreground="#F8FAFC"/>
    </StackPanel>
    <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,20,0,0">
      <Button x:Name="CancelTotpButton" Content="Cancel" Width="110" Height="36" Margin="0,0,10,0"/>
      <Button x:Name="ConfirmTotpButton" Content="Confirm and continue" Width="180" Height="36"
              Background="#0EA5E9" Foreground="#FFFFFF" BorderBrush="#0EA5E9" FontWeight="SemiBold"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $Owner
    $dialog.FindName('TotpTitle').Text = $Title
    $dialog.FindName('TotpHint').Text = $Hint
    $dialog.FindName('ScannedCheck').Content = $Scanned
    $dialog.FindName('RecoveryCheck').Content = $Recovery
    $dialog.FindName('CancelTotpButton').Content = $Cancel
    $dialog.FindName('ConfirmTotpButton').Content = $Confirm
    if ($ready.qr_path -and (Test-Path -LiteralPath ([string]$ready.qr_path))) {
        $bitmap = New-Object System.Windows.Media.Imaging.BitmapImage
        $bitmap.BeginInit()
        $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
        $bitmap.UriSource = New-Object System.Uri ([string]$ready.qr_path)
        $bitmap.EndInit()
        $dialog.FindName('QrImage').Source = $bitmap
    }
    if ($ready.recovery_path -and (Test-Path -LiteralPath ([string]$ready.recovery_path))) {
        $dialog.FindName('RecoveryText').Text = Get-Content -LiteralPath ([string]$ready.recovery_path) -Raw
    } else {
        $dialog.FindName('RecoveryText').Text = 'Recovery file missing: ' + [string]$ready.recovery_path
    }
    $script:cbTotpDialogResult = $null
    $dialog.FindName('ConfirmTotpButton').Add_Click({
        if ($dialog.FindName('ScannedCheck').IsChecked -and $dialog.FindName('RecoveryCheck').IsChecked) {
            $script:cbTotpDialogResult = [pscustomobject]@{ scanned = $true; recovery_saved = $true }
            $dialog.Close()
        }
    })
    $dialog.FindName('CancelTotpButton').Add_Click({
        $script:cbTotpDialogResult = [pscustomobject]@{ scanned = $false; recovery_saved = $false }
        $dialog.Close()
    })
    [void]$dialog.ShowDialog()
    return $script:cbTotpDialogResult
}




<#
.SYNOPSIS
    Show-CyberButlerInfoWindow performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Show-CyberButlerInfoWindow {
    param(
        [Parameter(Mandatory = $true)]$Owner,
        [string]$Title = 'Information',
        [string]$Text = '',
        [string]$Copy = 'Copy',
        [string]$Close = 'Close'
    )
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Information" Width="760" Height="620"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="#0F172A">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="InfoTitle" Text="Information" Foreground="#F8FAFC" FontSize="22" FontWeight="SemiBold"/>
    <TextBox x:Name="InfoBody" Grid.Row="1" IsReadOnly="True" AcceptsReturn="True"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
             FontFamily="Segoe UI" FontSize="12" Background="#020617"
             Foreground="#CBD5E1" BorderBrush="#1E293B" Padding="12"
             TextWrapping="Wrap" Margin="0,12,0,0"/>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="InfoCopy" Width="100" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="InfoClose" Width="90" Height="34"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    $dialog.Owner = $Owner
    $dialog.FindName('InfoTitle').Text = $Title
    $dialog.FindName('InfoBody').Text = $Text
    $dialog.FindName('InfoCopy').Content = $Copy
    $dialog.FindName('InfoClose').Content = $Close
    $dialog.FindName('InfoCopy').Add_Click({ try { [System.Windows.Clipboard]::SetText($dialog.FindName('InfoBody').Text) } catch { Write-Verbose 'optional operation failed' } })
    $dialog.FindName('InfoClose').Add_Click({ $dialog.Close() })
    [void]$dialog.ShowDialog()
}

<#
.SYNOPSIS
    Show-CyberButlerStatusWindow performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Show-CyberButlerStatusWindow {
    param(
        $Owner = $null,
        [string]$Title = 'Install status',
        [string]$Text = '',
        [string]$Copy = 'Copy',
        [string]$Close = 'Close',
        [string]$Refresh = 'Refresh',
        [scriptblock]$RefreshScript = $null,
        [switch]$SelfTest
    )
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Install status" Width="760" Height="640"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="#0F172A">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="StatusTitle" Text="Install status" Foreground="#F8FAFC" FontSize="22" FontWeight="SemiBold"/>
    <TextBox x:Name="StatusBody" Grid.Row="1" IsReadOnly="True" AcceptsReturn="True"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
             FontFamily="Consolas" FontSize="12" Background="#020617"
             Foreground="#CBD5E1" BorderBrush="#1E293B" Padding="12"
             TextWrapping="NoWrap" Margin="0,12,0,0"/>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,12,0,0">
      <Button x:Name="RefreshStatusButton" Width="100" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="CopyStatusButton" Width="100" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="CloseStatusButton" Width="90" Height="34"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    if ($SelfTest) { return $true }
    $dialog.Owner = $Owner
    $dialog.FindName('StatusTitle').Text = $Title
    $dialog.FindName('StatusBody').Text = $Text
    $dialog.FindName('RefreshStatusButton').Content = $Refresh
    $dialog.FindName('CopyStatusButton').Content = $Copy
    $dialog.FindName('CloseStatusButton').Content = $Close
    $dialog.FindName('RefreshStatusButton').Add_Click({
        if ($RefreshScript) {
            try { $dialog.FindName('StatusBody').Text = [string](& $RefreshScript) } catch { Write-Verbose 'optional operation failed' }
        }
    })
    $dialog.FindName('CopyStatusButton').Add_Click({
        try { [System.Windows.Clipboard]::SetText($dialog.FindName('StatusBody').Text) } catch { Write-Verbose 'optional operation failed' }
    })
    $dialog.FindName('CloseStatusButton').Add_Click({ $dialog.Close() })
    if ($RefreshScript) {
        $timer = New-Object System.Windows.Threading.DispatcherTimer
        $timer.Interval = [TimeSpan]::FromSeconds(3)
        $timer.add_Tick({
            try {
                $next = [string](& $RefreshScript)
                if ($next -and $next -ne [string]$dialog.FindName('StatusBody').Text) {
                    $dialog.FindName('StatusBody').Text = $next
                }
            } catch { Write-Verbose 'optional operation failed' }
        })
        $timer.Start()
        $dialog.Add_Closed({ $timer.Stop() })
    }
    [void]$dialog.ShowDialog()
}


<#
.SYNOPSIS
    Show-CyberButlerRemoveDialog performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Show-CyberButlerRemoveDialog {
    param(
        $Owner = $null,
        [hashtable]$Text = @{},
        [switch]$SelfTest
    )
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Remove Cyber-Butler" Width="640" Height="500"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="#0F172A">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="RemoveTitle" Text="Remove Cyber-Butler" Foreground="#F8FAFC" FontSize="22" FontWeight="SemiBold"/>
    <StackPanel Grid.Row="1" Margin="0,16,0,0">
      <TextBlock x:Name="RemoveHint" Text="Choose what to remove. This cannot be undone." Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,0,0,14"/>
      <RadioButton x:Name="RemovePackage" GroupName="RemoveChoice" Foreground="#F8FAFC" Margin="0,0,0,12"/>
      <RadioButton x:Name="RemoveProject" GroupName="RemoveChoice" Foreground="#F8FAFC" Margin="0,0,0,12"/>
      <RadioButton x:Name="RemoveBoth" GroupName="RemoveChoice" Foreground="#F8FAFC"/>
      <CheckBox x:Name="RemoveServiceAccount" Foreground="#FBBF24" Margin="0,16,0,0"
                Content="同时删除 CyberButlerSvc 服务账户（不会删除 CBS 用户）/ Also remove the CyberButlerSvc service account (never the CBS user)"/>
      <CheckBox x:Name="RemoveBigFish" Foreground="#FBBF24" Margin="0,12,0,0"
                Content="同时删除桌面shared专用文件夹（用户文件，默认保留）/ Also delete the Big Fish folder (user files; kept by default)"/>
      <CheckBox x:Name="RemoveDashboardShortcut" Foreground="#FBBF24" Margin="0,12,0,0" IsChecked="True"
                Content="同时删除桌面 Cyber-Butler 主控台快捷方式 / Also remove the desktop Dashboard shortcut"/>
    </StackPanel>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,16,0,0">
      <Button x:Name="RemoveCancel" Width="100" Height="36" Margin="0,0,10,0"/>
      <Button x:Name="RemoveContinue" Width="140" Height="36" Background="#DC2626" Foreground="#FFFFFF" BorderBrush="#DC2626" FontWeight="SemiBold"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    if ($SelfTest) { return $true }
    $dialog.Owner = $Owner
    $dialog.FindName('RemoveTitle').Text = $(if ($Text['RemoveTitle']) { $Text['RemoveTitle'] } else { 'Remove Cyber-Butler' })
    $dialog.FindName('RemoveHint').Text = $(if ($Text['RemoveHint']) { $Text['RemoveHint'] } else { 'Choose what to remove. This cannot be undone.' })
    $dialog.FindName('RemovePackage').Content = $(if ($Text['RemovePackage']) { $Text['RemovePackage'] } else { 'Installer / downloaded package only' })
    $dialog.FindName('RemoveProject').Content = $(if ($Text['RemoveProject']) { $Text['RemoveProject'] } else { 'Installed Cyber-Butler project only' })
    $dialog.FindName('RemoveBoth').Content = $(if ($Text['RemoveBoth']) { $Text['RemoveBoth'] } else { 'Both installer package and installed project' })
    $dialog.FindName('RemoveCancel').Content = $(if ($Text['Cancel']) { $Text['Cancel'] } else { 'Cancel' })
    $dialog.FindName('RemoveContinue').Content = $(if ($Text['Continue']) { $Text['Continue'] } else { 'Continue' })
    $script:cbRemoveChoice = $null
    $script:cbRemoveCleanup = $false
    $script:cbRemoveBigFish = $false
    $script:cbRemoveDashboardShortcut = $true
    $dialog.FindName('RemoveContinue').Add_Click({
        if ($dialog.FindName('RemovePackage').IsChecked) { $script:cbRemoveChoice = 'package' }
        elseif ($dialog.FindName('RemoveProject').IsChecked) { $script:cbRemoveChoice = 'project' }
        elseif ($dialog.FindName('RemoveBoth').IsChecked) { $script:cbRemoveChoice = 'both' }
        else { return }
        $script:cbRemoveCleanup = [bool]$dialog.FindName('RemoveServiceAccount').IsChecked
        $script:cbRemoveBigFish = [bool]$dialog.FindName('RemoveBigFish').IsChecked
        $script:cbRemoveDashboardShortcut = [bool]$dialog.FindName('RemoveDashboardShortcut').IsChecked
        $dialog.Close()
    })
    $dialog.FindName('RemoveCancel').Add_Click({ $script:cbRemoveChoice = $null; $dialog.Close() })
    [void]$dialog.ShowDialog()
    return $script:cbRemoveChoice
}

<#
.SYNOPSIS
    Remove-CyberButlerPackage performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Remove-CyberButlerPackage {
    param([Parameter(Mandatory = $true)][string]$InstallerRoot)
    $packageRoot = Split-Path -Parent ([IO.Path]::GetFullPath($InstallerRoot)).TrimEnd([char]92)
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'START-INSTALLER.exe'))) {
        throw ('Refusing to remove package without START-INSTALLER.exe: ' + $packageRoot)
    }
    if (-not (Test-Path -LiteralPath (Join-Path $packageRoot 'installer\CyberButler.Installer.GUI.ps1'))) {
        throw ('Refusing to remove package without installer GUI: ' + $packageRoot)
    }
    $targets = New-Object System.Collections.Generic.List[string]
    $targets.Add($packageRoot)
    $versionPath = Join-Path $packageRoot 'VERSION'
    if (Test-Path -LiteralPath $versionPath) {
        try {
            $version = (Get-Content -LiteralPath $versionPath -Raw).Trim()
            $zip = Join-Path (Split-Path -Parent $packageRoot) ('public-release-v' + $version + '.zip')
            if ($version -and (Test-Path -LiteralPath $zip)) { $targets.Add($zip) }
        } catch { Write-Verbose 'optional operation failed' }
    }
    $commands = @()
    foreach ($target in $targets) {
        $escaped = $target.Replace("'", "''")
        # START-INSTALLER.exe is still running until the GUI/launcher exits.
        # Retry after a delay instead of making one attempt that must fail.
        $commands += ("for (`$i=0; `$i -lt 30; `$i++) { try { Remove-Item -LiteralPath '" + $escaped + "' -Recurse -Force -ErrorAction Stop; if (-not (Test-Path -LiteralPath '" + $escaped + "')) { break } } catch { Write-Verbose 'optional operation failed' }; Start-Sleep -Seconds 2 }")
    }
    $command = 'Start-Sleep -Seconds 8; ' + ($commands -join '; ')
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $command) | Out-Null
    return ($targets -join '; ')
}

<#
.SYNOPSIS
    Show-CyberButlerPostInstallWindow performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Show-CyberButlerPostInstallWindow {
    param(
        [Parameter(Mandatory = $true)]$Owner,
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [string]$ReportPath = (Join-Path $env:ProgramData 'CyberButler\installer-report\install-report.json'),
        [string]$GuidePath = '',
        [string]$WebUIUrl = 'http://127.0.0.1:8765/',
        [string]$LaunchGuideText = '',
        [hashtable]$Text = @{},
        [switch]$SelfTest
    )
    if ($SelfTest) { return $true }
    $title = if ($Text['PostTitle']) { $Text['PostTitle'] } else { 'Installation complete' }
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Installation complete" Width="700" Height="520"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False" Background="#0F172A">
  <Grid Margin="24">
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <TextBlock x:Name="PostTitle" Text="Installation complete" Foreground="#F8FAFC" FontSize="26" FontWeight="SemiBold"/>
    <TextBlock x:Name="PostSubtitle" Grid.Row="1" Text="" Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,10,0,0"/>
    <TextBox x:Name="PostBody" Grid.Row="2" IsReadOnly="True" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12" Background="#020617" Foreground="#CBD5E1" BorderBrush="#1E293B" Padding="12" TextWrapping="Wrap" Margin="0,14,0,0"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,14,0,0">
      <Button x:Name="OpenWebUIButton" Content="Open WebUI" Width="110" Height="36" Margin="0,0,6,0" Background="#0EA5E9" Foreground="#FFFFFF" BorderBrush="#0EA5E9"/>
      <Button x:Name="OpenGuideButton" Content="Install guide" Width="105" Height="36" Margin="0,0,6,0"/>
      <Button x:Name="OpenReportButton" Content="Open report" Width="100" Height="36" Margin="0,0,6,0"/>
      <Button x:Name="ClosePostButton" Content="Close" Width="70" Height="36"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $dialog = [System.Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
    $dialog.Owner = $Owner
    $dialog.FindName('PostTitle').Text = $title
    $dialog.FindName('PostSubtitle').Text = 'CBS is installed. It does not bundle or manage an external agent.'
    $body = @(
        '--- Installation / 安装信息 ---',
        ('Install path: ' + $InstallPath),
        ('CBS WebUI: ' + $WebUIUrl),
        ('Report: ' + $ReportPath)
    )
    if ($GuidePath) { $body += ('Guide: ' + $GuidePath) }
    $body += ''
    $body += '--- External agent / 外部 Agent ---'
    $body += 'CBS is an independent control plane. Install an external agent or another agent separately, then connect it to the CBS Broker on port 18090.'
    $body += 'CBS does not install, configure, or manage that external application.'
    $body += ''
    $body += '--- Next / 下一步 ---'
    $body += '1. Open the CBS WebUI and complete approval/TOTP setup.'
    $body += '2. Point your agent at http://127.0.0.1:18090 (Broker).'
    $body += '3. Read docs/API_SPEC.md for the standard integration contract.'
    $dialog.FindName('PostBody').Text = ($body -join "`r`n")
    $dialog.FindName('OpenWebUIButton').Add_Click({ try { Start-Process $WebUIUrl } catch { Write-Verbose 'optional operation failed' } })
    if ($GuidePath -and (Test-Path -LiteralPath $GuidePath)) {
        $dialog.FindName('OpenGuideButton').Add_Click({ try { Start-Process $GuidePath } catch { Write-Verbose 'optional operation failed' } })
    }
    if ($ReportPath -and (Test-Path -LiteralPath (Split-Path -Parent $ReportPath))) {
        $dialog.FindName('OpenReportButton').Add_Click({ try { Start-Process (Split-Path -Parent $ReportPath) } catch { Write-Verbose 'optional operation failed' } })
    }
    $dialog.FindName('ClosePostButton').Add_Click({ $dialog.Close() })
    $dialog.ShowDialog() | Out-Null
    return $true
}
<#
.SYNOPSIS
    Start-CyberButlerGuiInstall performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function Start-CyberButlerGuiInstall {
    param(
        [Parameter(Mandatory = $true)]$Window,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [Parameter(Mandatory = $true)][string]$Tier,
        [string]$DesktopAccount = '',
        [string]$OwnerQQ = '',
        [string]$WebUIBind = 'Loopback',
        [string]$PersonalPluginsPath = '',
        [string]$ApiKeyFile = '',
        [string]$WebUIAdminEmail = '',
        [string]$SmtpAuth = '',
        [string]$SmtpHost = 'smtp.163.com',
        [string]$SmtpPort = '465',
        [Parameter(Mandatory = $true)][scriptblock]$OnLog,
        [Parameter(Mandatory = $true)][scriptblock]$OnStatus,
        [scriptblock]$OnProgress = $null,
        [hashtable]$Text = @{}
    )
    $signalDir = Join-Path $env:TEMP ('cb-gui-totp-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $signalDir -Force | Out-Null
    $configPath = Join-Path $signalDir 'approval-tokens.ps1'
    $configBody = @'
@{
    ApprovalTokens = @{
        'APPROVE PLAN' = 'APPROVE PLAN'
        'APPROVE ACCOUNT' = 'APPROVE ACCOUNT'
        'APPROVE ACL' = 'APPROVE ACL'
        'APPROVE TOTP' = 'APPROVE TOTP'
        'APPROVE FIREWALL' = 'APPROVE FIREWALL'
        'APPROVE SECRETS' = 'APPROVE SECRETS'
        'APPROVE SERVICES' = 'APPROVE SERVICES'
    }
}
'@
    Set-Content -LiteralPath $configPath -Value $configBody -Encoding UTF8

    $desktopAccountValue = if (-not [string]::IsNullOrWhiteSpace($DesktopAccount)) {
        $DesktopAccount
    } else {
        try { [string](Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName } catch { [Security.Principal.WindowsIdentity]::GetCurrent().Name }
    }
    if ([string]::IsNullOrWhiteSpace($desktopAccountValue)) { $desktopAccountValue = [string]$env:USERNAME }
    if ([string]::IsNullOrWhiteSpace($desktopAccountValue)) { throw 'DesktopAccount could not be resolved; refusing to launch installer.' }

    $launchArgs = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $InstallerPath,
        '-Tier', $Tier, '-InstallPath', $InstallPath, '-WebUIBind', $WebUIBind,
        '-DesktopAccount', $desktopAccountValue,
        '-NonInteractive', '-GuiMode', '-GuiSignalDirectory', $signalDir,
        '-TestConfigPath', $configPath,
        '-JournalRoot', 'C:\ProgramData\CyberButler\installer\state',
        '-ReportDirectory', (Join-Path $env:ProgramData 'CyberButler\installer-report')
    )
    if (-not [string]::IsNullOrWhiteSpace($OwnerQQ)) { $launchArgs += @('-OwnerQQ', $OwnerQQ) }
    if (-not [string]::IsNullOrWhiteSpace($PersonalPluginsPath)) { $launchArgs += @('-PersonalPluginsPath', $PersonalPluginsPath) }
    if (-not [string]::IsNullOrWhiteSpace($WebUIAdminEmail)) { $launchArgs += @('-WebUIAdminEmail', $WebUIAdminEmail) }
    if (-not [string]::IsNullOrWhiteSpace($SmtpHost)) { $launchArgs += @('-SmtpHost', $SmtpHost) }
    if (-not [string]::IsNullOrWhiteSpace($SmtpPort)) { $launchArgs += @('-SmtpPort', $SmtpPort) }
    if ($Tier -eq 'High') { $launchArgs += @('-EnableIsolation', 'true') }
    if ($Tier -eq 'Light') { $launchArgs += @('-AcceptLowerSecurity') }
    if (-not [string]::IsNullOrWhiteSpace($ApiKeyFile)) {
        $launchArgs += @('-ApiKeyFile', $ApiKeyFile, '-SkipSmtp')
    } else {
        $launchArgs += @('-SkipSecrets')
    }

    $argumentLine = (($launchArgs | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
    $script:cbGuiWindow = $Window
    $script:cbGuiOnLog = $OnLog
    $script:cbGuiOnStatus = $OnStatus
    $script:cbGuiOnProgress = $OnProgress
    $script:cbGuiText = $Text
    $stdoutPath = Join-Path $signalDir 'installer.out.log'
    $stderrPath = Join-Path $signalDir 'installer.err.log'
    $oldSmtpAuth = $env:CB_SMTP_AUTH_CODE
    if (-not [string]::IsNullOrWhiteSpace($SmtpAuth)) { $env:CB_SMTP_AUTH_CODE = $SmtpAuth }
    try {
        $process = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList $argumentLine `
        -WorkingDirectory (Split-Path -Parent $InstallerPath) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru
    } finally {
        if ($null -eq $oldSmtpAuth) { Remove-Item Env:CB_SMTP_AUTH_CODE -ErrorAction SilentlyContinue }
        else { $env:CB_SMTP_AUTH_CODE = $oldSmtpAuth }
    }
    $script:cbGuiLogPath = $stdoutPath
    $script:cbGuiErrPath = $stderrPath
    & $script:cbGuiOnStatus ($script:cbGuiText['Started'])
    $script:cbGuiProcess = $process
    $script:cbGuiStartTime = Get-Date
    $script:cbGuiSignalDir = $signalDir
    $script:cbGuiTotpSeen = $false
    $script:cbGuiPercent = 0
    $script:cbGuiTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:cbGuiTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:cbGuiTimer.add_Tick({
        if ($script:cbGuiProcess -and $script:cbGuiProcess.HasExited) {
            $script:cbGuiTimer.Stop()
            try { & $script:cbGuiOnStatus ($(if ($script:cbGuiProcess.ExitCode -eq 0) { 'Installation finished.' } else { 'Installation failed; review the report.' })) } catch { Write-Verbose 'optional operation failed' }
            return
        }
        if ($script:cbGuiOnProgress -and $script:cbGuiLogPath -and (Test-Path -LiteralPath $script:cbGuiLogPath)) {
            try {
                $tail = @(Get-Content -LiteralPath $script:cbGuiLogPath -Tail 40 -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object { $_ -and $_.Trim() })
                if ($tail.Count -gt 0) {
                    $last = Get-CyberButlerSafeLogLine ([string]$tail[$tail.Count - 1])
                    $text = ($tail -join "`n")
                    $target = 10
                    if ($text -match 'CORE start') { $target = 15 }
                    if ($text -match 'CORE downloaded') { $target = 25 }
                    if ($text -match 'Using cached|Installing collected|Successfully installed|Requirement already satisfied') { $target = 35 }
                    if ($text -match 'CORE completed') { $target = 45 }
                    if ($text -match 'ACL') { $target = 55 }
                    if ($text -match 'TOTP' -and $script:cbGuiSignalDir -and (Test-Path -LiteralPath (Join-Path $script:cbGuiSignalDir 'totp-ready.json'))) { $target = 65 }
                    if ($text -match 'SERVICE registering') { $target = 80 }
                    if ($text -match 'INSTALLER_OK|Install completed') { $target = 100 }
                    if ($target -gt $script:cbGuiPercent) { $script:cbGuiPercent = $target }
                    $percent = $script:cbGuiPercent
                    $message = $last
                    if ($script:cbGuiPercent -eq 15) { $message = 'Core: downloading / extracting' }
                    elseif ($script:cbGuiPercent -eq 25) { $message = 'Core: preparing files' }
                    elseif ($script:cbGuiPercent -eq 35) { $message = 'Core: pip install in progress (this can take several minutes)' }
                    elseif ($script:cbGuiPercent -eq 45) { $message = 'Core completed; applying overlay' }
                    elseif ($script:cbGuiPercent -eq 55) { $message = 'ACL / broker ACL' }
                    elseif ($script:cbGuiPercent -eq 65) { $message = 'TOTP: material ready / waiting for enrollment' }
                    elseif ($script:cbGuiPercent -eq 80) { $message = 'Services: registering tasks / waiting for ports' }
                    elseif ($script:cbGuiPercent -eq 100) { $message = 'Installation complete' }
                    $script:cbGuiWindow.Dispatcher.Invoke([Action]{ & $script:cbGuiOnProgress $percent $message })
                }
            } catch { Write-Verbose 'optional operation failed' }
        }
        if ($script:cbGuiTotpSeen) { return }
        $readyPath = Join-Path $script:cbGuiSignalDir 'totp-ready.json'
        if (-not (Test-Path -LiteralPath $readyPath)) { return }
        $script:cbGuiTotpSeen = $true
        $script:cbGuiTimer.Stop()
        try { & $script:cbGuiOnLog ($script:cbGuiText['TotpReady']) } catch { Write-Verbose 'optional operation failed' }
        $result = $null
        try {
            $result = Show-CyberButlerTotpDialog -ReadyPath $readyPath -Owner $script:cbGuiWindow `
                -Title $script:cbGuiText['TotpTitle'] -Hint $script:cbGuiText['TotpHint'] `
                -Scanned $script:cbGuiText['Scanned'] -Recovery $script:cbGuiText['Recovery'] `
                -Confirm $script:cbGuiText['Confirm'] -Cancel $script:cbGuiText['Cancel']
        } catch {
            $message = 'TOTP dialog failed: ' + $_.Exception.Message
            Write-CyberButlerGuiError $message
            try { & $script:cbGuiOnLog $message } catch { Write-Verbose 'optional operation failed' }
            $ready = Get-Content -LiteralPath $readyPath -Raw | ConvertFrom-Json
            $fallback = "TOTP material is ready.`n`nQR: $($ready.qr_path)`nRecovery: $($ready.recovery_path)`n`nOpen both files, scan the QR, save the recovery codes, then click Yes."
            $answer = [System.Windows.MessageBox]::Show($fallback, 'TOTP enrollment', 'YesNo', 'Warning')
            $result = [pscustomobject]@{ scanned = ($answer -eq 'Yes'); recovery_saved = ($answer -eq 'Yes') }
        }
        if ($null -eq $result) { $result = [pscustomobject]@{ scanned = $false; recovery_saved = $false } }
        [pscustomobject]@{
            scanned = [bool]$result.scanned
            recovery_saved = [bool]$result.recovery_saved
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:cbGuiSignalDir 'totp-confirm.json') -Encoding UTF8
        try { & $script:cbGuiOnLog ($script:cbGuiText['TotpConfirmed']) } catch { Write-Verbose 'optional operation failed' }
        $script:cbGuiTimer.Start()
    })
    $script:cbGuiTimer.Start()
    return $process
}
