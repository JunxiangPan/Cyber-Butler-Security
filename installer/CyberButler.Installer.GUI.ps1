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
. (Join-Path $installerRoot 'lib\Installer.GuiRun.ps1')

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

        <TextBlock x:Name="QuickHelp" Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="5"
                   Text=""
                   Foreground="#94A3B8" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/>
      </Grid>
    </Border>

    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,14">
      <Button x:Name="StartButton" Content="Start installation" Width="160" Height="38" Margin="0,0,10,0"
              Background="#0EA5E9" Foreground="#FFFFFF" BorderBrush="#0EA5E9" FontWeight="SemiBold"/>
      <Button x:Name="ReportButton" Content="Open report folder" Width="140" Height="38" Margin="0,0,10,0"/>
      <Button x:Name="RemoveButton" Content="Uninstall" Width="110" Height="38" Margin="0,0,10,0"/>
      <Button x:Name="StatusButton" Content="Check status" Width="110" Height="38" Margin="0,0,10,0"/>
      <Button x:Name="CloseButton" Content="Exit" Width="80" Height="38" Margin="0,0,10,0"/>
      <Button x:Name="HelpButton" Content="Help" Width="80" Height="38" Margin="0,0,10,0"/>
      <CheckBox x:Name="ApprovalCheck" Content="I have read the notes above and approve these installer steps"
                Foreground="#FBBF24" VerticalAlignment="Center" Margin="16,0,0,0"/>
    </StackPanel>

    <ProgressBar Grid.Row="3" x:Name="InstallProgress" Height="8" Minimum="0" Maximum="100" Value="0"
                 VerticalAlignment="Center" Foreground="#0EA5E9" Background="#1E293B" Margin="0,0,0,10"/>

    <TextBox Grid.Row="4" x:Name="LogBox" IsReadOnly="True" AcceptsReturn="True"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Auto"
             FontFamily="Consolas" FontSize="12"
             Background="#020617" Foreground="#CBD5E1" BorderBrush="#1E293B"
             Padding="14" TextWrapping="NoWrap"/>

    <TextBlock Grid.Row="5" x:Name="StatusText" Text="Ready."
               Foreground="#94A3B8" FontSize="12" Margin="0,12,0,0"/>

    <StackPanel Grid.Row="6" Orientation="Horizontal" Margin="0,8,0,0">
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
$startButton = $window.FindName('StartButton')
$reportButton = $window.FindName('ReportButton')
$removeButton = $window.FindName('RemoveButton')
$statusButton = $window.FindName('StatusButton')
$closeButton = $window.FindName('CloseButton')
$helpButton = $window.FindName('HelpButton')
$quickHelp = $window.FindName('QuickHelp')
$installProgress = $window.FindName('InstallProgress')
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
        Warning='只有勾选批准后，GUI 才会提交 approval token；TOTP 在可视化对话框中确认，不再打开第二个命令窗口。'
        InstallPath='安装路径'; Tier='安全档位'; OwnerQQ='主人 QQ'; Bind='WebUI 绑定'
        PersonalPlugins='个人插件路径'; ApiKeyFile='API Key 文件（可选，sk-...）'
        ApiKeyNote='API Key 不会保存在此界面；可选文件由安装器读取，不会写入 GUI 日志。'
        QuickHelp='主人 QQ：填你自己的主 QQ（管理员/所有者账号），不是机器人 QQ。它用于 TOTP 标签、审批/通知路由和 owner allowlist；机器人 QQ 在 AstrBot/QQ 适配器里单独配置。安全档位：High/Medium/Light 的区别见 Help；系统至少 Windows 10/11 x64、管理员权限、PowerShell 5.1、Python 3.10–3.13，档位不改变这些前提。本地模型显存建议：24GB+ 用 20–24B，16GB 用 7–14B，8GB 用 3–7B，无独显可用 API-only。WebUI 绑定：Loopback 仅本机；Tailscale 私有网络；LAN 暴露局域网（High 禁止 LAN）。个人插件：不随包发布，需要你已有的 AstrBot 插件目录，包含 private_companion（陪伴核心）、livingmemory（长期记忆）、memorix（图谱+向量记忆）；安装器只复制这三个插件，不下载。API Key：本字段只写 DeepSeek 的 sk-... 密钥；其他大模型/兼容 API 需要在 AstrBot 的 provider 配置中单独添加，不能在这里直接切换。获取 DeepSeek Key：https://platform.deepseek.com/api_keys 。批准勾选：表示你已阅读说明并授权安装器执行这些步骤。'
        HelpBody="Cyber-Butler 安装选项说明`n`n主人 QQ`n填你自己的主 QQ（管理员/所有者账号），不是机器人 QQ。用于 TOTP 标签、审批/通知路由、YOUR_QQ_ID 和 owner allowlist。机器人 QQ 在 AstrBot/QQ 适配器中单独配置。`n`n安全档位`nHigh：Windows 10/11 x64 + 管理员 + 独立本地服务账户；AstrBot/WebUI 以服务身份运行；TOTP vault 对 Agent 账户有 Deny；LAN 被禁止；隔离最强。`nMedium：使用当前桌面账户，Interactive 计划任务；无法对同一账户强制 TOTP vault Deny；适合单机测试。`nLight：减少 ACL/审计/TOTP egress，仅建议低价值或临时环境。`n档位不改变硬件前提：Windows 10/11 x64、PowerShell 5.1、管理员权限、Python 3.10–3.13。本地模型显存参考：24GB+ 可跑 20–24B；16GB 可跑 7–14B；8GB 可跑 3–7B 量化；无独显或不小于 8GB 时可用 API-only；所有档位都支持 API-only。`n`nWebUI 绑定`nLoopback：只监听 127.0.0.1，最安全。`nTailscale：通过私有 tailnet 访问，需要 Tailscale。`nLAN：局域网可访问，暴露面最大；High 禁止 LAN。`n`n个人插件`n不随开源包发布。需要你已有的 AstrBot 插件目录，包含三个插件：private_companion（我会永远陪着你：角色状态、日程、关系、主动消息、陪伴核心）、livingmemory（长期记忆生命周期）、memorix（图谱+向量混合检索记忆）。安装器只复制这三个名字，不联网下载；获取渠道是你现有 AstrBot/data/plugins 或上游仓库。`n`nAPI Key`n本字段填写包含 DeepSeek API Key 的文件路径，通常 sk-...，只用于 DeepSeek provider。其他大模型或 OpenAI-compatible API 需要在 AstrBot 的 provider 配置/WebUI 中单独添加，不能靠本字段直接切换。DeepSeek Key 获取：https://platform.deepseek.com/api_keys 。`n`n批准勾选`n只有勾选后才会提交 approval token；GUI 不会静默批准安全步骤。"
        Preflight='检查环境'; Start='开始安装'; Report='打开报告目录'; Exit='退出'; Help='说明'; Remove='删除程序'; RemoveConfirm='这会停止服务并永久删除此项目的安装目录和 ProgramData 状态。确定删除？'; RemoveDone='删除完成。'; RemoveFailed='删除失败：'; CheckStatus='检查状态'; StatusTitle='安装状态'; StatusRunning='安装器正在运行。'; StatusStalled='安装器进程还在，但已经很久没有新输出，可能卡住。'; StatusWaitingTotp='正在等待 TOTP 确认。'; StatusCompleted='安装已经完成。'; StatusFailed='安装失败。'; StatusNoActive='当前没有正在运行的安装，也没有找到成功报告。'; StatusStage='当前阶段'; StatusProcess='安装器进程'; StatusLastOutput='最后输出'; StatusReport='报告状态'; StatusPorts='服务端口'; StatusStep='步骤完成度'; StatusStepEta='当前步骤预计剩余'; StatusTotalEta='总预计剩余'; StatusElapsed='已用时间'; StatusProcessDetail='进程详情'; StatusTOTP='TOTP 状态'; StatusLog='日志'; StatusNote='预计值基于当前阶段和日志活动，不是保证值。'; Copy='复制'; PostTitle='安装完成'; PostSubtitle='三个服务已安装并启动。下一步打开 WebUI，配置机器人 QQ 和模型 provider。'; PostNext='下一步：打开 WebUI -> 配置机器人 QQ 适配器 -> 添加其他模型 provider -> 发测试消息 -> 离线保存 TOTP 恢复码。'; OpenWebUI='打开 WebUI'; OpenAstrBot='打开 AstrBot'; OpenGuide='安装说明'; OpenReport='安装报告'; Close='关闭'
        Approval='我已阅读上方说明，确认执行这些安装步骤'; NeedApproval='请先勾选安装确认。'
        TotpTitle='TOTP 注册'; TotpHint='扫描二维码并离线保存恢复码，然后勾选两项确认。'; Scanned='我已扫描二维码'; Recovery='我已保存恢复码'; Confirm='确认并继续'; Cancel='取消'; TotpReady='TOTP 材料已就绪，请完成注册。'; Invalid='TOTP 确认无效。'
        Ready='就绪。'; RunningPreflight='正在检查环境...'; PreflightDone='检查完成，请确认后开始安装。'
        PreflightFailed='环境检查失败。'; Starting='正在启动安装器...'; Started='安装器已启动，进度和 TOTP 将显示在本窗口。'
        StartFailed='无法启动安装器。'; Admin='已检测到管理员会话。'; NotAdmin='当前不是管理员；开始安装会请求 UAC。'
        NoReport='报告目录不存在：'
    }
    en = @{
        Title='Cyber-Butler Setup'; Subtitle='v1.6.1 · visual installer front-end'
        Warning='The GUI supplies approval tokens only after your explicit approval. TOTP is confirmed in a dialog; no second command window is used.'
        InstallPath='Install path'; Tier='Tier'; OwnerQQ='Owner QQ'; Bind='WebUI bind'
        PersonalPlugins='Personal plugins'; ApiKeyFile='API key file (optional, sk-...)'
        ApiKeyNote='API keys are not stored in this UI. The optional file is read by the installer and never written to the GUI log.'
        QuickHelp='Owner QQ: enter your own main QQ (the owner/admin account), not the bot QQ. It feeds the TOTP label, approval/notification routing, and owner allowlist; the bot QQ is configured separately in AstrBot/QQ. Tier: see Help for High/Medium/Light; all require Windows 10/11 x64, admin, PowerShell 5.1 and Python 3.10–3.13. Local model VRAM guidance: 24GB+ for 20–24B, 16GB for 7–14B, 8GB for 3–7B, no dGPU for API-only. WebUI bind: Loopback local only; Tailscale private tailnet; LAN network exposure (High rejects LAN). Personal plugins: not bundled; provide an existing AstrBot plugin folder with private_companion (companion core), livingmemory (long-term memory), memorix (graph+vector memory); the installer copies only these, never downloads. API key: this field writes a DeepSeek sk-... key only; other models/OpenAI-compatible endpoints must be configured in AstrBot providers, not switched here. Get a DeepSeek key: https://platform.deepseek.com/api_keys . Approval checkbox: you have read the notes and authorize these steps.'
        HelpBody="Cyber-Butler installer options`n`nOwner QQ`nEnter your own main QQ (the owner/admin account), not the bot QQ. It feeds the TOTP label, approval/notification routing, YOUR_QQ_ID and the owner allowlist. The bot QQ is configured separately in AstrBot/QQ.`n`nSecurity tier`nHigh: Windows 10/11 x64 + admin + a dedicated local service account; AstrBot/WebUI run as services; TOTP vault denies the agent account; LAN is rejected; strongest isolation.`nMedium: current desktop account with Interactive scheduled tasks; a same-account TOTP vault deny cannot be enforced; suitable for single-machine testing.`nLight: reduced ACL/audit/TOTP egress; only for temporary or low-value environments.`nTier does not change the hardware baseline: Windows 10/11 x64, PowerShell 5.1, admin rights, Python 3.10–3.13. Local model VRAM guidance: 24GB+ for 20–24B, 16GB for 7–14B, 8GB for 3–7B quantized, no dGPU for API-only; every tier supports API-only.`n`nWebUI bind`nLoopback: 127.0.0.1 only, safest.`nTailscale: private tailnet access; requires Tailscale.`nLAN: reachable on the local network; largest exposure; High rejects LAN.`n`nPersonal plugins`nNot bundled. Provide an existing AstrBot plugin folder containing private_companion (the companion core: character state, schedule, relationships, proactive messages), livingmemory (long-term memory lifecycle), and memorix (graph+vector hybrid memory). The installer copies only those three and never downloads them; obtain them from your existing AstrBot/data/plugins or their upstream repositories.`n`nAPI key`nThis field takes a file path containing a DeepSeek API key (usually sk-...) and writes only the DeepSeek provider secret. Other models or OpenAI-compatible endpoints must be configured in AstrBot providers/WebUI; this field does not switch providers. Get a DeepSeek key: https://platform.deepseek.com/api_keys .`n`nApproval checkbox`nIt supplies approval tokens only after it is checked; the GUI never silently approves security steps."
        Preflight='Run preflight'; Start='Start installation'; Report='Open report folder'; Exit='Exit'; Help='Help'; Remove='Uninstall'; RemoveConfirm='This stops services and permanently deletes the project install directory and ProgramData state. Continue?'; RemoveDone='Uninstall completed.'; RemoveFailed='Uninstall failed: '; CheckStatus='Check status'; StatusTitle='Install status'; StatusRunning='The installer is running.'; StatusStalled='The installer process exists, but there has been no new output for a long time; it may be stalled.'; StatusWaitingTotp='Waiting for TOTP confirmation.'; StatusCompleted='Installation has completed.'; StatusFailed='Installation failed.'; StatusNoActive='No active installation and no successful report found.'; StatusStage='Stage'; StatusProcess='Installer process'; StatusLastOutput='Last output'; StatusReport='Report status'; StatusPorts='Service ports'; StatusStep='Step completion'; StatusStepEta='Step ETA'; StatusTotalEta='Overall ETA'; StatusElapsed='Elapsed'; StatusProcessDetail='Process details'; StatusTOTP='TOTP state'; StatusLog='Log'; StatusNote='ETAs are heuristic from the current stage and log activity, not guarantees.'; Copy='Copy'; PostTitle='Installation complete'; PostSubtitle='The three services are installed and running. Next, open the WebUI and configure the bot QQ and model provider.'; PostNext='Next: open WebUI -> configure the bot QQ adapter -> add other model providers -> send a test message -> store TOTP recovery codes offline.'; OpenWebUI='Open WebUI'; OpenAstrBot='Open AstrBot'; OpenGuide='Install guide'; OpenReport='Install report'; Close='Close'
        Approval='I have read the notes above and approve these installer steps'; NeedApproval='Please check the approval box first.'
        TotpTitle='TOTP Enrollment'; TotpHint='Scan the QR code and store the recovery codes offline, then confirm both checks.'; Scanned='I scanned the QR code'; Recovery='I saved the recovery codes'; Confirm='Confirm and continue'; Cancel='Cancel'; TotpReady='TOTP material is ready; complete enrollment.'; Invalid='Invalid TOTP confirmation.'
        Ready='Ready.'; RunningPreflight='Running preflight...'; PreflightDone='Preflight finished. Review the output, then start installation.'
        PreflightFailed='Preflight failed.'; Starting='Starting installer...'; Started='Installer started; progress and TOTP are shown in this window.'
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
    $startButton.Content = Get-UiText 'Start'
    $reportButton.Content = Get-UiText 'Report'
    $closeButton.Content = Get-UiText 'Exit'
    $helpButton.Content = Get-UiText 'Help'
    $removeButton.Content = Get-UiText 'Remove'
    $statusButton.Content = Get-UiText 'CheckStatus'
    $approvalCheck.Content = Get-UiText 'Approval'
    $quickHelp.Text = Get-UiText 'QuickHelp'
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


function Set-GuiBusy([bool]$Busy) {
    foreach ($control in @(
        $startButton, $reportButton, $removeButton, $helpButton,
        $languageBox, $installPathBox, $tierBox, $ownerQQBox, $bindBox,
        $personalPluginsBox, $apiKeyFileBox, $approvalCheck
    )) {
        if ($null -ne $control) { $control.IsEnabled = -not $Busy }
    }
    $closeButton.IsEnabled = $true
    $statusButton.IsEnabled = $true
}


function Get-GuiStageText([int]$Percent) {
    if ($Percent -ge 100) { return 'complete' }
    if ($Percent -ge 80) { return 'services / firewall' }
    if ($Percent -ge 65) { return 'TOTP / security' }
    if ($Percent -ge 55) { return 'ACL / broker ACL' }
    if ($Percent -ge 45) { return 'core completed / overlay' }
    if ($Percent -ge 35) { return 'core: pip install' }
    if ($Percent -ge 15) { return 'core: download / extract' }
    return 'starting'
}

function Format-GuiDuration([int]$Seconds) {
    if ($Seconds -lt 0) { return 'unknown' }
    if ($Seconds -lt 60) { return ($Seconds.ToString() + 's') }
    $m = [int]($Seconds / 60)
    $s = [int]($Seconds % 60)
    if ($m -lt 60) { return ('{0}m {1}s' -f $m, $s) }
    return ('{0}h {1}m' -f [int]($m / 60), ($m % 60))
}

function Show-GuiInstallStatus {
    $reportPath = 'C:\CyberButler\installer-report\install-report.json'
    $reportStatus = ''
    $reportFailure = ''
    if (Test-Path -LiteralPath $reportPath) {
        try {
            $raw = Get-Content -LiteralPath $reportPath -Raw
            $m = [regex]::Match($raw, '"status"\s*:\s*"([^"]+)"')
            if ($m.Success) { $reportStatus = $m.Groups[1].Value }
            $f = [regex]::Match($raw, '"failure"\s*:\s*\{[^\}]*?"message"\s*:\s*"([^"]+)"', [Text.RegularExpressions.RegexOptions]::Singleline)
            if ($f.Success) { $reportFailure = $f.Groups[1].Value.Replace('\n', "`n") }
        } catch { }
    }

    $running = $false
    $processText = 'not running'
    $processDetail = 'n/a'
    $elapsedSec = 0
    if ($script:cbGuiProcess) {
        try {
            $running = -not $script:cbGuiProcess.HasExited
            $processText = ('PID {0}, {1}' -f $script:cbGuiProcess.Id, $(if ($running) { 'running' } else { 'exited' }))
            $proc = Get-Process -Id $script:cbGuiProcess.Id -ErrorAction SilentlyContinue
            if ($proc) {
                $elapsedSec = [int]((Get-Date) - $proc.StartTime).TotalSeconds
                $processDetail = ('CPU {0:N1}s, WS {1:N0} MB, started {2:yyyy-MM-dd HH:mm:ss}' -f $proc.CPU, ($proc.WorkingSet64 / 1MB), $proc.StartTime)
            }
        } catch { }
    }

    $lastText = 'no log'
    $ageSeconds = $null
    $tail = @()
    if ($script:cbGuiLogPath -and (Test-Path -LiteralPath $script:cbGuiLogPath)) {
        try {
            $last = Get-Item -LiteralPath $script:cbGuiLogPath
            $lastText = $last.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            $ageSeconds = [int]((Get-Date) - $last.LastWriteTime).TotalSeconds
            $tail = @(Get-Content -LiteralPath $script:cbGuiLogPath -Tail 12 -ErrorAction SilentlyContinue)
        } catch { }
    }
    $logText = ($tail -join "`n")

    $totpReady = $false
    $totpConfirmed = $false
    if ($script:cbGuiSignalDir) {
        $totpReady = Test-Path -LiteralPath (Join-Path $script:cbGuiSignalDir 'totp-ready.json')
        $totpConfirmed = Test-Path -LiteralPath (Join-Path $script:cbGuiSignalDir 'totp-confirm.json')
    }

    $percent = [int]$installProgress.Value
    $stage = Get-GuiStageText $percent
    $stageStart = 0; $stageEnd = 10; $stageNominal = 60
    if ($percent -ge 10 -and $percent -lt 25) { $stageStart = 10; $stageEnd = 25; $stageNominal = 120 }
    elseif ($percent -ge 25 -and $percent -lt 45) { $stageStart = 25; $stageEnd = 45; $stageNominal = 300 }
    elseif ($percent -ge 45 -and $percent -lt 55) { $stageStart = 45; $stageEnd = 55; $stageNominal = 60 }
    elseif ($percent -ge 55 -and $percent -lt 65) { $stageStart = 55; $stageEnd = 65; $stageNominal = 30 }
    elseif ($percent -ge 65 -and $percent -lt 75) { $stageStart = 65; $stageEnd = 75; $stageNominal = 180 }
    elseif ($percent -ge 75 -and $percent -lt 95) { $stageStart = 75; $stageEnd = 95; $stageNominal = 120 }
    elseif ($percent -ge 95) { $stageStart = 95; $stageEnd = 100; $stageNominal = 30 }
    $stepPercent = 100
    if ($stageEnd -gt $stageStart) {
        $stepPercent = [int]((($percent - $stageStart) / ($stageEnd - $stageStart)) * 100)
        $stepPercent = [Math]::Max(0, [Math]::Min(100, $stepPercent))
    }
    if ($stage -match 'pip') {
        if ($logText -match 'Successfully installed') { $stepPercent = 100 }
        elseif ($logText -match 'Installing collected packages') { $stepPercent = [Math]::Max($stepPercent, 70) }
        elseif ($elapsedSec -gt 0) { $stepPercent = [Math]::Max($stepPercent, [Math]::Min(95, [int](($elapsedSec / $stageNominal) * 100))) }
    }
    if ($totpReady -and -not $totpConfirmed) {
        $percent = [Math]::Max($percent, 65)
        $stage = 'TOTP: waiting for confirmation'
        $stageStart = 65; $stageEnd = 75; $stageNominal = 0; $stepPercent = 100
    }
    $stepRemaining = if ($stageNominal -gt 0) { [int]($stageNominal * (1 - ($stepPercent / 100))) } else { 0 }
    $totalNominal = if ($percent -lt 25) { 600 } elseif ($percent -lt 45) { 480 } elseif ($percent -lt 55) { 240 } elseif ($percent -lt 65) { 180 } elseif ($percent -lt 75) { 120 } elseif ($percent -lt 95) { 90 } else { 30 }
    $totalRemaining = [int](($totalNominal * (1 - ($percent / 100))) + $stepRemaining)
    if ($totpReady -and -not $totpConfirmed) { $totalRemaining = $null }

    $ports = @()
    $tasks = @()
    if ($percent -ge 80 -or $reportStatus -eq 'success') {
        $ports = @(Get-NetTCPConnection -State Listen -LocalPort 6185,18090,8765 -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty LocalPort -Unique | Sort-Object)
        $tasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -match 'AstrBot Service|AstrBot TOTP Broker|Cyber-Butler Web UI' } |
            Select-Object TaskName,State)
    }

    $lines = New-Object System.Collections.Generic.List[string]
    $headline = Get-UiText 'StatusRunning'
    if ($reportStatus -eq 'success') { $headline = Get-UiText 'StatusCompleted' }
    elseif ($reportStatus -eq 'failed' -or ($script:cbGuiProcess -and $script:cbGuiProcess.HasExited)) { $headline = Get-UiText 'StatusFailed' }
    elseif ($totpReady -and -not $totpConfirmed) { $headline = Get-UiText 'StatusWaitingTotp' }
    elseif ($running -and $ageSeconds -ne $null -and $ageSeconds -gt 300) { $headline = Get-UiText 'StatusStalled' }
    elseif (-not $running -and -not $reportStatus) { $headline = Get-UiText 'StatusNoActive' }

    $lines.Add('STATUS: ' + $headline)
    $lines.Add((Get-UiText 'StatusStage') + ': ' + $percent + '% · ' + $stage)
    $lines.Add((Get-UiText 'StatusStep') + ': ' + $stepPercent + '%')
    $lines.Add((Get-UiText 'StatusStepEta') + ': ' + $(if ($stageNominal -gt 0) { Format-GuiDuration $stepRemaining } else { 'waiting for user' }))
    $lines.Add((Get-UiText 'StatusTotalEta') + ': ' + $(if ($null -eq $totalRemaining) { 'waiting for TOTP confirmation' } else { Format-GuiDuration $totalRemaining }))
    $lines.Add((Get-UiText 'StatusElapsed') + ': ' + (Format-GuiDuration $elapsedSec))
    $lines.Add((Get-UiText 'StatusProcess') + ': ' + $processText)
    $lines.Add((Get-UiText 'StatusProcessDetail') + ': ' + $processDetail)
    $lines.Add((Get-UiText 'StatusLastOutput') + ': ' + $lastText + $(if ($null -ne $ageSeconds) { ' (' + $ageSeconds + 's ago)' } else { '' }))
    $lines.Add((Get-UiText 'StatusTOTP') + ': ' + $(if ($totpConfirmed) { 'confirmed' } elseif ($totpReady) { 'ready, waiting for confirmation' } else { 'not reached' }))
    if ($reportStatus) { $lines.Add((Get-UiText 'StatusReport') + ': ' + $reportStatus) }
    if ($reportFailure) { $lines.Add('Failure: ' + $reportFailure) }
    if ($ports.Count -gt 0) { $lines.Add((Get-UiText 'StatusPorts') + ': ' + ($ports -join ', ')) }
    foreach ($task in $tasks) { $lines.Add('Task: ' + $task.TaskName + ' = ' + $task.State) }
    if ($script:LastProgressMessage) { $lines.Add('Last message: ' + $script:LastProgressMessage) }
    $lines.Add('Signal dir: ' + $script:cbGuiSignalDir)
    $lines.Add('Output log: ' + $script:cbGuiLogPath)
    $lines.Add('Report: ' + $reportPath)
    $lines.Add('')
    $lines.Add('--- last 12 log lines ---')
    foreach ($line in $tail) { $lines.Add([string]$line) }
    $lines.Add('')
    $lines.Add((Get-UiText 'StatusNote'))
    Show-CyberButlerStatusWindow -Owner $window -Title (Get-UiText 'StatusTitle') -Text ($lines -join "`n") -Copy (Get-UiText 'Copy') -Close (Get-UiText 'Close')
}

function Remove-CyberButlerGuiInstall([string]$Root) {
    $full = [IO.Path]::GetFullPath($Root).TrimEnd([char]92)
    $rootOfDrive = [IO.Path]::GetPathRoot($full).TrimEnd([char]92)
    if ([string]::IsNullOrWhiteSpace($full) -or $full -eq $rootOfDrive -or $full.Length -lt 4) {
        throw ('Refusing to remove unsafe root: ' + $full)
    }
    $sysRoot = [IO.Path]::GetFullPath($env:SystemRoot).TrimEnd([char]92)
    $progFiles = [IO.Path]::GetFullPath($env:ProgramFiles).TrimEnd([char]92)
    $sep = [IO.Path]::DirectorySeparatorChar
    if (($full -eq $sysRoot) -or $full.StartsWith($sysRoot + $sep, [StringComparison]::OrdinalIgnoreCase)) {
        throw ('Refusing to remove system directory: ' + $full)
    }
    if (($full -eq $progFiles) -or $full.StartsWith($progFiles + $sep, [StringComparison]::OrdinalIgnoreCase)) {
        throw ('Refusing to remove Program Files directory: ' + $full)
    }
    foreach ($marker in @('VERSION', 'AstrBot', 'webui', 'tools')) {
        if (-not (Test-Path -LiteralPath (Join-Path $full $marker))) {
            throw ('Refusing to remove non-Cyber-Butler directory: missing ' + $marker)
        }
    }
    foreach ($taskName in @('AstrBot Service', 'AstrBot TOTP Broker', 'Cyber-Butler Web UI Services')) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    Remove-NetFirewallRule -DisplayName 'Cyber-Butler Web UI 8765' -ErrorAction SilentlyContinue
    foreach ($port in @(6185, 18090, 8765)) {
        foreach ($conn in @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) {
            $proc = Get-Process -Id $conn.OwningProcess -ErrorAction SilentlyContinue
            if ($proc -and $proc.Path -and $proc.Path.StartsWith($full, [StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        }
    }
    Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -and $_.CommandLine -like ('*' + $full + '*') } |
        ForEach-Object {
            $proc = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
            if ($proc -and $proc.Path -and $proc.Path.StartsWith($full, [StringComparison]::OrdinalIgnoreCase)) {
                Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            }
        }
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
    }
    $programData = Join-Path $env:ProgramData 'CyberButler'
    if (Test-Path -LiteralPath $programData) {
        Remove-Item -LiteralPath $programData -Recurse -Force -ErrorAction SilentlyContinue
    }
    return $full
}

function Get-SelectedComboText($combo) {
    if ($null -eq $combo.SelectedItem) { return '' }
    if ($combo.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) { return [string]$combo.SelectedItem.Content }
    return [string]$combo.SelectedItem
}

function Invoke-GuiPreflight {
    try {
        $installPath = [string]$installPathBox.Text
        if ([string]::IsNullOrWhiteSpace($installPath)) { throw 'Install path is required.' }
        $statusText.Text = Get-UiText 'RunningPreflight'
        Write-GuiLog ('preflight: ' + $installPath)
        . (Join-Path $installerRoot 'lib\Installer.Common.ps1')
        . (Join-Path $installerRoot 'lib\Installer.Tier.ps1')
        . (Join-Path $installerRoot 'lib\Installer.Preflight.ps1')
        $result = Get-CyberButlerPreflight -InstallPath $installPath
        $json = $result | ConvertTo-Json -Depth 6
        Write-GuiLog $json
        $statusText.Text = Get-UiText 'PreflightDone'
    } catch {
        Write-GuiLog ('PREFLIGHT ERROR: ' + $_.Exception.Message)
        $statusText.Text = Get-UiText 'PreflightFailed'
    }
}

$startButton.Add_Click({
    try {
        if (-not $approvalCheck.IsChecked) {
            [System.Windows.MessageBox]::Show((Get-UiText 'NeedApproval'), (Get-UiText 'Title')) | Out-Null
            return
        }
        if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            [System.Windows.MessageBox]::Show((Get-UiText 'NotAdmin'), (Get-UiText 'Title')) | Out-Null
            return
        }
        $installPath = [string]$installPathBox.Text
        if ([string]::IsNullOrWhiteSpace($installPath)) { throw 'Install path is required.' }
        $tierValue = Get-SelectedComboText $tierBox
        if ([string]::IsNullOrWhiteSpace($tierValue)) { $tierValue = 'Medium' }
        $bindValue = Get-SelectedComboText $bindBox
        if ([string]::IsNullOrWhiteSpace($bindValue)) { $bindValue = 'Loopback' }
        $text = @{
            Started = Get-UiText 'Started'; TotpTitle = Get-UiText 'TotpTitle'
            TotpHint = Get-UiText 'TotpHint'; Scanned = Get-UiText 'Scanned'
            Recovery = Get-UiText 'Recovery'; Confirm = Get-UiText 'Confirm'
            Cancel = Get-UiText 'Cancel'; TotpReady = Get-UiText 'TotpReady'
        }
        Set-GuiBusy $true
        Write-GuiLog (Get-UiText 'Starting')
        $installProgress.Value = 2
        Start-CyberButlerGuiInstall `
            -Window $window -InstallerPath $installerPath -InstallPath $installPath `
            -Tier $tierValue -OwnerQQ ([string]$ownerQQBox.Text) -WebUIBind $bindValue `
            -PersonalPluginsPath ([string]$personalPluginsBox.Text) `
            -ApiKeyFile ([string]$apiKeyFileBox.Text) `
            -OnLog { param($line) Write-GuiLog $line } `
            -OnStatus {
                param($line)
                $statusText.Text = $line
                if ($line -match 'finished') {
                    Set-GuiBusy $false
                    $installProgress.Value = 100
                    $postText = @{
                        PostTitle = Get-UiText 'PostTitle'
                        PostSubtitle = Get-UiText 'PostSubtitle'
                        PostNext = Get-UiText 'PostNext'
                        OpenWebUI = Get-UiText 'OpenWebUI'
                        OpenAstrBot = Get-UiText 'OpenAstrBot'
                        OpenGuide = Get-UiText 'OpenGuide'
                        OpenReport = Get-UiText 'OpenReport'
                        Close = Get-UiText 'Close'
                    }
                    $guidePath = Join-Path (Split-Path -Parent $installerRoot) 'README-INSTALL.md'
                    try {
                        Show-CyberButlerPostInstallWindow -Owner $window -InstallPath $installPath `
                            -ReportPath 'C:\CyberButler\installer-report\install-report.json' `
                            -GuidePath $guidePath -Text $postText
                    } catch {
                        [System.Windows.MessageBox]::Show(
                            ("Installation completed.`n`nReport: C:\CyberButler\installer-report\install-report.json"),
                            (Get-UiText 'Title')) | Out-Null
                    }
                } elseif ($line -match 'failed') {
                    [System.Windows.MessageBox]::Show(
                        ("Installation failed.`n`nReport: C:\CyberButler\installer-report\install-report.json"),
                        (Get-UiText 'Title')) | Out-Null
                }
            } `
            -OnProgress {
                param($percent, $message)
                if ([int]$percent -gt $installProgress.Value) { $installProgress.Value = [int]$percent }
                if ($message -and $message -ne $script:LastProgressMessage) {
                    $script:LastProgressMessage = $message
                    Write-GuiLog ('progress ' + [int]$percent + '% · ' + $message)
                }
            } `
            -Text $text | Out-Null
    } catch {
        Set-GuiBusy $false
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

$helpButton.Add_Click({
    [System.Windows.MessageBox]::Show((Get-UiText 'HelpBody'), (Get-UiText 'Help')) | Out-Null
})

$statusButton.Add_Click({ Show-GuiInstallStatus })

$removeButton.Add_Click({
    if ($script:cbGuiProcess -and -not $script:cbGuiProcess.HasExited) {
        [System.Windows.MessageBox]::Show('Installation is running. Wait or use Exit to stop it first.', (Get-UiText 'Remove')) | Out-Null
        return
    }
    $answer = [System.Windows.MessageBox]::Show((Get-UiText 'RemoveConfirm'), (Get-UiText 'Remove'), 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }
    try {
        $removed = Remove-CyberButlerGuiInstall ([string]$installPathBox.Text)
        [System.Windows.MessageBox]::Show(((Get-UiText 'RemoveDone') + "`n`n" + $removed), (Get-UiText 'Remove')) | Out-Null
    } catch {
        [System.Windows.MessageBox]::Show(((Get-UiText 'RemoveFailed') + $_.Exception.Message), (Get-UiText 'Remove')) | Out-Null
    }
})

$closeButton.Add_Click({
    if ($script:cbGuiProcess -and -not $script:cbGuiProcess.HasExited) {
        $answer = [System.Windows.MessageBox]::Show(
            'Installation is running. Exit will stop the hidden installer and may leave a partial install. Continue?',
            (Get-UiText 'Exit'), 'YesNo', 'Warning')
        if ($answer -ne 'Yes') { return }
        try { Stop-Process -Id $script:cbGuiProcess.Id -Force -ErrorAction SilentlyContinue } catch { }
    }
    $window.Close()
})

$window.Add_Loaded({
    Apply-GuiLanguage
    Write-GuiLog 'Cyber-Butler visual installer ready.'
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-GuiLog (Get-UiText 'NotAdmin')
    } else {
        Write-GuiLog (Get-UiText 'Admin')
    }
    Invoke-GuiPreflight
})

if ($SelfTest) {
    Write-Output 'GUI_XAML_OK'
    Write-Output ('INSTALLER=' + $installerPath)
    return
}

[void]$window.ShowDialog()
