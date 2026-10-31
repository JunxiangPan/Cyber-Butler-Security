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
      <TextBlock x:Name="HeaderTitle" Text="Cyber-Butler Setup" Foreground="#F8FAFC" FontSize="30" FontWeight="SemiBold"/>
      <TextBlock x:Name="HeaderSubtitle" Text="v1.6.1 · visual installer front-end"
                 Foreground="#94A3B8" FontSize="13" Margin="0,7,0,0"/>
      <TextBlock x:Name="HeaderWarning" Text="The console handoff keeps approval tokens and TOTP enrollment explicit. Complete those prompts in the elevated window."
                 Foreground="#FBBF24" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"/>
      <ComboBox x:Name="LanguageBox" SelectedIndex="0" Width="130" HorizontalAlignment="Right" Margin="0,10,0,0">
        <ComboBoxItem Content="中文"/>
        <ComboBoxItem Content="English"/>
      </ComboBox>
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

        <TextBlock x:Name="InstallPathLabel" Grid.Row="0" Grid.Column="0" Text="Install path" Foreground="#CBD5E1" VerticalAlignment="Center"/>
        <TextBox Grid.Row="0" Grid.Column="1" x:Name="InstallPathBox" Text="C:\CyberButler"
                 Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

        <TextBlock x:Name="TierLabel" Grid.Row="0" Grid.Column="3" Text="Tier" Foreground="#CBD5E1" VerticalAlignment="Center"/>
        <ComboBox Grid.Row="0" Grid.Column="4" x:Name="TierBox" SelectedIndex="1"
                  Background="#0B1220" Foreground="#111827" Padding="6">
          <ComboBoxItem Content="High"/>
          <ComboBoxItem Content="Medium"/>
          <ComboBoxItem Content="Light"/>
        </ComboBox>

        <TextBlock x:Name="OwnerQQLabel" Grid.Row="1" Grid.Column="0" Text="Owner QQ" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
        <TextBox Grid.Row="1" Grid.Column="1" x:Name="OwnerQQBox" Margin="0,12,0,0"
                 Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

        <TextBlock x:Name="BindLabel" Grid.Row="1" Grid.Column="3" Text="WebUI bind" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
        <ComboBox Grid.Row="1" Grid.Column="4" x:Name="BindBox" SelectedIndex="0" Margin="0,12,0,0"
                  Background="#0B1220" Foreground="#111827" Padding="6">
          <ComboBoxItem Content="Loopback"/>
          <ComboBoxItem Content="Tailscale"/>
          <ComboBoxItem Content="LAN"/>
        </ComboBox>

        <TextBlock x:Name="PersonalPluginsLabel" Grid.Row="2" Grid.Column="0" Text="Personal plugins" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
        <TextBox Grid.Row="2" Grid.Column="1" x:Name="PersonalPluginsBox" Margin="0,12,0,0"
                 Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

        <TextBlock x:Name="ApiKeyFileLabel" Grid.Row="2" Grid.Column="3" Text="API key file (optional)" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
        <TextBox Grid.Row="2" Grid.Column="4" x:Name="ApiKeyFileBox" Margin="0,12,0,0"
                 Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

        <TextBlock x:Name="ApiKeyNote" Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="5"
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
      <CheckBox x:Name="ApprovalCheck" Content="I approve the planned installer steps"
                Foreground="#FBBF24" VerticalAlignment="Center" Margin="16,0,0,0"/>
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
$approvalCheck = $window.FindName('ApprovalCheck')
$logBox = $window.FindName('LogBox')
$statusText = $window.FindName('StatusText')
$installerPathText = $window.FindName('InstallerPathText')
$installerPathText.Text = $installerPath
$languageBox = $window.FindName('LanguageBox')
$headerTitle = $window.FindName('HeaderTitle')
$headerSubtitle = $window.FindName('HeaderSubtitle')
$headerWarning = $window.FindName('HeaderWarning')
$installPathLabel = $window.FindName('InstallPathLabel')
$tierLabel = $window.FindName('TierLabel')
$ownerQQLabel = $window.FindName('OwnerQQLabel')
$bindLabel = $window.FindName('BindLabel')
$personalPluginsLabel = $window.FindName('PersonalPluginsLabel')
$apiKeyFileLabel = $window.FindName('ApiKeyFileLabel')
$apiKeyNote = $window.FindName('ApiKeyNote')

$script:UiText = @{
    zh = @{
        Title='Cyber-Butler 安装程序'; Subtitle='v1.6.1 · 可视化安装前端'
        Warning='安全批准 token 和 TOTP 注册仍在提权控制台中完成，安装器不会静默跳过这些确认。'
        InstallPath='安装路径'; Tier='安全档位'; OwnerQQ='主人 QQ'; Bind='WebUI 绑定'
        PersonalPlugins='个人插件路径'; ApiKeyFile='API Key 文件（可选）'
        ApiKeyNote='API Key 不会保存在此界面；可选文件由安装器读取，不会写入 GUI 日志。'
        Preflight='检查环境'; Start='开始安装'; Report='打开报告目录'; Exit='退出'; Approval='我确认执行上述安装步骤'; NeedApproval='请先勾选安装确认。'; TotpTitle='TOTP 注册'; TotpHint='扫描二维码并离线保存恢复码，然后勾选两项确认。'; Scanned='我已扫描二维码'; Recovery='我已保存恢复码'; Confirm='确认并继续'; Cancel='取消'; TotpReady='TOTP 材料已就绪，请完成注册。'; Invalid='TOTP 确认无效。'
        Ready='就绪。'; RunningPreflight='正在检查环境...'; PreflightDone='检查完成，请确认后开始安装。'
        PreflightFailed='环境检查失败。'; Starting='正在启动提权安装器...'; Started='安装器已启动，请在提权控制台完成批准和 TOTP。'
        StartFailed='无法启动安装器。'; Admin='已检测到管理员会话。'; NotAdmin='当前不是管理员；开始安装会请求 UAC。'
        NoReport='报告目录不存在：'
    }
    en = @{
        Title='Cyber-Butler Setup'; Subtitle='v1.6.1 · visual installer front-end'
        Warning='Approval tokens and TOTP enrollment remain in the elevated console; the GUI never auto-approves security steps.'
        InstallPath='Install path'; Tier='Tier'; OwnerQQ='Owner QQ'; Bind='WebUI bind'
        PersonalPlugins='Personal plugins'; ApiKeyFile='API key file (optional)'
        ApiKeyNote='API keys are not stored in this UI. The optional file is read by the installer and never written to the GUI log.'
        Preflight='Run preflight'; Start='Start installation'; Report='Open report folder'; Exit='Exit'; Approval='I approve the planned installer steps'; NeedApproval='Please check the approval box first.'; TotpTitle='TOTP Enrollment'; TotpHint='Scan the QR code and store the recovery codes offline, then confirm both checks.'; Scanned='I scanned the QR code'; Recovery='I saved the recovery codes'; Confirm='Confirm and continue'; Cancel='Cancel'; TotpReady='TOTP material is ready; complete enrollment.'; Invalid='Invalid TOTP confirmation.'
        Ready='Ready.'; RunningPreflight='Running preflight...'; PreflightDone='Preflight finished. Review the output, then start installation.'
        PreflightFailed='Preflight failed.'; Starting='Starting elevated installer...'; Started='Installer launched. Complete approval and TOTP prompts in the elevated console.'
        StartFailed='Could not start the installer.'; Admin='Administrator session detected.'; NotAdmin='This GUI is not elevated. Start installation will request UAC.'
        NoReport='Report directory not found: '
    }
}

function Get-UiText([string]$key) {
    $lang = if ($languageBox.SelectedIndex -eq 1) { 'en' } else { 'zh' }
    return [string]$script:UiText[$lang][$key]
}

function Apply-GuiLanguage {
    $window.Title = Get-UiText 'Title'
    $headerTitle.Text = Get-UiText 'Title'
    $headerSubtitle.Text = Get-UiText 'Subtitle'
    $headerWarning.Text = Get-UiText 'Warning'
    $installPathLabel.Text = Get-UiText 'InstallPath'
    $tierLabel.Text = Get-UiText 'Tier'
    $ownerQQLabel.Text = Get-UiText 'OwnerQQ'
    $bindLabel.Text = Get-UiText 'Bind'
    $personalPluginsLabel.Text = Get-UiText 'PersonalPlugins'
    $apiKeyFileLabel.Text = Get-UiText 'ApiKeyFile'
    $apiKeyNote.Text = Get-UiText 'ApiKeyNote'
    $preflightButton.Content = Get-UiText 'Preflight'
    $startButton.Content = Get-UiText 'Start'
    $reportButton.Content = Get-UiText 'Report'
    $closeButton.Content = Get-UiText 'Exit'
    $approvalCheck.Content = Get-UiText 'Approval'
    if ($statusText.Text -eq '' -or $statusText.Text -eq 'Ready.' -or $statusText.Text -eq '就绪。') {
        $statusText.Text = Get-UiText 'Ready'
    }
}

$languageBox.Add_SelectionChanged({ Apply-GuiLanguage })

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
        $statusText.Text = Get-UiText 'RunningPreflight'
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
        $statusText.Text = Get-UiText 'PreflightDone'
    } catch {
        Write-GuiLog ('PREFLIGHT ERROR: ' + $_.Exception.Message)
        $statusText.Text = Get-UiText 'PreflightFailed'
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
        $statusText.Text = Get-UiText 'Started'
    } catch {
        Write-GuiLog ('START ERROR: ' + $_.Exception.Message)
        $statusText.Text = Get-UiText 'StartFailed'
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
    Apply-GuiLanguage
    Write-GuiLog 'Cyber-Butler visual installer ready.'
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-GuiLog (Get-UiText 'NotAdmin')
    } else {
        Write-GuiLog (Get-UiText 'Admin')
    }
})

if ($SelfTest) {
    Write-Output 'GUI_XAML_OK'
    Write-Output ('INSTALLER=' + $installerPath)
    return
}

[void]$window.ShowDialog()
