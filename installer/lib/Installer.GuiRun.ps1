# GUI orchestration helpers for the Cyber-Butler installer.
# Keep the privileged install in a hidden child process and surface only the
# approval/TOTP steps through the WPF window.

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

function Start-CyberButlerGuiInstall {
    param(
        [Parameter(Mandatory = $true)]$Window,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [Parameter(Mandatory = $true)][string]$Tier,
        [string]$OwnerQQ = '',
        [string]$WebUIBind = 'Loopback',
        [string]$PersonalPluginsPath = '',
        [Parameter(Mandatory = $true)][scriptblock]$OnLog,
        [Parameter(Mandatory = $true)][scriptblock]$OnStatus,
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
        '-NonInteractive', '-GuiMode', '-GuiSignalDirectory', $signalDir, '-SkipSecrets',
        '-TestConfigPath', $configPath,
        '-JournalRoot', 'C:\ProgramData\CyberButler\installer\state',
        '-ReportDirectory', 'C:\CyberButler\installer-report'
    )
    if (-not [string]::IsNullOrWhiteSpace($OwnerQQ)) { $args += @('-OwnerQQ', $OwnerQQ) }
    if (-not [string]::IsNullOrWhiteSpace($PersonalPluginsPath)) { $args += @('-PersonalPluginsPath', $PersonalPluginsPath) }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = (($args | ForEach-Object { if ($_ -match '[\s"]') { '"' + ($_ -replace '"','\"') + '"' } else { $_ } }) -join ' ')
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = Split-Path -Parent $InstallerPath
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    $process.add_OutputDataReceived({
        param($sender, $e)
        if ($null -eq $e.Data) { return }
        $line = [string]$e.Data
        if ($line -match 'TOTP_SECRET=|TOTP_URI=|TOTP_RECOVERY_|Base32 Secret|Grouped:|otpauth URI|Recovery codes') { return }
        $Window.Dispatcher.Invoke([Action]{ & $OnLog $line })
    })
    $process.add_ErrorDataReceived({
        param($sender, $e)
        if ($null -ne $e.Data) { $Window.Dispatcher.Invoke([Action]{ & $OnLog ([string]$e.Data) }) }
    })
    $process.add_Exited({
        param($sender, $e)
        $Window.Dispatcher.Invoke([Action]{
            if ($script:cbGuiTimer) { $script:cbGuiTimer.Stop() }
            & $OnStatus ($(if ($sender.ExitCode -eq 0) { 'Installation finished.' } else { 'Installation failed; review the report.' }))
        })
    })

    [void]$process.Start()
    $process.BeginOutputReadLine()
    $process.BeginErrorReadLine()
    & $OnStatus ($Text['Started'])
    $script:cbGuiProcess = $process
    $script:cbGuiSignalDir = $signalDir
    $script:cbGuiTotpSeen = $false
    $script:cbGuiTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:cbGuiTimer.Interval = [TimeSpan]::FromSeconds(1)
    $script:cbGuiTimer.add_Tick({
        if ($script:cbGuiTotpSeen) { return }
        $readyPath = Join-Path $script:cbGuiSignalDir 'totp-ready.json'
        if (-not (Test-Path -LiteralPath $readyPath)) { return }
        $script:cbGuiTotpSeen = $true
        $script:cbGuiTimer.Stop()
        $result = Show-CyberButlerTotpDialog -ReadyPath $readyPath -Owner $Window `
            -Title $Text['TotpTitle'] -Hint $Text['TotpHint'] `
            -Scanned $Text['Scanned'] -Recovery $Text['Recovery'] `
            -Confirm $Text['Confirm'] -Cancel $Text['Cancel']
        if ($null -eq $result) { $result = [pscustomobject]@{ scanned = $false; recovery_saved = $false } }
        [pscustomobject]@{
            scanned = [bool]$result.scanned
            recovery_saved = [bool]$result.recovery_saved
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $script:cbGuiSignalDir 'totp-confirm.json') -Encoding UTF8
        & $OnLog ($Text['TotpReady'])
    })
    $script:cbGuiTimer.Start()
    return $process
}
