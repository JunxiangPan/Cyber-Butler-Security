# Cyber-Butler v1.6.1 visual installer front-end.
# The actual privileged installation still runs in a visible elevated console so
# approval tokens and TOTP enrollment remain explicit, auditable user actions.

param(
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

$installerRoot = $PSScriptRoot
$installerPath = Join-Path $installerRoot 'Install-CyberButler.ps1'
$guiHelper = Join-Path $installerRoot 'lib\Installer.Gui.ps1'
. $guiHelper

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Cyber-Butler Setup"
        Width="980" Height="760"
        MinWidth="860" MinHeight="640"
        WindowStartupLocation="CenterScreen"
        Background="#0F172A">
  <Grid Margin="30">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,22">
      <TextBlock Text="Cyber-Butler Setup" Foreground="#F8FAFC" FontSize="30" FontWeight="SemiBold"/>
      <TextBlock Text="v1.6.1 · visual installer front-end"
                 Foreground="#94A3B8" FontSize="13" Margin="0,7,0,0"/>
      <TextBlock Text="The console handoff keeps approval tokens and TOTP enrollment explicit. Complete those prompts in the elevated window."
                 Foreground="#FBBF24" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"/>
    </StackPanel>

    <Border Grid.Row="1" Background="#111C33" CornerRadius="12" Padding="20" Margin="0,0,0,16">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="180"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="20"/>
          <ColumnDefinition Width="180"/>
          <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
          <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <TextBlock Grid.Row="0" Grid.Column="0" Text="Install path" Foreground="#CBD5E1" VerticalAlignment="Center"/>
        <TextBox Grid.Row="0" Grid.Column="1" x:Name="InstallPathBox" Text="C:\CyberButler"
                 Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

        <TextBlock Grid.Row="0" Grid.Column="3" Text="Tier" Foreground="#CBD5E1" VerticalAlignment="Center"/>
        <ComboBox Grid.Row="0" Grid.Column="4" x:Name="TierBox" SelectedIndex="1"
                  Background="#0B1220" Foreground="#111827" Padding="6">
          <ComboBoxItem Content="High"/>
          <ComboBoxItem Content="Medium"/>
          <ComboBoxItem Content="Light"/>
        </ComboBox>

        <TextBlock Grid.Row="1" Grid.Column="0" Text="Owner QQ" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
        <TextBox Grid.Row="1" Grid.Column="1" x:Name="OwnerQQBox" Margin="0,12,0,0"
                 Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

        <TextBlock Grid.Row="1" Grid.Column="3" Text="WebUI bind" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
        <ComboBox Grid.Row="1" Grid.Column="4" x:Name="BindBox" SelectedIndex="0" Margin="0,12,0,0"
                  Background="#0B1220" Foreground="#111827" Padding="6">
          <ComboBoxItem Content="Loopback"/>
          <ComboBoxItem Content="Tailscale"/>
          <ComboBoxItem Content="LAN"/>
        </ComboBox>

        <TextBlock Grid.Row="2" Grid.Column="0" Text="Personal plugins" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
        <TextBox Grid.Row="2" Grid.Column="1" x:Name="PersonalPluginsBox" Margin="0,12,0,0"
                 Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

        <TextBlock Grid.Row="2" Grid.Column="3" Text="API key file (optional)" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
        <TextBox Grid.Row="2" Grid.Column="4" x:Name="ApiKeyFileBox" Margin="0,12,0,0"
                 Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

        <TextBlock Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="5"
                   Text="API keys are not stored in this UI. The optional file is read by the installer and never written to the GUI log."
                   Foreground="#64748B" FontSize="11" TextWrapping="Wrap" Margin="0,14,0,0"/>
      </Grid>
    </Border>

    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,14">
      <Button x:Name="PreflightButton" Content="Run preflight" Width="150" Height="38" Margin="0,0,10,0"/>
      <Button x:Name="StartButton" Content="Start installation" Width="170" Height="38" Margin="0,0,10,0"
              Background="#0EA5E9" Foreground="#FFFFFF" BorderBrush="#0EA5E9" FontWeight="SemiBold"/>
      <Button x:Name="ReportButton" Content="Open report folder" Width="170" Height="38" Margin="0,0,10,0"/>
      <Button x:Name="CloseButton" Content="Exit" Width="90" Height="38"/>
    </StackPanel>

    <TextBox Grid.Row="3" x:Name="LogBox" IsReadOnly="True" AcceptsReturn="True"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
             FontFamily="Consolas" FontSize="12"
             Background="#020617" Foreground="#CBD5E1" BorderBrush="#1E293B"
             Padding="14" TextWrapping="NoWrap"/>

    <TextBlock Grid.Row="4" x:Name="StatusText" Text="Ready."
               Foreground="#94A3B8" FontSize="12" Margin="0,12,0,0"/>

    <StackPanel Grid.Row="5" Orientation="Horizontal" Margin="0,8,0,0">
      <TextBlock Text="Installer: " Foreground="#475569" FontSize="11"/>
      <TextBlock x:Name="InstallerPathText" Text="" Foreground="#64748B" FontSize="11" TextTrimming="CharacterEllipsis" Width="760"/>
    </StackPanel>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$installPathBox = $window.FindName('InstallPathBox')
$tierBox = $window.FindName('TierBox')
$ownerQQBox = $window.FindName('OwnerQQBox')
$bindBox = $window.FindName('BindBox')
$personalPluginsBox = $window.FindName('PersonalPluginsBox')
$apiKeyFileBox = $window.FindName('ApiKeyFileBox')
$preflightButton = $window.FindName('PreflightButton')
$startButton = $window.FindName('StartButton')
$reportButton = $window.FindName('ReportButton')
$closeButton = $window.FindName('CloseButton')
$logBox = $window.FindName('LogBox')
$statusText = $window.FindName('StatusText')
$installerPathText = $window.FindName('InstallerPathText')
$installerPathText.Text = $installerPath

function Write-GuiLog([string]$message) {
    $line = '[{0:HH:mm:ss}] {1}' -f (Get-Date), $message
    $logBox.AppendText($line + "`r`n")
    $logBox.ScrollToEnd()
}

function Get-SelectedComboText($combo) {
    if ($null -eq $combo.SelectedItem) { return '' }
    if ($combo.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) { return [string]$combo.SelectedItem.Content }
    return [string]$combo.SelectedItem
}

$preflightButton.Add_Click({
    try {
        $installPath = [string]$installPathBox.Text
        if ([string]::IsNullOrWhiteSpace($installPath)) { throw 'Install path is required.' }
        $statusText.Text = 'Running preflight...'
        Write-GuiLog ('preflight: ' + $installPath)
        $common = Join-Path $installerRoot 'lib\Installer.Common.ps1'
        $tier = Join-Path $installerRoot 'lib\Installer.Tier.ps1'
        $preflight = Join-Path $installerRoot 'lib\Installer.Preflight.ps1'
        $command = '& { . ' + (ConvertTo-CyberButlerPowerShellLiteral $common) + '; . ' +
            (ConvertTo-CyberButlerPowerShellLiteral $tier) + '; . ' +
            (ConvertTo-CyberButlerPowerShellLiteral $preflight) + '; Get-CyberButlerPreflight -InstallPath ' +
            (ConvertTo-CyberButlerPowerShellLiteral $installPath) + ' | ConvertTo-Json -Depth 6 }'
        $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -Command $command 2>&1 | Out-String
        Write-GuiLog $output.Trim()
        $statusText.Text = 'Preflight finished. Review the output, then start installation.'
    } catch {
        Write-GuiLog ('PREFLIGHT ERROR: ' + $_.Exception.Message)
        $statusText.Text = 'Preflight failed.'
    }
})

$startButton.Add_Click({
    try {
        $installPath = [string]$installPathBox.Text
        if ([string]::IsNullOrWhiteSpace($installPath)) { throw 'Install path is required.' }
        $tierValue = Get-SelectedComboText $tierBox
        if ([string]::IsNullOrWhiteSpace($tierValue)) { $tierValue = 'Medium' }
        $bindValue = Get-SelectedComboText $bindBox
        if ([string]::IsNullOrWhiteSpace($bindValue)) { $bindValue = 'Loopback' }
        if (-not (Test-Path -LiteralPath $installerPath)) { throw ('Installer not found: ' + $installerPath) }

        $command = New-CyberButlerInteractiveInstallCommand `
            -InstallerPath $installerPath `
            -Tier $tierValue `
            -InstallPath $installPath `
            -OwnerQQ ([string]$ownerQQBox.Text) `
            -WebUIBind $bindValue `
            -PersonalPluginsPath ([string]$personalPluginsBox.Text) `
            -ApiKeyFile ([string]$apiKeyFileBox.Text)
        Write-GuiLog 'Starting elevated installer console...'
        Write-GuiLog $command
        Start-Process -FilePath 'powershell.exe' `
            -Verb RunAs `
            -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-Command', $command) | Out-Null
        $statusText.Text = 'Installer console launched. Complete the approval and TOTP prompts there.'
    } catch {
        Write-GuiLog ('START ERROR: ' + $_.Exception.Message)
        $statusText.Text = 'Could not start the installer.'
    }
})

$reportButton.Add_Click({
    $reportDir = 'C:\CyberButler\installer-report'
    if (Test-Path -LiteralPath $reportDir) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $reportDir | Out-Null
    } else {
        Write-GuiLog ('Report directory not found: ' + $reportDir)
    }
})

$closeButton.Add_Click({ $window.Close() })

$window.Add_Loaded({
    Write-GuiLog 'Cyber-Butler visual installer ready.'
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-GuiLog 'This GUI is not elevated. Start installation will request UAC.'
    } else {
        Write-GuiLog 'Administrator session detected.'
    }
})

if ($SelfTest) {
    Write-Output 'GUI_XAML_OK'
    Write-Output ('INSTALLER=' + $installerPath)
    return
}

[void]$window.ShowDialog()
