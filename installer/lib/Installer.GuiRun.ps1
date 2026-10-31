# GUI orchestration helpers for the Cyber-Butler installer.
# Keep the privileged install in a hidden child process and surface only the
# approval/TOTP steps through the WPF window.

function Write-CyberButlerGuiError {
    param([string]$Message)
    try {
        $path = Join-Path $env:TEMP 'CyberButler-Installer-GUI-error.log'
        Add-Content -LiteralPath $path -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message) -Encoding UTF8
    } catch { }
}

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
            try { $dialog.FindName('StatusBody').Text = [string](& $RefreshScript) } catch { }
        }
    })
    $dialog.FindName('CopyStatusButton').Add_Click({
        try { [System.Windows.Clipboard]::SetText($dialog.FindName('StatusBody').Text) } catch { }
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
            } catch { }
        })
        $timer.Start()
        $dialog.Add_Closed({ $timer.Stop() })
    }
    [void]$dialog.ShowDialog()
}

function Show-CyberButlerPostInstallWindow {
    param(
        [Parameter(Mandatory = $true)]$Owner,
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [string]$ReportPath = 'C:\CyberButler\installer-report\install-report.json',
        [string]$GuidePath = '',
        [string]$WebUIUrl = 'http://127.0.0.1:8765/',
        [string]$AstrBotUrl = 'http://127.0.0.1:6185/',
        [hashtable]$Text = @{},
        [switch]$SelfTest
    )
    $title = if ($Text['PostTitle']) { $Text['PostTitle'] } else { 'Installation complete' }
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Installation complete" Width="760" Height="620"
        WindowStartupLocation="CenterOwner" ShowInTaskbar="False"
        Background="#0F172A">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="PostTitle" Text="Installation complete" Foreground="#F8FAFC" FontSize="26" FontWeight="SemiBold"/>
    <TextBlock x:Name="PostSubtitle" Grid.Row="1" Text="" Foreground="#94A3B8" TextWrapping="Wrap" Margin="0,10,0,0"/>
    <TextBox x:Name="PostBody" Grid.Row="2" IsReadOnly="True" AcceptsReturn="True"
             VerticalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12"
             Background="#020617" Foreground="#CBD5E1" BorderBrush="#1E293B"
             Padding="12" TextWrapping="Wrap" Margin="0,14,0,0"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,14,0,0">
      <Button x:Name="OpenWebUIButton" Content="Open WebUI" Width="130" Height="36" Margin="0,0,8,0" Background="#0EA5E9" Foreground="#FFFFFF" BorderBrush="#0EA5E9"/>
      <Button x:Name="OpenAstrBotButton" Content="Open AstrBot" Width="130" Height="36" Margin="0,0,8,0"/>
      <Button x:Name="OpenGuideButton" Content="Install guide" Width="130" Height="36" Margin="0,0,8,0"/>
      <Button x:Name="OpenReportButton" Content="Open report" Width="120" Height="36" Margin="0,0,8,0"/>
      <Button x:Name="ClosePostButton" Content="Close" Width="90" Height="36"/>
    </StackPanel>
    <TextBlock Grid.Row="4" Text="" Foreground="#64748B" FontSize="11" Margin="0,16,0,0" TextWrapping="Wrap"/>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    if ($SelfTest) { return $true }
    $dialog.Owner = $Owner
    $dialog.FindName('PostTitle').Text = $title
    $dialog.FindName('PostSubtitle').Text = $(if ($Text['PostSubtitle']) { $Text['PostSubtitle'] } else { 'The three services are installed. Open the WebUI and configure the bot account and model provider next.' })
    $body = @()
    $body += 'Install path: ' + $InstallPath
    $body += 'WebUI: ' + $WebUIUrl
    $body += 'AstrBot: ' + $AstrBotUrl
    $body += 'Report: ' + $ReportPath
    if ($GuidePath) { $body += 'Guide: ' + $GuidePath }
    $body += ''
    $body += $(if ($Text['PostNext']) { $Text['PostNext'] } else { 'Next: open WebUI -> configure the bot QQ adapter -> add other model providers -> send a test message -> keep TOTP recovery codes offline.' })
    $dialog.FindName('PostBody').Text = ($body -join "`r`n")
    $dialog.FindName('OpenWebUIButton').Content = $(if ($Text['OpenWebUI']) { $Text['OpenWebUI'] } else { 'Open WebUI' })
    $dialog.FindName('OpenAstrBotButton').Content = $(if ($Text['OpenAstrBot']) { $Text['OpenAstrBot'] } else { 'Open AstrBot' })
    $dialog.FindName('OpenGuideButton').Content = $(if ($Text['OpenGuide']) { $Text['OpenGuide'] } else { 'Install guide' })
    $dialog.FindName('OpenReportButton').Content = $(if ($Text['OpenReport']) { $Text['OpenReport'] } else { 'Open report' })
    $dialog.FindName('ClosePostButton').Content = $(if ($Text['Close']) { $Text['Close'] } else { 'Close' })
    $dialog.FindName('OpenWebUIButton').Add_Click({ try { Start-Process $WebUIUrl } catch { } })
    $dialog.FindName('OpenAstrBotButton').Add_Click({ try { Start-Process $AstrBotUrl } catch { } })
    $dialog.FindName('OpenGuideButton').Add_Click({ if ($GuidePath -and (Test-Path -LiteralPath $GuidePath)) { Start-Process $GuidePath } })
    $dialog.FindName('OpenReportButton').Add_Click({ if (Test-Path -LiteralPath $ReportPath) { Start-Process $ReportPath } elseif (Test-Path -LiteralPath (Split-Path -Parent $ReportPath)) { Start-Process (Split-Path -Parent $ReportPath) } })
    $dialog.FindName('ClosePostButton').Add_Click({ $dialog.Close() })
    [void]$dialog.ShowDialog()
}

function Start-CyberButlerGuiInstall {
    param(
        [Parameter(Mandatory = $true)]$Window,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [Parameter(Mandatory = $true)][string]$Tier,
        [string]$OwnerQQ = '',
        [string]$WebUIBind = 'Loopback',
        [string]$PersonalPluginsPath = '',
        [string]$ApiKeyFile = '',
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

    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $InstallerPath,
        '-Tier', $Tier, '-InstallPath', $InstallPath, '-WebUIBind', $WebUIBind,
        '-NonInteractive', '-GuiMode', '-GuiSignalDirectory', $signalDir,
        '-TestConfigPath', $configPath,
        '-JournalRoot', 'C:\ProgramData\CyberButler\installer\state',
        '-ReportDirectory', 'C:\CyberButler\installer-report'
    )
    if (-not [string]::IsNullOrWhiteSpace($OwnerQQ)) { $args += @('-OwnerQQ', $OwnerQQ) }
    if (-not [string]::IsNullOrWhiteSpace($PersonalPluginsPath)) { $args += @('-PersonalPluginsPath', $PersonalPluginsPath) }
    if (-not [string]::IsNullOrWhiteSpace($ApiKeyFile)) {
        $args += @('-ApiKeyFile', $ApiKeyFile, '-SkipSmtp')
    } else {
        $args += @('-SkipSecrets')
    }

    $argumentLine = (($args | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
    $script:cbGuiWindow = $Window
    $script:cbGuiOnLog = $OnLog
    $script:cbGuiOnStatus = $OnStatus
    $script:cbGuiOnProgress = $OnProgress
    $script:cbGuiText = $Text
    $stdoutPath = Join-Path $signalDir 'installer.out.log'
    $stderrPath = Join-Path $signalDir 'installer.err.log'
    $process = Start-Process -FilePath 'powershell.exe' `
        -ArgumentList $argumentLine `
        -WorkingDirectory (Split-Path -Parent $InstallerPath) `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdoutPath `
        -RedirectStandardError $stderrPath `
        -PassThru
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
            try { & $script:cbGuiOnStatus ($(if ($script:cbGuiProcess.ExitCode -eq 0) { 'Installation finished.' } else { 'Installation failed; review the report.' })) } catch { }
            return
        }
        if ($script:cbGuiOnProgress -and $script:cbGuiLogPath -and (Test-Path -LiteralPath $script:cbGuiLogPath)) {
            try {
                $tail = @(Get-Content -LiteralPath $script:cbGuiLogPath -Tail 40 -ErrorAction SilentlyContinue | Where-Object { $_ -and $_.Trim() })
                if ($tail.Count -gt 0) {
                    $last = [string]$tail[$tail.Count - 1]
                    $text = ($tail -join "`n")
                    $target = 10
                    if ($text -match 'CORE start') { $target = 15 }
                    if ($text -match 'CORE downloaded') { $target = 25 }
                    if ($text -match 'Using cached|Installing collected|Successfully installed|Requirement already satisfied') { $target = 35 }
                    if ($text -match 'CORE completed') { $target = 45 }
                    if ($text -match 'ACL') { $target = 55 }
                    if ($text -match 'TOTP') { $target = 65 }
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
            } catch { }
        }
        if ($script:cbGuiTotpSeen) { return }
        $readyPath = Join-Path $script:cbGuiSignalDir 'totp-ready.json'
        if (-not (Test-Path -LiteralPath $readyPath)) { return }
        $script:cbGuiTotpSeen = $true
        $script:cbGuiTimer.Stop()
        try { & $script:cbGuiOnLog ($script:cbGuiText['TotpReady']) } catch { }
        $result = $null
        try {
            $result = Show-CyberButlerTotpDialog -ReadyPath $readyPath -Owner $script:cbGuiWindow `
                -Title $script:cbGuiText['TotpTitle'] -Hint $script:cbGuiText['TotpHint'] `
                -Scanned $script:cbGuiText['Scanned'] -Recovery $script:cbGuiText['Recovery'] `
                -Confirm $script:cbGuiText['Confirm'] -Cancel $script:cbGuiText['Cancel']
        } catch {
            $message = 'TOTP dialog failed: ' + $_.Exception.Message
            Write-CyberButlerGuiError $message
            try { & $script:cbGuiOnLog $message } catch { }
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
        try { & $script:cbGuiOnLog ($script:cbGuiText['TotpConfirmed']) } catch { }
        $script:cbGuiTimer.Start()
    })
    $script:cbGuiTimer.Start()
    return $process
}
