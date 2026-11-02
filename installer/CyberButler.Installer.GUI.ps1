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
        FontFamily="Segoe UI">
  <Window.Background>
    <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
      <GradientStop Color="#0B1220" Offset="0"/>
      <GradientStop Color="#101B2E" Offset="1"/>
    </LinearGradientBrush>
  </Window.Background>
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#1E293B"/>
      <Setter Property="Foreground" Value="#E2E8F0"/>
      <Setter Property="BorderBrush" Value="#334155"/>
      <Setter Property="Padding" Value="10,4"/>
    </Style>
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="#0B1220"/>
      <Setter Property="Foreground" Value="#F8FAFC"/>
      <Setter Property="BorderBrush" Value="#334155"/>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Background" Value="#0B1220"/>
      <Setter Property="Foreground" Value="#111827"/>
    </Style>
  </Window.Resources>
  <ScrollViewer x:Name="MainScroll" VerticalScrollBarVisibility="Auto"
                HorizontalScrollBarVisibility="Disabled" PanningMode="VerticalOnly">
  <Grid Margin="30">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="240"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Margin="0,0,0,22">
      <Border Height="4" CornerRadius="2" Background="#0EA5E9" Margin="0,0,0,14"/>
      <TextBlock x:Name="HeaderTitle" Text="Cyber-Butler Setup" Foreground="#F8FAFC" FontSize="32" FontWeight="SemiBold"/>
      <TextBlock x:Name="HeaderSubtitle" Text="v1.6.1 · visual installer front-end"
                 Foreground="#94A3B8" FontSize="13" Margin="0,7,0,0"/>
      <TextBlock x:Name="HeaderWarning" Text="The console handoff keeps approval tokens and TOTP enrollment explicit. Complete those prompts in the elevated window."
                 Foreground="#FBBF24" FontSize="12" TextWrapping="Wrap" Margin="0,12,0,0"/>
      <ComboBox x:Name="LanguageBox" SelectedIndex="0" Width="130" HorizontalAlignment="Right" Margin="0,10,0,0">
        <ComboBoxItem Content="中文"/>
        <ComboBoxItem Content="English"/>
        <ComboBoxItem Content="Deutsch"/>
        <ComboBoxItem Content="Español"/>
        <ComboBoxItem Content="Français"/>
        <ComboBoxItem Content="日本語"/>
        <ComboBoxItem Content="한국어"/>
        <ComboBoxItem Content="Русский"/>
      </ComboBox>
    </StackPanel>

    <Border Grid.Row="1" Background="#0F1B2E" BorderBrush="#1E3A5F" BorderThickness="1"
            CornerRadius="12" Padding="20" Margin="0,0,0,16">
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
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <TextBlock x:Name="InstallPathLabel" Grid.Row="0" Grid.Column="0" Text="Install path" Foreground="#CBD5E1" VerticalAlignment="Center"/>
          <TextBox Grid.Row="0" Grid.Column="1" x:Name="InstallPathBox" Text="C:\CyberButler"
                   Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

          <TextBlock x:Name="TierLabel" Grid.Row="0" Grid.Column="3" Text="Tier" Foreground="#CBD5E1" VerticalAlignment="Center"/>
          <ComboBox Grid.Row="0" Grid.Column="4" x:Name="TierBox" SelectedIndex="1"
                    Background="#0B1220" Foreground="#111827" Padding="6">
            <ComboBoxItem Content="High" Tag="High"/>
            <ComboBoxItem Content="Medium" Tag="Medium"/>
            <ComboBoxItem Content="Light" Tag="Light"/>
          </ComboBox>

          <TextBlock x:Name="OwnerQQLabel" Grid.Row="1" Grid.Column="0" Text="Owner QQ" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
          <TextBox Grid.Row="1" Grid.Column="1" x:Name="OwnerQQBox" Margin="0,12,0,0"
                   Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>

          <TextBlock x:Name="BindLabel" Grid.Row="1" Grid.Column="3" Text="WebUI bind" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,12,0,0"/>
          <ComboBox Grid.Row="1" Grid.Column="4" x:Name="BindBox" SelectedIndex="0" Margin="0,12,0,0"
                    Background="#0B1220" Foreground="#111827" Padding="6">
            <ComboBoxItem Content="Loopback" Tag="Loopback"/>
            <ComboBoxItem Content="Tailscale" Tag="Tailscale"/>
            <ComboBoxItem Content="LAN" Tag="LAN"/>
          </ComboBox>

          <Border Grid.Row="2" Grid.Column="0" Grid.ColumnSpan="5"
                  Background="#0B182B" BorderBrush="#1D4ED8" BorderThickness="1"
                  CornerRadius="8" Padding="14" Margin="0,16,0,4">
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
              <TextBlock Grid.Row="0" Grid.Column="0" Grid.ColumnSpan="5"
                         Text="WebUI 邮箱与邮件审批（必填） / WebUI email and email approval (required)"
                         Foreground="#93C5FD" FontSize="13" FontWeight="SemiBold" TextWrapping="Wrap"/>

              <TextBlock x:Name="WebUIEmailLabel" Grid.Row="1" Grid.Column="0"
                         Text="WebUI email / 管理员邮箱" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,10,0,0"/>
              <TextBox x:Name="WebUIEmailBox" Grid.Row="1" Grid.Column="1"
                       Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8" Margin="0,10,0,0"
                       ToolTip="管理员登录 CBS WebUI、接收 TOTP 审批/告警的邮箱，不是机器人 QQ。 / Administrator login + TOTP/alert recipient, not the bot QQ."/>
              <TextBlock x:Name="SmtpAuthLabel" Grid.Row="1" Grid.Column="3"
                         Text="SMTP auth code / 授权码" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,10,0,0"/>
              <PasswordBox x:Name="SmtpAuthBox" Grid.Row="1" Grid.Column="4"
                           Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8" Margin="0,10,0,0"
                           ToolTip="邮箱服务商生成的应用授权码/短信授权码，不是邮箱登录密码。DPAPI 加密保存。 / Provider app password, not the mailbox login password. Stored with DPAPI."/>

              <TextBlock x:Name="SmtpHostLabel" Grid.Row="2" Grid.Column="0"
                         Text="SMTP host / 服务器" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,10,0,0"/>
              <TextBox x:Name="SmtpHostBox" Grid.Row="2" Grid.Column="1" Text="smtp.163.com"
                       Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8" Margin="0,10,0,0"
                       ToolTip="发信服务器，例如 smtp.163.com 或 smtp.gmail.com。 / Outgoing mail server, e.g. smtp.163.com or smtp.gmail.com."/>
              <TextBlock x:Name="SmtpPortLabel" Grid.Row="2" Grid.Column="3"
                         Text="SMTP port / 端口" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="0,10,0,0"/>
              <TextBox x:Name="SmtpPortBox" Grid.Row="2" Grid.Column="4" Text="465"
                       Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8" Margin="0,10,0,0"
                       ToolTip="当前邮件组件使用隐式 SSL，填 465；587/STARTTLS 暂不支持。 / This build uses implicit SSL on 465; 587/STARTTLS is not supported."/>

              <TextBlock x:Name="EmailHelp" Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="5"
                         Text="管理员邮箱用于 CBS WebUI 登录和 TOTP/告警；SMTP 是发信服务器，授权码不是邮箱登录密码。缺失时 WebUI 显示红色 Banner，Broker 返回 503。点击“说明/Help”查看 163/Gmail 的获取方法。"
                         Foreground="#93C5FD" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/>
              <TextBlock x:Name="EmailHelpEn" Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="5"
                         Text="WebUI email is for CBS WebUI login and TOTP/alerts; SMTP is the outgoing server and the auth code is not your mailbox password. Missing values show a red banner and Broker 503. Use Help for 163/Gmail setup steps."
                         Foreground="#64748B" FontSize="10" TextWrapping="Wrap" Margin="0,4,0,0"/>
            </Grid>
          </Border>

          <Expander x:Name="AdvancedExpander" Grid.Row="3" Grid.Column="0" Grid.ColumnSpan="5"
                    IsExpanded="False" Foreground="#CBD5E1" Margin="0,14,0,0"
                    Header="Advanced: personal plugins / API key">
            <Grid Margin="0,8,0,0">
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
              </Grid.RowDefinitions>
              <TextBlock x:Name="PersonalPluginsLabel" Grid.Row="0" Grid.Column="0" Text="Personal plugins" Foreground="#CBD5E1" VerticalAlignment="Center"/>
              <TextBox Grid.Row="0" Grid.Column="1" x:Name="PersonalPluginsBox" Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>
              <TextBlock x:Name="ApiKeyFileLabel" Grid.Row="0" Grid.Column="3" Text="API key file (optional)" Foreground="#CBD5E1" VerticalAlignment="Center"/>
              <TextBox Grid.Row="0" Grid.Column="4" x:Name="ApiKeyFileBox" Background="#0B1220" Foreground="#F8FAFC" BorderBrush="#334155" Padding="8"/>
              <TextBlock x:Name="ApiKeyNote" Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="5"
                         Text="API keys are not stored in this UI. The optional file is read by the installer and never written to the GUI log."
                         Foreground="#64748B" FontSize="11" TextWrapping="Wrap" Margin="0,10,0,0"/>
            </Grid>
          </Expander>

          <TextBlock x:Name="QuickHelp" Grid.Row="4" Grid.Column="0" Grid.ColumnSpan="5"
                     Text=""
                     Foreground="#A8B7CB" FontSize="11" TextWrapping="Wrap" Margin="0,12,0,0"/>
          <CheckBox x:Name="DefenderExclusionCheck" Grid.Row="5" Grid.Column="0" Grid.ColumnSpan="5"
                    Content="I understand this build is unsigned; add only C:\CyberButler to Defender exclusions"
                    Foreground="#FBBF24" FontSize="12" Margin="0,12,0,0" IsChecked="False"/>
          <TextBlock x:Name="DefenderHint" Grid.Row="6" Grid.Column="0" Grid.ColumnSpan="5"
                     Text="Huorong/360: add C:\CyberButler to the trust list manually. This installer never disables real-time protection."
                     Foreground="#64748B" FontSize="11" TextWrapping="Wrap" Margin="0,6,0,0"/>
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
      <CheckBox x:Name="PhysicalSeparationCheck" Content="我已确认 TOTP 验证器（手机/邮箱）不在当前这台机器上 / TOTP authenticator is on another device"
                Foreground="#F87171" VerticalAlignment="Center" Margin="8,0,0,0"/>
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
      <TextBlock x:Name="InstallerLabel" Text="Installer: " Foreground="#475569" FontSize="11"/>
      <TextBlock x:Name="InstallerPathText" Text="" Foreground="#64748B" FontSize="11" TextTrimming="CharacterEllipsis" Width="760"/>
    </StackPanel>
  </Grid>
  </ScrollViewer>
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
$webUIEmailBox = $window.FindName('WebUIEmailBox')
$smtpAuthBox = $window.FindName('SmtpAuthBox')
$smtpHostBox = $window.FindName('SmtpHostBox')
$smtpPortBox = $window.FindName('SmtpPortBox')
$mainScroll = $window.FindName('MainScroll')
if ($mainScroll) {
    $mainScroll.Add_PreviewMouseWheel({
        param($sender, $eventArgs)
        $step = [Math]::Max(24, [Math]::Abs([int]$eventArgs.Delta) / 2)
        if ($eventArgs.Delta -gt 0) { $sender.ScrollToVerticalOffset($sender.VerticalOffset - $step) }
        else { $sender.ScrollToVerticalOffset($sender.VerticalOffset + $step) }
        $eventArgs.Handled = $true
    })
}
$startButton = $window.FindName('StartButton')
$reportButton = $window.FindName('ReportButton')
$removeButton = $window.FindName('RemoveButton')
$statusButton = $window.FindName('StatusButton')
$closeButton = $window.FindName('CloseButton')
$helpButton = $window.FindName('HelpButton')
$quickHelp = $window.FindName('QuickHelp')
$installProgress = $window.FindName('InstallProgress')
$approvalCheck = $window.FindName('ApprovalCheck')
$defenderExclusionCheck = $window.FindName('DefenderExclusionCheck')
$defenderHint = $window.FindName('DefenderHint')
$logBox = $window.FindName('LogBox')
$statusText = $window.FindName('StatusText')
$installerPathText = $window.FindName('InstallerPathText')
$installerLabel = $window.FindName('InstallerLabel')
$installerPathText.Text = $installerPath
$installerPathText.ToolTip = $installerPath
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
$advancedExpander = $window.FindName('AdvancedExpander')

$script:UiText = @{
    zh = @{
        Title='Cyber-Butler 安装程序'; Subtitle='v1.6.1 · 可视化安装前端'
        Warning='只有勾选批准后，GUI 才会提交 approval token；TOTP 在可视化对话框中确认，不再打开第二个命令窗口。'
        InstallPath='安装路径'; Tier='安全档位'; OwnerQQ='主人 QQ'; Bind='WebUI 绑定'
        PersonalPlugins='个人插件路径'; ApiKeyFile='API Key 文件（可选，sk-...）'
        ApiKeyNote='API Key 不会保存在此界面；可选文件由安装器读取，不会写入 GUI 日志。'
        QuickHelp='主人 QQ：你自己的主账号，不是机器人 QQ。安装路径、安全档位和 WebUI 绑定可直接设置；个人插件与 API Key 在“高级选项”中。详细差异点“说明”按钮。'
        HelpBody="Cyber-Butler 安装选项说明`n`n主人 QQ`n填你自己的主 QQ（管理员/所有者账号），不是机器人 QQ。用于 TOTP 标签、审批/通知路由、YOUR_QQ_ID 和 owner allowlist。机器人 QQ 在 AstrBot/QQ 适配器中单独配置。`n`n安全档位`nHigh：Windows 10/11 x64 + 管理员 + 独立本地服务账户；AstrBot/WebUI 以服务身份运行；TOTP vault 对 Agent 账户有 Deny；LAN 被禁止；隔离最强。`nMedium：使用当前桌面账户，Interactive 计划任务；无法对同一账户强制 TOTP vault Deny；适合单机测试。`nLight：减少 ACL/审计/TOTP egress，仅建议低价值或临时环境。`n档位不改变硬件前提：Windows 10/11 x64、PowerShell 5.1、管理员权限、Python 3.10–3.13。本地模型显存参考：24GB+ 可跑 20–24B；16GB 可跑 7–14B；8GB 可跑 3–7B 量化；无独显或不小于 8GB 时可用 API-only；所有档位都支持 API-only。`n`nWebUI 绑定`nLoopback：只监听 127.0.0.1，最安全。`nTailscale：通过私有 tailnet 访问，需要 Tailscale。`nLAN：局域网可访问，暴露面最大；High 禁止 LAN。`n`n个人插件`n不随开源包发布。需要你已有的 AstrBot 插件目录，包含三个插件：private_companion（我会永远陪着你：角色状态、日程、关系、主动消息、陪伴核心）、livingmemory（长期记忆生命周期）、memorix（图谱+向量混合检索记忆）。安装器只复制这三个名字，不联网下载；获取渠道是你现有 AstrBot/data/plugins 或上游仓库。`n`nAPI Key`n本字段填写包含 DeepSeek API Key 的文件路径，通常 sk-...，只用于 DeepSeek provider。其他大模型或 OpenAI-compatible API 需要在 AstrBot 的 provider 配置/WebUI 中单独添加，不能靠本字段直接切换。DeepSeek Key 获取：https://platform.deepseek.com/api_keys 。`n`n批准勾选`n只有勾选后才会提交 approval token；GUI 不会静默批准安全步骤。"
        Preflight='检查环境'; Start='开始安装'; Installing='安装中...'; Report='打开报告目录'; Exit='退出'; Help='说明'; Remove='删除程序'; Advanced='高级选项：个人插件 / API Key'; PathTip='Cyber-Butler 的安装目录，默认 C:\CyberButler。'; TierTip='High：独立服务账户；Medium：当前桌面账户；Light：较低保护。详见“说明”。'; OwnerTip='填你自己的主 QQ（管理员/所有者账号），不是机器人 QQ。'; BindTip='Loopback 仅本机；Tailscale 私有网络；LAN 局域网暴露。'; PluginsTip='可选目录，包含 private_companion、livingmemory、memorix 三个插件。'; ApiTip='可选 DeepSeek API Key 文件路径，通常 sk-...；获取地址见“说明”。'; RemoveConfirm='这会停止服务并永久删除此项目的安装目录和 ProgramData 状态。确定删除？'; RemoveDone='删除完成。'; RemoveFailed='删除失败：'; RemoveTitle='删除 Cyber-Butler'; RemoveHint='选择要删除的内容。删除不可恢复；同目录下与版本匹配的下载 zip 也会一并删除。'; RemovePackage='只删除安装程序/发布包'; RemoveProject='只删除主项目 C:\CyberButler'; RemoveBoth='同时删除发布包和主项目'; Continue='继续'; RemoveConfirm2='二次确认：确定执行不可恢复的删除吗？'; RemoveBothDone='主项目已删除；发布包将在 GUI 退出后删除。'; RemovePackageDone='发布包将在 GUI 退出后删除。'; RemoveProjectDone='主项目已删除。'; CheckStatus='检查状态'; StatusTitle='安装状态'; StatusRunning='安装器正在运行。'; StatusStalled='安装器进程还在，但已经很久没有新输出，可能卡住。'; StatusWaitingTotp='正在等待 TOTP 确认。'; StatusCompleted='安装已经完成。'; StatusFailed='安装失败。'; StatusNoActive='当前没有正在运行的安装，也没有找到成功报告。'; StatusStage='当前阶段'; StatusProcess='安装器进程'; StatusLastOutput='最后输出'; StatusReport='报告状态'; StatusPorts='服务端口'; StatusStep='步骤完成度'; StatusStepEta='当前步骤预计剩余'; StatusTotalEta='总预计剩余'; StatusElapsed='已用时间'; StatusProcessDetail='进程详情'; StatusTOTP='TOTP 状态'; StatusLog='日志'; StatusNote='预计值基于当前阶段和日志活动，不是保证值。'; Copy='复制'; RefreshStatus='刷新'; PostTitle='安装完成'; PostSubtitle='三个服务已安装并启动。下一步打开 WebUI，配置机器人 QQ 和模型 provider。'; PostNext='下一步：打开 WebUI -> 配置机器人 QQ 适配器 -> 添加其他模型 provider -> 发测试消息 -> 离线保存 TOTP 恢复码。'; OpenWebUI='打开 WebUI'; OpenAstrBot='打开 AstrBot'; OpenGuide='安装说明'; OpenReport='安装报告'; Close='关闭'
        Approval='我已阅读上方说明，确认执行这些安装步骤'; NeedApproval='请先勾选安装确认。'
        DefenderExclusion='我已了解此版本未签名；仅将 C:\CyberButler 加入 Defender 排除项（默认不勾选）'; DefenderHint='火绒/360：请手动将 C:\CyberButler 加入信任区。安装器不会关闭实时防护，也不会排除 C 盘根目录。'; DefenderExclusionFailed='Defender 排除项添加失败：'; DefenderExclusionDone='已将 C:\CyberButler 加入 Defender 排除项。'
        TotpTitle='TOTP 注册'; TotpHint='扫描二维码并离线保存恢复码，然后勾选两项确认。'; Scanned='我已扫描二维码'; Recovery='我已保存恢复码'; Confirm='确认并继续'; Cancel='取消'; TotpReady='TOTP 材料已就绪，等待扫码和确认...'; TotpConfirmed='TOTP 已确认，继续安装服务...'; Invalid='TOTP 确认无效。'
        Ready='就绪。'; RunningPreflight='正在检查环境...'; PreflightDone='检查完成，请确认后开始安装。'
        PreflightFailed='环境检查失败。'; Starting='正在启动安装器...'; Started='安装器已启动，进度和 TOTP 将显示在本窗口。'
        StartFailed='无法启动安装器。'; Admin='已检测到管理员会话。'; NotAdmin='当前不是管理员；开始安装会请求 UAC。'; CloseConfirm='安装正在进行。关闭窗口会终止隐藏安装器，并可能留下不完整安装。确定终止吗？'; CloseConfirmTitle='终止安装'
        NoReport='报告目录不存在：'
        InstallerLabel='安装程序：'
        TierHigh='高 (High)'
        TierMedium='中 (Medium)'
        TierLight='低 (Light)'
        BindLoopback='仅本机 (Loopback)'
        BindTailscale='Tailscale 私有网络'
        BindLAN='局域网 (LAN)'
        OpenLaunchGuide='登录与启动说明'
        LaunchGuideTitle='登录、启动与维护说明'
    }
    en = @{
        Title='Cyber-Butler Setup'; Subtitle='v1.6.1 · visual installer front-end'
        Warning='The GUI supplies approval tokens only after your explicit approval. TOTP is confirmed in a dialog; no second command window is used.'
        InstallPath='Install path'; Tier='Tier'; OwnerQQ='Owner QQ'; Bind='WebUI bind'
        PersonalPlugins='Personal plugins'; ApiKeyFile='API key file (optional, sk-...)'
        ApiKeyNote='API keys are not stored in this UI. The optional file is read by the installer and never written to the GUI log.'
        QuickHelp='Owner QQ: your own main account, not the bot QQ. Set path, tier and WebUI bind here; personal plugins and API key are under Advanced. Open Help for details.'
        HelpBody="Cyber-Butler installer options`n`nOwner QQ`nEnter your own main QQ (the owner/admin account), not the bot QQ. It feeds the TOTP label, approval/notification routing, YOUR_QQ_ID and the owner allowlist. The bot QQ is configured separately in AstrBot/QQ.`n`nSecurity tier`nHigh: Windows 10/11 x64 + admin + a dedicated local service account; AstrBot/WebUI run as services; TOTP vault denies the agent account; LAN is rejected; strongest isolation.`nMedium: current desktop account with Interactive scheduled tasks; a same-account TOTP vault deny cannot be enforced; suitable for single-machine testing.`nLight: reduced ACL/audit/TOTP egress; only for temporary or low-value environments.`nTier does not change the hardware baseline: Windows 10/11 x64, PowerShell 5.1, admin rights, Python 3.10–3.13. Local model VRAM guidance: 24GB+ for 20–24B, 16GB for 7–14B, 8GB for 3–7B quantized, no dGPU for API-only; every tier supports API-only.`n`nWebUI bind`nLoopback: 127.0.0.1 only, safest.`nTailscale: private tailnet access; requires Tailscale.`nLAN: reachable on the local network; largest exposure; High rejects LAN.`n`nPersonal plugins`nNot bundled. Provide an existing AstrBot plugin folder containing private_companion (the companion core: character state, schedule, relationships, proactive messages), livingmemory (long-term memory lifecycle), and memorix (graph+vector hybrid memory). The installer copies only those three and never downloads them; obtain them from your existing AstrBot/data/plugins or their upstream repositories.`n`nAPI key`nThis field takes a file path containing a DeepSeek API key (usually sk-...) and writes only the DeepSeek provider secret. Other models or OpenAI-compatible endpoints must be configured in AstrBot providers/WebUI; this field does not switch providers. Get a DeepSeek key: https://platform.deepseek.com/api_keys .`n`nApproval checkbox`nIt supplies approval tokens only after it is checked; the GUI never silently approves security steps."
        Preflight='Run preflight'; Start='Start installation'; Installing='Installing...'; Report='Open report folder'; Exit='Exit'; Help='Help'; Remove='Uninstall'; Advanced='Advanced: personal plugins / API key'; PathTip='Cyber-Butler install directory (default C:\CyberButler).'; TierTip='High: separate service account; Medium: current desktop account; Light: reduced protection. See Help.'; OwnerTip='Your own main QQ (owner/admin account), not the bot QQ.'; BindTip='Loopback: local only; Tailscale: private tailnet; LAN: network exposure.'; PluginsTip='Optional folder containing private_companion, livingmemory and memorix.'; ApiTip='Optional DeepSeek API key file path (usually sk-...); see Help for the URL.'; RemoveConfirm='This stops services and permanently deletes the project install directory and ProgramData state. Continue?'; RemoveDone='Uninstall completed.'; RemoveFailed='Uninstall failed: '; RemoveTitle='Remove Cyber-Butler'; RemoveHint='Choose what to remove. This cannot be undone; a matching downloaded zip in the same parent folder is removed too.'; RemovePackage='Installer / release package only'; RemoveProject='Installed C:\CyberButler project only'; RemoveBoth='Both release package and installed project'; Continue='Continue'; RemoveConfirm2='Second confirmation: delete permanently? This cannot be undone.'; RemoveBothDone='Project removed; the release package will be removed after this GUI exits.'; RemovePackageDone='The release package will be removed after this GUI exits.'; RemoveProjectDone='The installed project was removed.'; CheckStatus='Check status'; StatusTitle='Install status'; StatusRunning='The installer is running.'; StatusStalled='The installer process exists, but there has been no new output for a long time; it may be stalled.'; StatusWaitingTotp='Waiting for TOTP confirmation.'; StatusCompleted='Installation has completed.'; StatusFailed='Installation failed.'; StatusNoActive='No active installation and no successful report found.'; StatusStage='Stage'; StatusProcess='Installer process'; StatusLastOutput='Last output'; StatusReport='Report status'; StatusPorts='Service ports'; StatusStep='Step completion'; StatusStepEta='Step ETA'; StatusTotalEta='Overall ETA'; StatusElapsed='Elapsed'; StatusProcessDetail='Process details'; StatusTOTP='TOTP state'; StatusLog='Log'; StatusNote='ETAs are heuristic from the current stage and log activity, not guarantees.'; Copy='Copy'; RefreshStatus='Refresh'; PostTitle='Installation complete'; PostSubtitle='The three services are installed and running. Next, open the WebUI and configure the bot QQ and model provider.'; PostNext='Next: open WebUI -> configure the bot QQ adapter -> add other model providers -> send a test message -> store TOTP recovery codes offline.'; OpenWebUI='Open WebUI'; OpenAstrBot='Open AstrBot'; OpenGuide='Install guide'; OpenReport='Install report'; Close='Close'
        Approval='I have read the notes above and approve these installer steps'; NeedApproval='Please check the approval box first.'
        DefenderExclusion='I understand this build is unsigned; add only C:\CyberButler to Defender exclusions (unchecked by default)'; DefenderHint='Huorong/360: manually add C:\CyberButler to the trust list. This installer never disables real-time protection or excludes the C: root.'; DefenderExclusionFailed='Defender exclusion failed: '; DefenderExclusionDone='C:\CyberButler has been added to Defender exclusions.'
        TotpTitle='TOTP Enrollment'; TotpHint='Scan the QR code and store the recovery codes offline, then confirm both checks.'; Scanned='I scanned the QR code'; Recovery='I saved the recovery codes'; Confirm='Confirm and continue'; Cancel='Cancel'; TotpReady='TOTP material is ready; waiting for scan and confirmation...'; TotpConfirmed='TOTP confirmed; continuing services...'; Invalid='Invalid TOTP confirmation.'
        Ready='Ready.'; RunningPreflight='Running preflight...'; PreflightDone='Preflight finished. Review the output, then start installation.'
        PreflightFailed='Preflight failed.'; Starting='Starting installer...'; Started='Installer started; progress and TOTP are shown in this window.'
        StartFailed='Could not start the installer.'; Admin='Administrator session detected.'; NotAdmin='This GUI is not elevated. Start installation will request UAC.'; CloseConfirm='Installation is running. Closing the window will stop the hidden installer and may leave a partial install. Terminate?'; CloseConfirmTitle='Terminate installation'
        NoReport='Report directory not found: '
        InstallerLabel='Installer: '
        TierHigh='High'
        TierMedium='Medium'
        TierLight='Light'
        BindLoopback='Loopback'
        BindTailscale='Tailscale'
        BindLAN='LAN'
        OpenLaunchGuide='Login & startup guide'
        LaunchGuideTitle='Login, startup and maintenance guide'
    }
    de = @{
        Title='Cyber-Butler Installationsprogramm'; Subtitle='v1.6.1 · visueller Installer'
        Warning='Die GUI übergibt Freigabetoken erst nach Ihrer ausdrücklichen Bestätigung. TOTP wird in einem Dialog bestätigt.'
        InstallPath='Installationspfad'; Tier='Sicherheitsstufe'; OwnerQQ='Eigentümer-QQ'; Bind='WebUI-Bindung'
        PersonalPlugins='Persönliche Plugins'; ApiKeyFile='API-Key-Datei (optional, sk-...)'
        ApiKeyNote='API-Keys werden nicht in der GUI gespeichert.'
        QuickHelp='Eigentümer-QQ: Ihr eigenes Hauptkonto, nicht der Bot. Pfad, Stufe und WebUI-Bindung sind direkt einstellbar; persönliche Plugins und API-Key unter Erweitert. Details über Hilfe.'
        Preflight='Umgebung prüfen'; Start='Installation starten'; Installing='Installation läuft...'; Report='Bericht öffnen'; Exit='Beenden'; Help='Hilfe'; Remove='Entfernen'; Advanced='Erweitert: persönliche Plugins / API-Key'
        PathTip='Installationsverzeichnis, Standard C:\CyberButler.'; TierTip='High: separates Dienstkonto; Medium: aktuelles Desktopkonto; Light: geringerer Schutz.'; OwnerTip='Ihr eigenes Haupt-QQ, nicht der Bot.'; BindTip='Loopback: nur lokal; Tailscale: privates Netz; LAN: Netzwerkfreigabe.'; PluginsTip='Optionales Verzeichnis mit private_companion, livingmemory und memorix.'; ApiTip='Optionaler Pfad zu einer DeepSeek-API-Key-Datei (sk-...).'
        Approval='Ich habe die Hinweise gelesen und stimme den Schritten zu'; NeedApproval='Bitte zuerst die Freigabe ankreuzen.'
        TotpTitle='TOTP-Registrierung'; TotpHint='QR-Code scannen und Wiederherstellungscodes offline speichern.'; Scanned='QR-Code gescannt'; Recovery='Wiederherstellungscodes gespeichert'; Confirm='Bestätigen und fortfahren'; Cancel='Abbrechen'; TotpReady='TOTP-Material bereit; warten auf Bestätigung...'; TotpConfirmed='TOTP bestätigt; Dienste werden fortgesetzt...'; Invalid='Ungültige TOTP-Bestätigung.'
        Ready='Bereit.'; RunningPreflight='Umgebung wird geprüft...'; PreflightDone='Prüfung abgeschlossen. Bitte bestätigen und dann die Installation starten.'; PreflightFailed='Umgebungsprüfung fehlgeschlagen.'; Starting='Installer wird gestartet...'; Started='Installer gestartet.'; StartFailed='Installer konnte nicht gestartet werden.'; Admin='Administratorsitzung erkannt.'; NotAdmin='Diese GUI ist nicht erhöht.'; CloseConfirm='Installation läuft. Schließen beendet den Installer und kann eine unvollständige Installation hinterlassen. Beenden?'; CloseConfirmTitle='Installation beenden'; NoReport='Berichtsverzeichnis nicht gefunden: '
        CheckStatus='Status prüfen'
        StatusTitle='Installationsstatus'
        StatusRunning='Der Installer läuft.'
        StatusStalled='Der Installerprozess läuft, aber es gibt seit längerer Zeit keine neue Ausgabe; er könnte hängen.'
        StatusWaitingTotp='Warten auf TOTP-Bestätigung.'
        StatusCompleted='Die Installation ist abgeschlossen.'
        StatusFailed='Die Installation ist fehlgeschlagen.'
        StatusNoActive='Keine laufende Installation und kein Erfolgsbericht gefunden.'
        StatusStage='Aktuelle Phase'
        StatusProcess='Installerprozess'
        StatusLastOutput='Letzte Ausgabe'
        StatusReport='Berichtsstatus'
        StatusPorts='Dienstports'
        StatusStep='Schrittfortschritt'
        StatusStepEta='Restzeit des Schritts'
        StatusTotalEta='Gesamte Restzeit'
        StatusElapsed='Verstrichen'
        StatusProcessDetail='Prozessdetails'
        StatusTOTP='TOTP-Status'
        StatusLog='Protokoll'
        StatusNote='Die Schätzungen basieren auf Phase und Protokollaktivität, keine Garantie.'
        Copy='Kopieren'
        RefreshStatus='Aktualisieren'
        RemoveTitle='Cyber-Butler entfernen'
        RemoveHint='Wählen Sie den Umfang. Das Löschen ist nicht rückgängig zu machen; eine passende ZIP im gleichen Ordner wird ebenfalls entfernt.'
        RemovePackage='Nur Installer / Release-Paket löschen'
        RemoveProject='Nur das Projekt C:\CyberButler löschen'
        RemoveBoth='Release-Paket und Projekt löschen'
        Continue='Weiter'
        RemoveConfirm='Dienste stoppen und das Projekt dauerhaft löschen?'
        RemoveDone='Entfernen abgeschlossen.'
        RemoveFailed='Entfernen fehlgeschlagen: '
        RemoveConfirm2='Zweite Bestätigung: endgültig und nicht rückgängig lösbar?'
        RemoveBothDone='Projekt entfernt; das Release-Paket wird nach dem Beenden der GUI entfernt.'
        RemovePackageDone='Das Release-Paket wird nach dem Beenden der GUI entfernt.'
        RemoveProjectDone='Das installierte Projekt wurde entfernt.'
        PostTitle='Installation abgeschlossen'
        PostSubtitle='Die drei Dienste sind installiert und laufen. Öffnen Sie als Nächstes die WebUI und konfigurieren Sie Bot-QQ und Modell-Provider.'
        PostNext='Weiter: WebUI öffnen -> Bot-QQ-Adapter konfigurieren -> weitere Modell-Provider hinzufügen -> Testnachricht senden -> TOTP-Codes offline speichern.'
        OpenWebUI='WebUI öffnen'
        OpenAstrBot='AstrBot öffnen'
        OpenGuide='Installationsanleitung'
        OpenReport='Installationsbericht'
        Close='Schließen'
        HelpBody="Cyber-Butler Installationsoptionen`n`nEigentümer-QQ`nIhr eigenes Haupt-QQ (Eigentümer/Admin), nicht das Bot-QQ. Es dient TOTP-Label, Freigabe-/Benachrichtigungsrouting, YOUR_QQ_ID und der Eigentümer-Allowlist. Das Bot-QQ wird separat in AstrBot/QQ konfiguriert.`n`nSicherheitsstufe`nHigh: Windows 10/11 x64 + Administrator + separates lokales Dienstkonto; AstrBot/WebUI laufen als Dienst; TOTP-Vault verweigert dem Agent-Konto; LAN ist gesperrt; stärkste Isolation.`nMedium: aktuelles Desktopkonto mit interaktiven Aufgaben; eine TOTP-Vault-Verweigerung für dasselbe Konto ist nicht durchsetzbar; für Einzelplatz-Tests.`nLight: reduzierte ACL/Prüfung/TOTP-Egress; nur für temporäre oder wenig wertvolle Umgebungen.`nDie Stufe ändert die Hardwarebasis nicht: Windows 10/11 x64, PowerShell 5.1, Administratorrechte, Python 3.10–3.13. Lokales Modell: 24GB+ für 20–24B, 16GB für 7–14B, 8GB für 3–7B quantisiert, ohne dGPU nur API.`n`nWebUI-Bindung`nLoopback: nur 127.0.0.1.`nTailscale: privates Tailnet.`nLAN: lokales Netzwerk; High lehnt LAN ab.`n`nPersönliche Plugins`nNicht im Paket. Ein vorhandener AstrBot-Plugin-Ordner mit private_companion (Companion-Kern), livingmemory (Langzeitgedächtnis) und memorix (Graph+Vektor-Gedächtnis). Der Installer kopiert nur diese drei und lädt nichts herunter.`n`nAPI-Key`nDieses Feld erwartet einen Dateipfad mit einem DeepSeek-API-Key (sk-...). Andere Modelle oder OpenAI-kompatible Endpunkte müssen in den AstrBot-Providern konfiguriert werden. DeepSeek-Key: https://platform.deepseek.com/api_keys .`n`nFreigabe`nNur nach dem Ankreuzen werden Freigabetoken übergeben; die GUI stimmt nie stillschweigend zu."
        InstallerLabel='Installer: '
        TierHigh='Hoch (High)'
        TierMedium='Mittel (Medium)'
        TierLight='Niedrig (Light)'
        BindLoopback='Nur lokal (Loopback)'
        BindTailscale='Tailscale'
        BindLAN='LAN'
        OpenLaunchGuide='Anmeldung & Start'
        LaunchGuideTitle='Anmeldung, Start und Wartung'
    }
    es = @{
        Title='Instalador de Cyber-Butler'; Subtitle='v1.6.1 · instalador visual'
        Warning='La GUI entrega los tokens solo tras su aprobación explícita. TOTP se confirma en un diálogo.'
        InstallPath='Ruta de instalación'; Tier='Nivel de seguridad'; OwnerQQ='QQ del propietario'; Bind='Enlace WebUI'
        PersonalPlugins='Plugins personales'; ApiKeyFile='Archivo de API Key (opcional, sk-...)'
        ApiKeyNote='Las API Keys no se guardan en esta GUI.'
        QuickHelp='QQ del propietario: su cuenta principal, no el bot. Ruta, nivel y enlace se configuran aquí; plugins y API Key en Avanzado. Consulte Ayuda.'
        Preflight='Comprobar entorno'; Start='Iniciar instalación'; Installing='Instalando...'; Report='Abrir informe'; Exit='Salir'; Help='Ayuda'; Remove='Desinstalar'; Advanced='Avanzado: plugins / API Key'
        PathTip='Directorio de instalación, por defecto C:\CyberButler.'; TierTip='High: cuenta de servicio separada; Medium: cuenta actual; Light: menos protección.'; OwnerTip='Su QQ principal, no el del bot.'; BindTip='Loopback: solo local; Tailscale: red privada; LAN: exposición de red.'; PluginsTip='Carpeta opcional con private_companion, livingmemory y memorix.'; ApiTip='Ruta opcional a un archivo de clave DeepSeek (sk-...).'
        Approval='He leído las notas y apruebo estos pasos'; NeedApproval='Marque primero la aprobación.'
        TotpTitle='Registro TOTP'; TotpHint='Escanee el código QR y guarde los códigos de recuperación sin conexión.'; Scanned='He escaneado el QR'; Recovery='He guardado los códigos'; Confirm='Confirmar y continuar'; Cancel='Cancelar'; TotpReady='Material TOTP listo; esperando confirmación...'; TotpConfirmed='TOTP confirmado; continuando servicios...'; Invalid='Confirmación TOTP no válida.'
        Ready='Listo.'; RunningPreflight='Comprobando entorno...'; PreflightDone='Comprobación completada. Confirme y luego inicie la instalación.'; PreflightFailed='Error en la comprobación.'; Starting='Iniciando instalador...'; Started='Instalador iniciado.'; StartFailed='No se pudo iniciar el instalador.'; Admin='Sesión de administrador detectada.'; NotAdmin='Esta GUI no está elevada.'; CloseConfirm='La instalación está en curso. Cerrar detendrá el instalador y puede dejar una instalación incompleta. ¿Terminar?'; CloseConfirmTitle='Terminar instalación'; NoReport='Carpeta de informes no encontrada: '
        CheckStatus='Comprobar estado'
        StatusTitle='Estado de instalación'
        StatusRunning='El instalador está en ejecución.'
        StatusStalled='El proceso existe, pero no hay salida nueva desde hace mucho; puede estar bloqueado.'
        StatusWaitingTotp='Esperando confirmación TOTP.'
        StatusCompleted='La instalación ha finalizado.'
        StatusFailed='La instalación ha fallado.'
        StatusNoActive='No hay instalación activa ni informe de éxito.'
        StatusStage='Etapa actual'
        StatusProcess='Proceso del instalador'
        StatusLastOutput='Última salida'
        StatusReport='Estado del informe'
        StatusPorts='Puertos de servicio'
        StatusStep='Progreso del paso'
        StatusStepEta='Tiempo restante del paso'
        StatusTotalEta='Tiempo total restante'
        StatusElapsed='Transcurrido'
        StatusProcessDetail='Detalles del proceso'
        StatusTOTP='Estado TOTP'
        StatusLog='Registro'
        StatusNote='Las estimaciones se basan en la etapa y la actividad del registro; no son garantías.'
        Copy='Copiar'
        RefreshStatus='Actualizar'
        RemoveTitle='Eliminar Cyber-Butler'
        RemoveHint='Elija qué eliminar. No se puede deshacer; también se borra un ZIP coincidente en la misma carpeta.'
        RemovePackage='Solo instalador / paquete de publicación'
        RemoveProject='Solo el proyecto C:\CyberButler'
        RemoveBoth='Paquete y proyecto instalado'
        Continue='Continuar'
        RemoveConfirm='¿Detener servicios y borrar el proyecto permanentemente?'
        RemoveDone='Eliminación completada.'
        RemoveFailed='Error al eliminar: '
        RemoveConfirm2='Segunda confirmación: ¿borrar de forma permanente e irreversible?'
        RemoveBothDone='Proyecto eliminado; el paquete se borrará al cerrar la GUI.'
        RemovePackageDone='El paquete se borrará al cerrar la GUI.'
        RemoveProjectDone='El proyecto instalado fue eliminado.'
        PostTitle='Instalación completada'
        PostSubtitle='Los tres servicios están instalados y en ejecución. Abra la WebUI y configure el QQ del bot y el proveedor de modelos.'
        PostNext='Siguiente: abrir WebUI -> configurar adaptador QQ del bot -> añadir proveedores -> enviar mensaje de prueba -> guardar códigos TOTP offline.'
        OpenWebUI='Abrir WebUI'
        OpenAstrBot='Abrir AstrBot'
        OpenGuide='Guía de instalación'
        OpenReport='Informe de instalación'
        Close='Cerrar'
        HelpBody="Opciones del instalador Cyber-Butler`n`nQQ del propietario`nSu QQ principal (propietario/admin), no el QQ del bot. Se usa para la etiqueta TOTP, enrutamiento de aprobación/notificación, YOUR_QQ_ID y la lista de propietarios. El QQ del bot se configura aparte en AstrBot/QQ.`n`nNivel de seguridad`nHigh: Windows 10/11 x64 + administrador + cuenta de servicio local dedicada; AstrBot/WebUI como servicio; la bóveda TOTP niega la cuenta del agente; LAN rechazada; máxima aislamiento.`nMedium: cuenta de escritorio actual con tareas interactivas; no se puede imponer la denegación TOTP para la misma cuenta; para pruebas de una máquina.`nLight: ACL/auditoría/egress TOTP reducidos; solo entornos temporales o de bajo valor.`nEl nivel no cambia la base de hardware: Windows 10/11 x64, PowerShell 5.1, administrador, Python 3.10–3.13. Modelo local: 24GB+ para 20–24B, 16GB para 7–14B, 8GB para 3–7B cuantizado, sin dGPU solo API.`n`nEnlace WebUI`nLoopback: solo 127.0.0.1.`nTailscale: tailnet privado.`nLAN: red local; High rechaza LAN.`n`nPlugins personales`nNo incluidos. Una carpeta AstrBot existente con private_companion (núcleo de compañía), livingmemory (memoria a largo plazo) y memorix (memoria grafo+vector). El instalador copia solo esos tres y no descarga nada.`n`nAPI Key`nEste campo espera una ruta de archivo con una clave DeepSeek (sk-...). Otros modelos o endpoints compatibles con OpenAI deben configurarse en los proveedores de AstrBot. Clave DeepSeek: https://platform.deepseek.com/api_keys .`n`nAprobación`nSolo después de marcarla se envían tokens; la GUI nunca aprueba en silencio."
        InstallerLabel='Instalador: '
        TierHigh='Alto (High)'
        TierMedium='Medio (Medium)'
        TierLight='Bajo (Light)'
        BindLoopback='Solo local (Loopback)'
        BindTailscale='Tailscale'
        BindLAN='LAN'
        OpenLaunchGuide='Acceso y inicio'
        LaunchGuideTitle='Acceso, inicio y mantenimiento'
    }
    fr = @{
        Title='Installateur Cyber-Butler'; Subtitle='v1.6.1 · installateur visuel'
        Warning='L interface ne transmet les jetons qu après votre approbation explicite. TOTP est confirmé dans une boîte de dialogue.'
        InstallPath='Chemin d installation'; Tier='Niveau de sécurité'; OwnerQQ='QQ propriétaire'; Bind='Liaison WebUI'
        PersonalPlugins='Plugins personnels'; ApiKeyFile='Fichier de clé API (facultatif, sk-...)'
        ApiKeyNote='Les clés API ne sont pas stockées dans cette interface.'
        QuickHelp='QQ propriétaire : votre compte principal, pas le bot. Chemin, niveau et liaison se règlent ici ; plugins et clé API dans Avancé. Voir Aide.'
        Preflight='Vérifier l environnement'; Start='Démarrer l installation'; Installing='Installation...'; Report='Ouvrir le rapport'; Exit='Quitter'; Help='Aide'; Remove='Désinstaller'; Advanced='Avancé : plugins / clé API'
        PathTip='Répertoire d installation, par défaut C:\CyberButler.'; TierTip='High : compte de service séparé ; Medium : compte actuel ; Light : protection réduite.'; OwnerTip='Votre QQ principal, pas celui du bot.'; BindTip='Loopback : local uniquement ; Tailscale : réseau privé ; LAN : exposition réseau.'; PluginsTip='Dossier facultatif avec private_companion, livingmemory et memorix.'; ApiTip='Chemin facultatif vers une clé DeepSeek (sk-...).'
        Approval='J ai lu les notes et j approuve ces étapes'; NeedApproval='Cochez d abord l approbation.'
        TotpTitle='Enregistrement TOTP'; TotpHint='Scannez le QR et conservez les codes de récupération hors ligne.'; Scanned='QR scanné'; Recovery='Codes sauvegardés'; Confirm='Confirmer et continuer'; Cancel='Annuler'; TotpReady='Matériel TOTP prêt ; en attente de confirmation...'; TotpConfirmed='TOTP confirmé ; reprise des services...'; Invalid='Confirmation TOTP invalide.'
        Ready='Prêt.'; RunningPreflight='Vérification de l environnement...'; PreflightDone='Vérification terminée. Confirmez, puis démarrez l installation.'; PreflightFailed='Échec de la vérification.'; Starting='Démarrage de l installateur...'; Started='Installateur démarré.'; StartFailed='Impossible de démarrer l installateur.'; Admin='Session administrateur détectée.'; NotAdmin='Cette interface n est pas élevée.'; CloseConfirm='L installation est en cours. Fermer arrêtera l installateur et peut laisser une installation partielle. Terminer ?'; CloseConfirmTitle='Terminer l installation'; NoReport='Dossier de rapports introuvable : '
        CheckStatus='Vérifier l état'
        StatusTitle='État de l installation'
        StatusRunning='L installateur est en cours.'
        StatusStalled='Le processus existe mais aucune nouvelle sortie depuis longtemps ; il peut être bloqué.'
        StatusWaitingTotp='En attente de confirmation TOTP.'
        StatusCompleted='L installation est terminée.'
        StatusFailed='L installation a échoué.'
        StatusNoActive='Aucune installation active et aucun rapport réussi.'
        StatusStage='Étape actuelle'
        StatusProcess='Processus installateur'
        StatusLastOutput='Dernière sortie'
        StatusReport='État du rapport'
        StatusPorts='Ports de service'
        StatusStep='Avancement de l étape'
        StatusStepEta='Temps restant de l étape'
        StatusTotalEta='Temps restant total'
        StatusElapsed='Écoulé'
        StatusProcessDetail='Détails du processus'
        StatusTOTP='État TOTP'
        StatusLog='Journal'
        StatusNote='Les estimations reposent sur l étape et l activité du journal ; aucune garantie.'
        Copy='Copier'
        RefreshStatus='Actualiser'
        RemoveTitle='Supprimer Cyber-Butler'
        RemoveHint='Choisissez la portée. Action irréversible ; un ZIP correspondant dans le même dossier sera aussi supprimé.'
        RemovePackage='Installateur / paquet de publication uniquement'
        RemoveProject='Projet C:\CyberButler uniquement'
        RemoveBoth='Paquet de publication et projet'
        Continue='Continuer'
        RemoveConfirm='Arrêter les services et supprimer définitivement le projet ?'
        RemoveDone='Suppression terminée.'
        RemoveFailed='Échec de la suppression : '
        RemoveConfirm2='Seconde confirmation : suppression définitive et irréversible ?'
        RemoveBothDone='Projet supprimé ; le paquet sera supprimé à la fermeture de la GUI.'
        RemovePackageDone='Le paquet sera supprimé à la fermeture de la GUI.'
        RemoveProjectDone='Le projet installé a été supprimé.'
        PostTitle='Installation terminée'
        PostSubtitle='Les trois services sont installés et en cours. Ouvrez la WebUI et configurez le QQ du bot et le fournisseur de modèles.'
        PostNext='Suite : ouvrir WebUI -> configurer l adaptateur QQ du bot -> ajouter des fournisseurs -> envoyer un message test -> conserver les codes TOTP hors ligne.'
        OpenWebUI='Ouvrir WebUI'
        OpenAstrBot='Ouvrir AstrBot'
        OpenGuide='Guide d installation'
        OpenReport='Rapport d installation'
        Close='Fermer'
        HelpBody="Options de l installateur Cyber-Butler`n`nQQ propriétaire`nVotre QQ principal (propriétaire/admin), pas celui du bot. Il sert au libellé TOTP, au routage des approbations/notifications, à YOUR_QQ_ID et à la liste propriétaire. Le QQ du bot se configure séparément dans AstrBot/QQ.`n`nNiveau de sécurité`nHigh : Windows 10/11 x64 + administrateur + compte de service local dédié ; AstrBot/WebUI en service ; le coffre TOTP refuse le compte agent ; LAN refusé ; isolation maximale.`nMedium : compte de bureau actuel avec tâches interactives ; le refus TOTP du même compte ne peut pas être imposé ; pour tests sur une machine.`nLight : ACL/audit/egress TOTP réduits ; environnements temporaires ou de faible valeur.`nLe niveau ne change pas la base matérielle : Windows 10/11 x64, PowerShell 5.1, administrateur, Python 3.10–3.13. Modèle local : 24GB+ pour 20–24B, 16GB pour 7–14B, 8GB pour 3–7B quantifié, sans dGPU API uniquement.`n`nLiaison WebUI`nLoopback : 127.0.0.1 seulement.`nTailscale : tailnet privé.`nLAN : réseau local ; High refuse LAN.`n`nPlugins personnels`nNon inclus. Un dossier AstrBot existant avec private_companion (cœur compagnon), livingmemory (mémoire long terme) et memorix (mémoire graphe+vecteur). L installateur copie seulement ces trois et ne télécharge rien.`n`nClé API`nCe champ attend un chemin de fichier contenant une clé DeepSeek (sk-...). Les autres modèles ou endpoints compatibles OpenAI doivent être configurés dans les fournisseurs AstrBot. Clé DeepSeek : https://platform.deepseek.com/api_keys .`n`nApprobation`nLes jetons ne sont transmis qu après la case cochée ; la GUI n approuve jamais silencieusement."
        InstallerLabel='Installateur : '
        TierHigh='Élevé (High)'
        TierMedium='Moyen (Medium)'
        TierLight='Faible (Light)'
        BindLoopback='Local uniquement (Loopback)'
        BindTailscale='Tailscale'
        BindLAN='LAN'
        OpenLaunchGuide='Connexion et démarrage'
        LaunchGuideTitle='Connexion, démarrage et maintenance'
    }
    ja = @{
        Title='Cyber-Butler インストーラー'; Subtitle='v1.6.1 · ビジュアルインストーラー'
        Warning='承認チェック後だけ承認トークンを渡します。TOTP はダイアログで確認します。'
        InstallPath='インストール先'; Tier='セキュリティレベル'; OwnerQQ='オーナー QQ'; Bind='WebUI バインド'
        PersonalPlugins='個人プラグイン'; ApiKeyFile='API Key ファイル（任意、sk-...）'
        ApiKeyNote='API Key はこの画面に保存されません。'
        QuickHelp='オーナー QQ：ボットではなく自分のメイン QQ。パス・レベル・バインドはここで設定し、個人プラグインと API Key は詳細設定にあります。詳細は説明を参照。'
        Preflight='環境を確認'; Start='インストール開始'; Installing='インストール中...'; Report='レポートを開く'; Exit='終了'; Help='説明'; Remove='削除'; Advanced='詳細設定：個人プラグイン / API Key'
        PathTip='インストール先。既定は C:\CyberButler。'; TierTip='High：専用サービスアカウント。Medium：現在のデスクトップ。Light：保護が少ない。'; OwnerTip='自分のメイン QQ。ボット QQ ではありません。'; BindTip='Loopback：ローカルのみ。Tailscale：プライベート網。LAN：LAN 公開。'; PluginsTip='private_companion、livingmemory、memorix を含む任意のフォルダー。'; ApiTip='DeepSeek API Key（sk-...）ファイルの任意パス。'
        Approval='上記を読み、この手順を承認します'; NeedApproval='先に承認にチェックしてください。'
        TotpTitle='TOTP 登録'; TotpHint='QR を読み取り、回復コードをオフライン保存してください。'; Scanned='QR を読み取りました'; Recovery='回復コードを保存しました'; Confirm='確認して続行'; Cancel='キャンセル'; TotpReady='TOTP の準備完了。確認待ち...'; TotpConfirmed='TOTP 確認済み。サービスを続行...'; Invalid='TOTP 確認が無効です。'
        Ready='準備完了'; RunningPreflight='環境を確認中...'; PreflightDone='確認が完了しました。承認してからインストールを開始してください。'; PreflightFailed='環境確認に失敗'; Starting='インストーラーを開始中...'; Started='インストーラー開始'; StartFailed='インストーラーを開始できません'; Admin='管理者セッションを検出'; NotAdmin='管理者権限ではありません'; CloseConfirm='インストール中です。閉じるとインストーラーを停止し、不完全な状態になる可能性があります。終了しますか？'; CloseConfirmTitle='インストールを終了'; NoReport='レポートフォルダーが見つかりません：'
        CheckStatus='状態確認'
        StatusTitle='インストール状態'
        StatusRunning='インストーラーは実行中です。'
        StatusStalled='プロセスは存在しますが、長い間新しい出力がありません。停止している可能性があります。'
        StatusWaitingTotp='TOTP の確認待ちです。'
        StatusCompleted='インストールは完了しました。'
        StatusFailed='インストールは失敗しました。'
        StatusNoActive='実行中のインストールも成功レポートもありません。'
        StatusStage='現在の段階'
        StatusProcess='インストーラープロセス'
        StatusLastOutput='最終出力'
        StatusReport='レポート状態'
        StatusPorts='サービスポート'
        StatusStep='ステップ進捗'
        StatusStepEta='ステップ残り時間'
        StatusTotalEta='全体残り時間'
        StatusElapsed='経過時間'
        StatusProcessDetail='プロセス詳細'
        StatusTOTP='TOTP 状態'
        StatusLog='ログ'
        StatusNote='推定値は段階とログ活動に基づくもので、保証ではありません。'
        Copy='コピー'
        RefreshStatus='更新'
        RemoveTitle='Cyber-Butler を削除'
        RemoveHint='削除範囲を選択してください。元に戻せません。同じフォルダー内の一致する ZIP も削除されます。'
        RemovePackage='インストーラー / 配布パッケージのみ'
        RemoveProject='C:\CyberButler プロジェクトのみ'
        RemoveBoth='配布パッケージとプロジェクトの両方'
        Continue='続行'
        RemoveConfirm='サービスを停止し、プロジェクトを完全に削除しますか？'
        RemoveDone='削除が完了しました。'
        RemoveFailed='削除に失敗しました：'
        RemoveConfirm2='二次確認：完全に削除し、元に戻せません。実行しますか？'
        RemoveBothDone='プロジェクトを削除しました。配布パッケージは GUI 終了後に削除されます。'
        RemovePackageDone='配布パッケージは GUI 終了後に削除されます。'
        RemoveProjectDone='インストール済みプロジェクトを削除しました。'
        PostTitle='インストール完了'
        PostSubtitle='3 つのサービスがインストールされ実行中です。WebUI を開き、ボット QQ とモデルプロバイダーを設定してください。'
        PostNext='次へ：WebUI を開く -> ボット QQ アダプターを設定 -> 他のモデルプロバイダーを追加 -> テストメッセージ送信 -> TOTP 回復コードをオフライン保存。'
        OpenWebUI='WebUI を開く'
        OpenAstrBot='AstrBot を開く'
        OpenGuide='インストールガイド'
        OpenReport='インストールレポート'
        Close='閉じる'
        HelpBody="Cyber-Butler インストールオプション`n`nオーナー QQ`nご自身のメイン QQ（オーナー/管理者）で、ボット QQ ではありません。TOTP ラベル、承認/通知ルーティング、YOUR_QQ_ID、オーナー許可リストに使います。ボット QQ は AstrBot/QQ 側で別に設定します。`n`nセキュリティレベル`nHigh：Windows 10/11 x64 + 管理者 + 専用ローカルサービスアカウント。AstrBot/WebUI はサービスとして実行。TOTP 保管庫はエージェントアカウントを拒否。LAN は不可。最も強い分離。`nMedium：現在のデスクトップアカウントと対話型タスク。同一アカウントの TOTP 拒否は強制できません。単一マシン試験向け。`nLight：ACL/監査/TOTP egress を削減。一時的または低価値環境のみ。`nレベルはハードウェア前提を変えません：Windows 10/11 x64、PowerShell 5.1、管理者、Python 3.10–3.13。ローカルモデル：24GB+ は 20–24B、16GB は 7–14B、8GB は 3–7B 量子化、dGPU なしは API のみ。`n`nWebUI バインド`nLoopback：127.0.0.1 のみ。`nTailscale：プライベート tailnet。`nLAN：ローカルネットワーク。High は LAN を拒否。`n`n個人プラグイン`n同梱されません。既存の AstrBot プラグインフォルダーに private_companion（コンパニオンコア）、livingmemory（長期記憶）、memorix（グラフ+ベクトル記憶）が必要です。インストーラーはこの 3 つだけをコピーし、ダウンロードしません。`n`nAPI Key`nこの欄は DeepSeek API Key（sk-...）を含むファイルパスです。他のモデルや OpenAI 互換エンドポイントは AstrBot のプロバイダー設定で追加してください。DeepSeek Key：https://platform.deepseek.com/api_keys 。`n`n承認`nチェック後のみ承認トークンを渡します。GUI が無言で承認することはありません。"
        InstallerLabel='インストーラー：'
        TierHigh='高 (High)'
        TierMedium='中 (Medium)'
        TierLight='低 (Light)'
        BindLoopback='ローカルのみ (Loopback)'
        BindTailscale='Tailscale'
        BindLAN='LAN'
        OpenLaunchGuide='ログインと起動'
        LaunchGuideTitle='ログイン・起動・保守'
    }
    ko = @{
        Title='Cyber-Butler 설치 프로그램'; Subtitle='v1.6.1 · 시각적 설치 프로그램'
        Warning='승인 확인 후에만 승인 토큰을 전달합니다. TOTP는 대화상자에서 확인합니다.'
        InstallPath='설치 경로'; Tier='보안 등급'; OwnerQQ='소유자 QQ'; Bind='WebUI 바인딩'
        PersonalPlugins='개인 플러그인'; ApiKeyFile='API Key 파일 (선택, sk-...)'
        ApiKeyNote='API Key는 이 화면에 저장되지 않습니다.'
        QuickHelp='소유자 QQ: 봇이 아닌 본인의 메인 QQ입니다. 경로, 등급, 바인딩은 여기서 설정하고 개인 플러그인과 API Key는 고급 옵션에 있습니다. 자세한 내용은 도움말을 보세요.'
        Preflight='환경 확인'; Start='설치 시작'; Installing='설치 중...'; Report='보고서 열기'; Exit='종료'; Help='도움말'; Remove='삭제'; Advanced='고급: 개인 플러그인 / API Key'
        PathTip='설치 경로, 기본값 C:\CyberButler.'; TierTip='High: 별도 서비스 계정; Medium: 현재 데스크톱 계정; Light: 낮은 보호.'; OwnerTip='본인의 메인 QQ이며 봇 QQ가 아닙니다.'; BindTip='Loopback: 로컬만; Tailscale: 사설 네트워크; LAN: 네트워크 노출.'; PluginsTip='private_companion, livingmemory, memorix가 포함된 선택 폴더.'; ApiTip='DeepSeek API Key(sk-...) 파일의 선택 경로.'
        Approval='위 내용을 읽고 이 단계를 승인합니다'; NeedApproval='먼저 승인 확인란을 선택하세요.'
        TotpTitle='TOTP 등록'; TotpHint='QR을 스캔하고 복구 코드를 오프라인으로 저장하세요.'; Scanned='QR 스캔 완료'; Recovery='복구 코드 저장 완료'; Confirm='확인 후 계속'; Cancel='취소'; TotpReady='TOTP 자료 준비됨; 확인 대기 중...'; TotpConfirmed='TOTP 확인됨; 서비스 계속...'; Invalid='TOTP 확인이 유효하지 않습니다.'
        Ready='준비됨'; RunningPreflight='환경 확인 중...'; PreflightDone='확인 완료. 승인 후 설치를 시작하세요.'; PreflightFailed='환경 확인 실패'; Starting='설치 프로그램 시작 중...'; Started='설치 프로그램 시작됨'; StartFailed='설치 프로그램을 시작할 수 없습니다'; Admin='관리자 세션 감지됨'; NotAdmin='관리자 권한이 아닙니다'; CloseConfirm='설치가 진행 중입니다. 닫으면 설치 프로그램이 중지되고 불완전한 설치가 남을 수 있습니다. 종료할까요?'; CloseConfirmTitle='설치 종료'; NoReport='보고서 폴더를 찾을 수 없습니다: '
        CheckStatus='상태 확인'
        StatusTitle='설치 상태'
        StatusRunning='설치 프로그램이 실행 중입니다.'
        StatusStalled='프로세스는 있지만 오랫동안 새 출력이 없습니다. 멈췄을 수 있습니다.'
        StatusWaitingTotp='TOTP 확인을 기다리는 중입니다.'
        StatusCompleted='설치가 완료되었습니다.'
        StatusFailed='설치가 실패했습니다.'
        StatusNoActive='실행 중인 설치도 성공 보고서도 없습니다.'
        StatusStage='현재 단계'
        StatusProcess='설치 프로그램 프로세스'
        StatusLastOutput='마지막 출력'
        StatusReport='보고서 상태'
        StatusPorts='서비스 포트'
        StatusStep='단계 진행률'
        StatusStepEta='단계 남은 시간'
        StatusTotalEta='전체 남은 시간'
        StatusElapsed='경과 시간'
        StatusProcessDetail='프로세스 세부 정보'
        StatusTOTP='TOTP 상태'
        StatusLog='로그'
        StatusNote='예상 값은 단계와 로그 활동에 기반한 것이며 보장이 아닙니다.'
        Copy='복사'
        RefreshStatus='새로 고침'
        RemoveTitle='Cyber-Butler 삭제'
        RemoveHint='삭제 범위를 선택하세요. 되돌릴 수 없으며 같은 폴더의 일치하는 ZIP도 삭제됩니다.'
        RemovePackage='설치 프로그램 / 배포 패키지만'
        RemoveProject='C:\CyberButler 프로젝트만'
        RemoveBoth='배포 패키지와 설치 프로젝트 모두'
        Continue='계속'
        RemoveConfirm='서비스를 중지하고 프로젝트를 영구 삭제할까요?'
        RemoveDone='삭제가 완료되었습니다.'
        RemoveFailed='삭제 실패: '
        RemoveConfirm2='2차 확인: 영구 삭제이며 되돌릴 수 없습니다. 진행할까요?'
        RemoveBothDone='프로젝트를 삭제했습니다. 배포 패키지는 GUI 종료 후 삭제됩니다.'
        RemovePackageDone='배포 패키지는 GUI 종료 후 삭제됩니다.'
        RemoveProjectDone='설치된 프로젝트를 삭제했습니다.'
        PostTitle='설치 완료'
        PostSubtitle='세 서비스가 설치되어 실행 중입니다. WebUI를 열고 봇 QQ와 모델 공급자를 설정하세요.'
        PostNext='다음: WebUI 열기 -> 봇 QQ 어댑터 설정 -> 다른 모델 공급자 추가 -> 테스트 메시지 전송 -> TOTP 복구 코드 오프라인 저장.'
        OpenWebUI='WebUI 열기'
        OpenAstrBot='AstrBot 열기'
        OpenGuide='설치 안내'
        OpenReport='설치 보고서'
        Close='닫기'
        HelpBody="Cyber-Butler 설치 옵션`n`n소유자 QQ`n봇 QQ가 아닌 본인의 메인 QQ(소유자/관리자)입니다. TOTP 라벨, 승인/알림 라우팅, YOUR_QQ_ID, 소유자 허용 목록에 사용됩니다. 봇 QQ는 AstrBot/QQ에서 별도로 설정합니다.`n`n보안 등급`nHigh: Windows 10/11 x64 + 관리자 + 전용 로컬 서비스 계정. AstrBot/WebUI는 서비스로 실행. TOTP 보관소는 에이전트 계정을 거부. LAN 금지. 가장 강한 격리.`nMedium: 현재 데스크톱 계정과 대화형 작업. 동일 계정의 TOTP 거부를 강제할 수 없음. 단일 PC 테스트용.`nLight: ACL/감사/TOTP egress 감소. 임시 또는 저가치 환경 전용.`n등급은 하드웨어 기준을 바꾸지 않습니다: Windows 10/11 x64, PowerShell 5.1, 관리자, Python 3.10–3.13. 로컬 모델: 24GB+는 20–24B, 16GB는 7–14B, 8GB는 3–7B 양자화, dGPU 없으면 API 전용.`n`nWebUI 바인딩`nLoopback: 127.0.0.1만.`nTailscale: 사설 tailnet.`nLAN: 로컬 네트워크. High는 LAN 거부.`n`n개인 플러그인`n패키지에 포함되지 않습니다. 기존 AstrBot 플러그인 폴더에 private_companion(컴패니언 코어), livingmemory(장기 기억), memorix(그래프+벡터 기억)가 필요합니다. 설치 프로그램은 이 세 개만 복사하며 다운로드하지 않습니다.`n`nAPI Key`n이 필드는 DeepSeek API Key(sk-...)가 든 파일 경로입니다. 다른 모델이나 OpenAI 호환 엔드포인트는 AstrBot 공급자 설정에서 추가하세요. DeepSeek Key: https://platform.deepseek.com/api_keys .`n`n승인`n체크한 뒤에만 승인 토큰을 전달하며 GUI는 조용히 승인하지 않습니다."
        InstallerLabel='설치 프로그램: '
        TierHigh='높음 (High)'
        TierMedium='보통 (Medium)'
        TierLight='낮음 (Light)'
        BindLoopback='로컬만 (Loopback)'
        BindTailscale='Tailscale'
        BindLAN='LAN'
        OpenLaunchGuide='로그인 및 시작'
        LaunchGuideTitle='로그인, 시작 및 유지 관리'
    }
    ru = @{
        Title='Установщик Cyber-Butler'; Subtitle='v1.6.1 · визуальный установщик'
        Warning='GUI передаёт токены только после явного подтверждения. TOTP подтверждается в диалоге.'
        InstallPath='Путь установки'; Tier='Уровень безопасности'; OwnerQQ='QQ владельца'; Bind='Привязка WebUI'
        PersonalPlugins='Личные плагины'; ApiKeyFile='Файл API Key (необязательно, sk-...)'
        ApiKeyNote='API Key не сохраняются в этом интерфейсе.'
        QuickHelp='QQ владельца: ваш основной QQ, а не бот. Путь, уровень и привязка настраиваются здесь; плагины и API Key — в разделе Дополнительно. Подробности в Справке.'
        Preflight='Проверить окружение'; Start='Начать установку'; Installing='Установка...'; Report='Открыть отчёт'; Exit='Выход'; Help='Справка'; Remove='Удалить'; Advanced='Дополнительно: плагины / API Key'
        PathTip='Каталог установки, по умолчанию C:\CyberButler.'; TierTip='High: отдельная служебная учётная запись; Medium: текущая; Light: меньше защиты.'; OwnerTip='Ваш основной QQ, а не QQ бота.'; BindTip='Loopback: только локально; Tailscale: частная сеть; LAN: сеть.'; PluginsTip='Необязательная папка с private_companion, livingmemory и memorix.'; ApiTip='Необязательный путь к файлу ключа DeepSeek (sk-...).'
        Approval='Я прочитал примечания и одобряю эти шаги'; NeedApproval='Сначала установите флажок одобрения.'
        TotpTitle='Регистрация TOTP'; TotpHint='Отсканируйте QR и сохраните коды восстановления офлайн.'; Scanned='QR отсканирован'; Recovery='Коды сохранены'; Confirm='Подтвердить и продолжить'; Cancel='Отмена'; TotpReady='Материал TOTP готов; ожидание подтверждения...'; TotpConfirmed='TOTP подтверждён; продолжаем службы...'; Invalid='Неверное подтверждение TOTP.'
        Ready='Готово.'; RunningPreflight='Проверка окружения...'; PreflightDone='Проверка завершена. Подтвердите и затем начните установку.'; PreflightFailed='Ошибка проверки.'; Starting='Запуск установщика...'; Started='Установщик запущен.'; StartFailed='Не удалось запустить установщик.'; Admin='Обнаружена сессия администратора.'; NotAdmin='GUI запущен без прав администратора.'; CloseConfirm='Идёт установка. Закрытие остановит установщик и может оставить неполную установку. Завершить?'; CloseConfirmTitle='Завершить установку'; NoReport='Каталог отчётов не найден: '
        CheckStatus='Проверить статус'
        StatusTitle='Статус установки'
        StatusRunning='Установщик работает.'
        StatusStalled='Процесс существует, но давно нет нового вывода; возможно, он завис.'
        StatusWaitingTotp='Ожидание подтверждения TOTP.'
        StatusCompleted='Установка завершена.'
        StatusFailed='Установка не удалась.'
        StatusNoActive='Нет активной установки и успешного отчёта.'
        StatusStage='Текущий этап'
        StatusProcess='Процесс установщика'
        StatusLastOutput='Последний вывод'
        StatusReport='Статус отчёта'
        StatusPorts='Порты служб'
        StatusStep='Прогресс шага'
        StatusStepEta='Осталось на шаг'
        StatusTotalEta='Общее оставшееся время'
        StatusElapsed='Прошло'
        StatusProcessDetail='Сведения о процессе'
        StatusTOTP='Статус TOTP'
        StatusLog='Журнал'
        StatusNote='Оценки основаны на этапе и активности журнала; это не гарантия.'
        Copy='Копировать'
        RefreshStatus='Обновить'
        RemoveTitle='Удалить Cyber-Butler'
        RemoveHint='Выберите объём удаления. Действие необратимо; подходящий ZIP в той же папке тоже будет удалён.'
        RemovePackage='Только установщик / пакет выпуска'
        RemoveProject='Только проект C:\CyberButler'
        RemoveBoth='Пакет выпуска и установленный проект'
        Continue='Продолжить'
        RemoveConfirm='Остановить службы и навсегда удалить проект?'
        RemoveDone='Удаление завершено.'
        RemoveFailed='Ошибка удаления: '
        RemoveConfirm2='Второе подтверждение: удалить навсегда и безвозвратно?'
        RemoveBothDone='Проект удалён; пакет будет удалён после закрытия GUI.'
        RemovePackageDone='Пакет будет удалён после закрытия GUI.'
        RemoveProjectDone='Установленный проект удалён.'
        PostTitle='Установка завершена'
        PostSubtitle='Три службы установлены и запущены. Откройте WebUI и настройте QQ бота и провайдера моделей.'
        PostNext='Далее: открыть WebUI -> настроить адаптер QQ бота -> добавить провайдеров -> отправить тестовое сообщение -> сохранить коды TOTP офлайн.'
        OpenWebUI='Открыть WebUI'
        OpenAstrBot='Открыть AstrBot'
        OpenGuide='Руководство по установке'
        OpenReport='Отчёт установки'
        Close='Закрыть'
        HelpBody="Параметры установщика Cyber-Butler`n`nQQ владельца`nВаш основной QQ (владелец/администратор), а не QQ бота. Используется для метки TOTP, маршрутизации одобрений/уведомлений, YOUR_QQ_ID и списка владельцев. QQ бота настраивается отдельно в AstrBot/QQ.`n`nУровень безопасности`nHigh: Windows 10/11 x64 + администратор + отдельная локальная служебная учётная запись; AstrBot/WebUI как службы; хранилище TOTP запрещает учётной записи агента; LAN запрещён; максимальная изоляция.`nMedium: текущая учётная запись рабочего стола с интерактивными задачами; запрет TOTP для той же учётной записи невозможен; для тестов на одной машине.`nLight: сокращённые ACL/аудит/TOTP egress; только временные или малые среды.`nУровень не меняет аппаратную базу: Windows 10/11 x64, PowerShell 5.1, администратор, Python 3.10–3.13. Локальная модель: 24GB+ для 20–24B, 16GB для 7–14B, 8GB для 3–7B квант., без dGPU только API.`n`nПривязка WebUI`nLoopback: только 127.0.0.1.`nTailscale: частный tailnet.`nLAN: локальная сеть; High запрещает LAN.`n`nЛичные плагины`nНе входят в пакет. Нужна существующая папка AstrBot с private_companion (ядро компаньона), livingmemory (долговременная память) и memorix (граф+вектор). Установщик копирует только эти три и ничего не скачивает.`n`nAPI Key`nПоле ожидает путь к файлу с ключом DeepSeek (sk-...). Другие модели или OpenAI-совместимые endpoint настраиваются в провайдерах AstrBot. Ключ DeepSeek: https://platform.deepseek.com/api_keys .`n`nОдобрение`nТокены передаются только после отметки; GUI никогда не одобряет молча."
        InstallerLabel='Установщик: '
        TierHigh='Высокий (High)'
        TierMedium='Средний (Medium)'
        TierLight='Низкий (Light)'
        BindLoopback='Только локально (Loopback)'
        BindTailscale='Tailscale'
        BindLAN='LAN'
        OpenLaunchGuide='Вход и запуск'
        LaunchGuideTitle='Вход, запуск и обслуживание'
    }
}

$script:LaunchGuides = @{}
try {
    $guideFile = Join-Path $installerRoot 'lib\launch-guide.json'
    if (Test-Path -LiteralPath $guideFile) {
        $guideData = Get-Content -LiteralPath $guideFile -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($property in $guideData.PSObject.Properties) { $script:LaunchGuides[[string]$property.Name] = [string]$property.Value }
    }
} catch { }

function Get-LaunchGuideText {
    $langs = @('zh', 'en', 'de', 'es', 'fr', 'ja', 'ko', 'ru')
    $index = [Math]::Max(0, [Math]::Min($langs.Count - 1, [int]$languageBox.SelectedIndex))
    $text = $script:LaunchGuides[$langs[$index]]
    if ([string]::IsNullOrWhiteSpace([string]$text)) { $text = $script:LaunchGuides['en'] }
    return [string]$text
}

function Get-UiText([string]$key) {
    $langs = @('zh', 'en', 'de', 'es', 'fr', 'ja', 'ko', 'ru')
    $index = [Math]::Max(0, [Math]::Min($langs.Count - 1, [int]$languageBox.SelectedIndex))
    $lang = $langs[$index]
    $value = $script:UiText[$lang][$key]
    if ([string]::IsNullOrWhiteSpace([string]$value)) { $value = $script:UiText['en'][$key] }
    return [string]$value
}

function Get-EmailHelpText {
    $langs = @('zh', 'en', 'de', 'es', 'fr', 'ja', 'ko', 'ru')
    $index = [Math]::Max(0, [Math]::Min($langs.Count - 1, [int]$languageBox.SelectedIndex))
    $lang = $langs[$index]
    $text = $script:EmailHelpText[$lang]
    if ([string]::IsNullOrWhiteSpace([string]$text)) { $text = $script:EmailHelpText['en'] }
    return [string]$text
}

$script:EmailHelpText = @{
    zh = "WebUI 邮箱 / SMTP 详细说明`n`nCBS WebUI 8765 使用管理员邮箱 + 邮件验证码；AstrBot 6185 使用用户名/密码。`n`nWebUI 邮箱：管理员登录 CBS WebUI、接收 TOTP 审批和告警的邮箱；不是机器人 QQ。`nSMTP host：邮箱服务商的发信服务器，例如 163 用 smtp.163.com，Gmail 用 smtp.gmail.com。`nSMTP port：当前邮件组件使用隐式 SSL，必须填 465；587/STARTTLS 暂不支持。`nSMTP 授权码：服务商生成的应用授权码/应用专用密码，不是邮箱登录密码；安装器用 DPAPI 加密保存。`nSMTP 用户：通常与管理员邮箱相同。`n`n如何找到：`n163：登录 mail.163.com -> 设置 -> POP3/SMTP/IMAP -> 开启 SMTP -> 生成授权码。`nGmail：Google 账户 -> 安全性 -> 两步验证 -> 应用专用密码。`nOutlook/其他：在邮箱账户设置的 SMTP/IMAP 页面生成应用密码或授权码。`n`n缺失时 WebUI 显示红色 Banner，Broker 邮件审批返回 503。当前版本邮件审批的 IMAP 默认是 163；非 163 邮箱请先确认 SMTP 和 IMAP 都可用。"
    en = "WebUI email / SMTP details`n`nCBS WebUI 8765 uses an administrator email + email OTP; AstrBot 6185 uses username/password.`n`nWebUI email: administrator mailbox for CBS login and TOTP/alert mail; not the bot QQ.`nSMTP host: provider outgoing server, e.g. smtp.163.com for 163, smtp.gmail.com for Gmail.`nSMTP port: this build uses implicit SSL, so use 465; 587/STARTTLS is not supported yet.`nSMTP auth code: provider app password/authorization code, not your mailbox login password; stored encrypted with DPAPI.`nSMTP user: usually the same address as WebUI email.`n`nWhere to find it:`n163: mail.163.com -> Settings -> POP3/SMTP/IMAP -> enable SMTP -> generate authorization code.`nGmail: Google Account -> Security -> 2-Step Verification -> App passwords.`nOutlook/others: account security or SMTP/IMAP settings -> app password/authorization code.`n`nIf missing: red WebUI banner and Broker email approval HTTP 503. This build defaults email-approval IMAP to 163; for other providers verify both SMTP and IMAP."
    de = "WebUI-E-Mail / SMTP – Details`n`nCBS WebUI 8765 nutzt Admin-E-Mail + E-Mail-OTP; AstrBot 6185 nutzt Benutzername/Passwort.`nWebUI email: Admin-Postfach für Login und TOTP-/Warnmails, nicht die Bot-QQ.`nSMTP host: Postausgangsserver, z. B. smtp.163.com oder smtp.gmail.com.`nSMTP port: dieser Build nutzt implizites SSL, also 465; 587/STARTTLS wird nicht unterstützt.`nSMTP auth code: App-Passwort/Autorisierungscode, nicht das Login-Passwort; DPAPI-verschlüsselt.`nSMTP user: normalerweise dieselbe Adresse.`n`n163: mail.163.com -> Einstellungen -> POP3/SMTP/IMAP -> SMTP aktivieren -> Autorisierungscode.`nGmail: Google-Konto -> Sicherheit -> 2-Faktor -> App-Passwörter.`nOutlook/andere: SMTP/IMAP-Einstellungen -> App-Passwort.`n`nFehlt die Konfiguration: rotes Banner und Broker HTTP 503. IMAP für Mail-Freigaben ist hier standardmäßig 163."
    es = "Correo WebUI / SMTP: detalles`n`nCBS WebUI 8765 usa correo de administrador + OTP; AstrBot 6185 usa usuario/contraseña.`nWebUI email: buzón del administrador para login y avisos TOTP, no el QQ del bot.`nSMTP host: servidor de salida, p. ej. smtp.163.com o smtp.gmail.com.`nSMTP port: esta versión usa SSL implícito, use 465; 587/STARTTLS no está soportado.`nSMTP auth code: contraseña de aplicación/código de autorización, no la contraseña del correo; cifrado DPAPI.`nSMTP user: normalmente la misma dirección.`n`n163: mail.163.com -> Configuración -> POP3/SMTP/IMAP -> activar SMTP -> generar código.`nGmail: Cuenta de Google -> Seguridad -> Verificación en dos pasos -> Contraseñas de aplicación.`nOutlook/otros: ajustes SMTP/IMAP -> contraseña de aplicación.`n`nSi falta: banner rojo y Broker HTTP 503. La parte IMAP de aprobación usa 163 por defecto."
    fr = "E-mail WebUI / SMTP : détails`n`nCBS WebUI 8765 utilise un e-mail administrateur + OTP ; AstrBot 6185 utilise un nom d’utilisateur/mot de passe.`nWebUI email : boîte admin pour la connexion et les alertes TOTP, pas le QQ du bot.`nSMTP host : serveur d’envoi, par ex. smtp.163.com ou smtp.gmail.com.`nSMTP port : cette version utilise SSL implicite, donc 465 ; 587/STARTTLS non pris en charge.`nSMTP auth code : mot de passe d’application/code d’autorisation, pas le mot de passe de connexion ; chiffré DPAPI.`nSMTP user : normalement la même adresse.`n`n163 : mail.163.com -> Paramètres -> POP3/SMTP/IMAP -> activer SMTP -> code d’autorisation.`nGmail : Compte Google -> Sécurité -> Validation en deux étapes -> Mots de passe d’application.`nOutlook/autres : réglages SMTP/IMAP -> mot de passe d’application.`n`nSi absent : bandeau rouge et Broker HTTP 503. L’IMAP des approbations est 163 par défaut."
    ja = "WebUI メール / SMTP の詳細`n`nCBS WebUI 8765 は管理者メール + メール OTP、AstrBot 6185 はユーザー名/パスワードです。`nWebUI email: CBS ログインと TOTP/アラート用の管理者メール。ボット QQ ではありません。`nSMTP host: 送信サーバー。163 は smtp.163.com、Gmail は smtp.gmail.com。`nSMTP port: このビルドは暗黙 SSL のため 465。587/STARTTLS は未対応です。`nSMTP auth code: プロバイダーのアプリパスワード/認証コード。ログインパスワードではありません。DPAPI で暗号化。`nSMTP user: 通常は WebUI email と同じアドレス。`n`n163: mail.163.com -> 設定 -> POP3/SMTP/IMAP -> SMTP 有効化 -> 認証コード生成。`nGmail: Google アカウント -> セキュリティ -> 2 段階認証 -> アプリ パスワード。`nOutlook/その他: SMTP/IMAP 設定 -> アプリ パスワード。`n`n未設定だと赤いバナーと Broker HTTP 503。メール承認の IMAP は既定で 163 です。"
    ko = "WebUI 이메일 / SMTP 상세`n`nCBS WebUI 8765는 관리자 이메일 + 이메일 OTP, AstrBot 6185는 사용자 이름/비밀번호를 사용합니다.`nWebUI email: CBS 로그인과 TOTP/알림용 관리자 메일. 봇 QQ가 아닙니다.`nSMTP host: 발신 서버. 163은 smtp.163.com, Gmail은 smtp.gmail.com.`nSMTP port: 이 빌드는 암시적 SSL이라 465. 587/STARTTLS 미지원.`nSMTP auth code: 공급자 앱 비밀번호/인증 코드. 로그인 비밀번호가 아니며 DPAPI로 암호화됩니다.`nSMTP user: 보통 WebUI email과 같은 주소.`n`n163: mail.163.com -> 설정 -> POP3/SMTP/IMAP -> SMTP 활성화 -> 인증 코드 생성.`nGmail: Google 계정 -> 보안 -> 2단계 인증 -> 앱 비밀번호.`nOutlook/기타: SMTP/IMAP 설정 -> 앱 비밀번호.`n`n없으면 빨간 배너와 Broker HTTP 503. 메일 승인 IMAP 기본값은 163입니다."
    ru = "WebUI email / SMTP: подробности`n`nCBS WebUI 8765 использует почту администратора + OTP; AstrBot 6185 — логин/пароль.`nWebUI email: почта администратора для входа и TOTP/оповещений, не QQ бота.`nSMTP host: сервер исходящей почты, например smtp.163.com или smtp.gmail.com.`nSMTP port: в этой сборке неявный SSL, поэтому 465; 587/STARTTLS не поддерживается.`nSMTP auth code: пароль приложения/код авторизации, не пароль входа; шифруется DPAPI.`nSMTP user: обычно тот же адрес.`n`n163: mail.163.com -> Настройки -> POP3/SMTP/IMAP -> включить SMTP -> создать код.`nGmail: аккаунт Google -> Безопасность -> 2FA -> пароли приложений.`nOutlook/другие: настройки SMTP/IMAP -> пароль приложения.`n`nЕсли не задано: красный баннер и Broker HTTP 503. IMAP для подтверждений по умолчанию 163."
}

function Show-CyberButlerHelp {
    $helpXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Cyber-Butler Help" Width="760" Height="620"
        WindowStartupLocation="CenterOwner" Background="#0F172A">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Text="Cyber-Butler Help" Foreground="#F8FAFC" FontSize="22" FontWeight="SemiBold"/>
    <TextBox x:Name="HelpBox" Grid.Row="1" IsReadOnly="True" AcceptsReturn="True"
             VerticalScrollBarVisibility="Auto" HorizontalScrollBarVisibility="Disabled"
             TextWrapping="Wrap" Background="#020617" Foreground="#CBD5E1"
             BorderBrush="#1E293B" Padding="12" Margin="0,14,0,14"/>
    <Button x:Name="CloseHelp" Grid.Row="2" Content="Close / 关闭" Width="120" Height="34"
            HorizontalAlignment="Right" Background="#0EA5E9" Foreground="#FFFFFF"
            BorderBrush="#0EA5E9"/>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$helpXaml)
    $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    $box = $dialog.FindName('HelpBox')
    $box.Text = (Get-UiText 'HelpBody') + "`n`n" + (Get-EmailHelpText)
    $dialog.FindName('CloseHelp').Add_Click({ $dialog.Close() })
    $dialog.ShowDialog() | Out-Null
}

function Get-PostNextDetails {
    $langs = @('zh', 'en', 'de', 'es', 'fr', 'ja', 'ko', 'ru')
    $index = [Math]::Max(0, [Math]::Min($langs.Count - 1, [int]$languageBox.SelectedIndex))
    $path = Join-Path $installerRoot 'lib\post-next-details.json'
    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        $lines = $data.($langs[$index])
        if ($null -eq $lines) { $lines = $data.en }
        return @($lines)
    } catch {
        return @('AstrBot setup: open http://127.0.0.1:6185/ and configure an OneBot v11 platform with reverse WebSocket 127.0.0.1:6199.')
    }
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
    $defenderExclusionCheck.Content = Get-UiText 'DefenderExclusion'
    $defenderHint.Text = Get-UiText 'DefenderHint'
    $advancedExpander.Header = Get-UiText 'Advanced'
    $quickHelp.Text = Get-UiText 'QuickHelp'
    $installerLabel.Text = Get-UiText 'InstallerLabel'
    if ($tierBox.Items.Count -ge 3) {
        $tierBox.Items[0].Content = Get-UiText 'TierHigh'
        $tierBox.Items[1].Content = Get-UiText 'TierMedium'
        $tierBox.Items[2].Content = Get-UiText 'TierLight'
    }
    if ($bindBox.Items.Count -ge 3) {
        $bindBox.Items[0].Content = Get-UiText 'BindLoopback'
        $bindBox.Items[1].Content = Get-UiText 'BindTailscale'
        $bindBox.Items[2].Content = Get-UiText 'BindLAN'
    }
    $installPathBox.ToolTip = Get-UiText 'PathTip'
    $tierBox.ToolTip = Get-UiText 'TierTip'
    $ownerQQBox.ToolTip = Get-UiText 'OwnerTip'
    $bindBox.ToolTip = Get-UiText 'BindTip'
    $personalPluginsBox.ToolTip = Get-UiText 'PluginsTip'
    $apiKeyFileBox.ToolTip = Get-UiText 'ApiTip'
    if ($script:StatusState -eq 'preflight_done') {
        $statusText.Text = Get-UiText 'PreflightDone'
    } elseif ($script:StatusState -eq 'preflight_failed') {
        $statusText.Text = Get-UiText 'PreflightFailed'
    } elseif ($script:StatusState -eq 'preflight_running') {
        $statusText.Text = Get-UiText 'RunningPreflight'
    } elseif ($statusText.Text -eq '' -or $statusText.Text -eq 'Ready.' -or $statusText.Text -eq '就绪。') {
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
    $startButton.Content = if ($Busy) { Get-UiText 'Installing' } else { Get-UiText 'Start' }
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


function Get-GuiReportPath {
    $candidates = @(
        (Join-Path $env:ProgramData 'CyberButler\installer-report\install-report.json'),
        'C:\CyberButler\installer-report\install-report.json'
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }
    return $candidates[0]
}

function Get-GuiInstallStatusText {
    $reportPath = Get-GuiReportPath
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

    if ($elapsedSec -eq 0 -and $script:cbGuiStartTime) { $elapsedSec = [int]((Get-Date) - $script:cbGuiStartTime).TotalSeconds }
    $lastText = 'no log'
    $ageSeconds = $null
    $tail = @()
    if ($script:cbGuiLogPath -and (Test-Path -LiteralPath $script:cbGuiLogPath)) {
        try {
            $last = Get-Item -LiteralPath $script:cbGuiLogPath
            $lastText = $last.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
            $ageSeconds = [int]((Get-Date) - $last.LastWriteTime).TotalSeconds
            $tail = @(Get-Content -LiteralPath $script:cbGuiLogPath -Tail 60 -ErrorAction SilentlyContinue | ForEach-Object { Get-CyberButlerSafeLogLine ([string]$_) } | Select-Object -Last 12)
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
    $stageStartedAt = $script:GuiStageStartedAt
    if (-not $stageStartedAt -and $script:cbGuiStartTime) { $stageStartedAt = $script:cbGuiStartTime }
    if (-not $stageStartedAt -and $script:cbGuiProcess) {
        try { $stageStartedAt = $script:cbGuiProcess.StartTime } catch { }
    }
    $stageElapsed = if ($stageStartedAt) { [int]((Get-Date) - $stageStartedAt).TotalSeconds } else { 0 }
    $stageStart = 0; $stageEnd = 10; $stageNominal = 60
    if ($percent -ge 10 -and $percent -lt 25) { $stageStart = 10; $stageEnd = 25; $stageNominal = 120 }
    elseif ($percent -ge 25 -and $percent -lt 45) { $stageStart = 25; $stageEnd = 45; $stageNominal = 300 }
    elseif ($percent -ge 45 -and $percent -lt 55) { $stageStart = 45; $stageEnd = 55; $stageNominal = 60 }
    elseif ($percent -ge 55 -and $percent -lt 65) { $stageStart = 55; $stageEnd = 65; $stageNominal = 30 }
    elseif ($percent -ge 65 -and $percent -lt 75) { $stageStart = 65; $stageEnd = 75; $stageNominal = 180 }
    elseif ($percent -ge 75 -and $percent -lt 95) { $stageStart = 75; $stageEnd = 95; $stageNominal = 120 }
    elseif ($percent -ge 95) { $stageStart = 95; $stageEnd = 100; $stageNominal = 30 }
    $stepPercent = 100
    if ($stageNominal -gt 0) {
        $stepPercent = [Math]::Max(0, [Math]::Min(99, [int](($stageElapsed / $stageNominal) * 100)))
    }
    if ($stage -match 'pip') {
        if ($logText -match 'Successfully installed') { $stepPercent = 100 }
        elseif ($logText -match 'Installing collected packages') { $stepPercent = [Math]::Max($stepPercent, 70) }
    }
    if ($totpReady -and -not $totpConfirmed) {
        $percent = [Math]::Max($percent, 65)
        $stage = 'TOTP: waiting for confirmation'
        $stageStart = 65; $stageEnd = 75; $stageNominal = 0; $stepPercent = 100
    }
    $stepRemaining = if ($stageNominal -gt 0) { [Math]::Max(0, [int]($stageNominal - $stageElapsed)) } else { 0 }
    $nominalStages = @(60, 120, 300, 60, 30, 180, 120, 30)
    $stageIndex = 0
    if ($percent -ge 95) { $stageIndex = 7 }
    elseif ($percent -ge 75) { $stageIndex = 6 }
    elseif ($percent -ge 65) { $stageIndex = 5 }
    elseif ($percent -ge 55) { $stageIndex = 4 }
    elseif ($percent -ge 45) { $stageIndex = 3 }
    elseif ($percent -ge 25) { $stageIndex = 2 }
    elseif ($percent -ge 10) { $stageIndex = 1 }
    $laterRemaining = 0
    for ($i = $stageIndex + 1; $i -lt $nominalStages.Count; $i++) { $laterRemaining += [int]$nominalStages[$i] }
    $totalRemaining = [int]($stepRemaining + $laterRemaining)
    if ($totpReady -and -not $totpConfirmed) { $totalRemaining = $null }
    if ($reportStatus -eq 'success') {
        $percent = 100; $stage = 'complete'; $stepPercent = 100; $stepRemaining = 0; $totalRemaining = 0
    }

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
    return ($lines -join "`n")
}

function Show-GuiInstallStatus {
    $text = Get-GuiInstallStatusText
    Show-CyberButlerStatusWindow -Owner $window -Title (Get-UiText 'StatusTitle') -Text $text -Copy (Get-UiText 'Copy') -Close (Get-UiText 'Close') -Refresh (Get-UiText 'RefreshStatus') -RefreshScript { Get-GuiInstallStatusText }
}

function Show-GuiCompletionIfReady {
    if ($script:GuiCompletionShown) { return }
    $reportPath = Get-GuiReportPath
    $status = ''
    $failure = ''
    if (Test-Path -LiteralPath $reportPath) {
        try {
            $raw = Get-Content -LiteralPath $reportPath -Raw
            $m = [regex]::Match($raw, '"status"\s*:\s*"([^"]+)"')
            if ($m.Success) { $status = $m.Groups[1].Value }
            $f = [regex]::Match($raw, '"failure"\s*:\s*\{[^\}]*?"message"\s*:\s*"([^"]+)"', [Text.RegularExpressions.RegexOptions]::Singleline)
            if ($f.Success) { $failure = $f.Groups[1].Value.Replace('\n', "`n") }
        } catch { }
    }
    if ($status -eq 'success') {
        $script:GuiCompletionShown = $true
        if ($script:GuiCompletionTimer) { $script:GuiCompletionTimer.Stop() }
        Set-GuiBusy $false
        $installProgress.Value = 100
        $postText = @{
            PostTitle = Get-UiText 'PostTitle'
            PostSubtitle = Get-UiText 'PostSubtitle'
            PostNext = Get-UiText 'PostNext'
            PostNextDetailed = (Get-PostNextDetails)
            OpenWebUI = Get-UiText 'OpenWebUI'
            OpenAstrBot = Get-UiText 'OpenAstrBot'
            OpenGuide = Get-UiText 'OpenGuide'
            OpenReport = Get-UiText 'OpenReport'
            Close = Get-UiText 'Close'
        }
        $guidePath = Join-Path (Split-Path -Parent $installerRoot) 'README-INSTALL.md'
        try {
            Show-CyberButlerPostInstallWindow -Owner $window -InstallPath $script:GuiInstallPath `
                -ReportPath $reportPath -GuidePath $guidePath -Text $postText
        } catch {
            [System.Windows.MessageBox]::Show(
                ("Installation completed.`n`nReport: " + $reportPath),
                (Get-UiText 'Title')) | Out-Null
        }
    } elseif ($status -eq 'failed') {
        $script:GuiCompletionShown = $true
        if ($script:GuiCompletionTimer) { $script:GuiCompletionTimer.Stop() }
        Set-GuiBusy $false
        $message = "Installation failed.`n`nReport: $reportPath"
        if ($failure) { $message += "`n`nFailure: $failure" }
        [System.Windows.MessageBox]::Show($message, (Get-UiText 'Title')) | Out-Null
    } elseif ($script:GuiInstallProcess -and $script:GuiInstallProcess.HasExited) {
        if (-not $script:GuiExitNoticeAt) { $script:GuiExitNoticeAt = Get-Date }
        if (((Get-Date) - $script:GuiExitNoticeAt).TotalSeconds -ge 5) {
            $script:GuiCompletionShown = $true
            if ($script:GuiCompletionTimer) { $script:GuiCompletionTimer.Stop() }
            Set-GuiBusy $false
            $stateRoot = Join-Path $env:ProgramData 'CyberButler\installer\state'
            [System.Windows.MessageBox]::Show(
                ("Installer exited without a completion report.`n`nReport: " + $reportPath + "`nState: " + $stateRoot + "`n`nOpen the status window for the latest log tail."),
                (Get-UiText 'Title')) | Out-Null
        }
    }
}

function Remove-CyberButlerServiceAccountProfile {
    $name = 'CyberButlerSvc'
    $current = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($current.EndsWith('\' + $name, [StringComparison]::OrdinalIgnoreCase)) {
        return [pscustomobject]@{ removed = $false; reason = 'refusing to remove the currently logged-on service account' }
    }
    $user = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    $profilePath = Join-Path $env:SystemDrive ('Users\' + $name)
    if (-not $user -and -not (Test-Path -LiteralPath $profilePath)) {
        return [pscustomobject]@{ removed = $false; reason = 'service account/profile not present' }
    }
    $errors = New-Object System.Collections.Generic.List[string]

    # The profile may still be loaded by the service account even after the
    # project tasks were removed. Kill only processes whose executable or
    # command line is inside this exact profile, never the interactive user.
    foreach ($item in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        $exe = [string]$item.ExecutablePath
        $cmd = [string]$item.CommandLine
        if (($exe -and $exe.StartsWith($profilePath, [StringComparison]::OrdinalIgnoreCase)) -or
            ($cmd -and $cmd.IndexOf($profilePath, [StringComparison]::OrdinalIgnoreCase) -ge 0)) {
            try { & taskkill.exe /PID $item.ProcessId /T /F 2>$null | Out-Null } catch { }
        }
    }
    Start-Sleep -Seconds 3

    if ($user) {
        try { Remove-LocalUser -Name $name -ErrorAction Stop }
        catch { $errors.Add('user: ' + $_.Exception.Message) }
    }
    $profileRemoved = $false
    for ($attempt = 1; $attempt -le 6; $attempt++) {
        try {
            $profile = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
                Where-Object { $_.LocalPath -and ([string]$_.LocalPath).TrimEnd('\') -ieq $profilePath.TrimEnd('\') } |
                Select-Object -First 1
            if ($profile) { Remove-CimInstance -InputObject $profile -ErrorAction Stop }
            $profileRemoved = $true
            break
        } catch {
            $errors.Add('profile try ' + $attempt + ': ' + $_.Exception.Message)
            Start-Sleep -Seconds 3
        }
    }
    if (-not $profileRemoved -and (Test-Path -LiteralPath $profilePath)) {
        # The profile is still loaded. Schedule a one-time cleanup for the next
        # reboot instead of forcibly deleting a live Windows profile. This
        # never touches the interactive CBS profile.
        try {
            $cleanupDir = Join-Path $env:WINDIR 'Temp'
            $cleanupScript = Join-Path $cleanupDir 'CyberButler-svc-profile-cleanup.ps1'
            @'
$name = 'CyberButlerSvc'
$profilePath = Join-Path $env:SystemDrive ('Users\' + $name)
$profile = Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
    Where-Object { $_.LocalPath -and ([string]$_.LocalPath).TrimEnd('\') -ieq $profilePath.TrimEnd('\') } |
    Select-Object -First 1
if ($profile) { Remove-CimInstance -InputObject $profile -ErrorAction SilentlyContinue }
Get-LocalUser -Name $name -ErrorAction SilentlyContinue | Remove-LocalUser -ErrorAction SilentlyContinue
if (Test-Path -LiteralPath $profilePath) { Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction SilentlyContinue }
Remove-Item -LiteralPath $PSCommandPath -Force -ErrorAction SilentlyContinue
'@ | Set-Content -LiteralPath $cleanupScript -Encoding UTF8
            $runOnce = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce'
            New-Item -Path $runOnce -Force | Out-Null
            Set-ItemProperty -Path $runOnce -Name 'CyberButlerSvcProfileCleanup' `
                -Value ('powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $cleanupScript + '"')
            $errors.Add('profile still loaded; cleanup scheduled for next reboot')
        } catch { $errors.Add('schedule: ' + $_.Exception.Message) }
    } elseif (Test-Path -LiteralPath $profilePath) {
        try { Remove-Item -LiteralPath $profilePath -Recurse -Force -ErrorAction Stop }
        catch { $errors.Add('folder: ' + $_.Exception.Message) }
    }
    $still = (Get-LocalUser -Name $name -ErrorAction SilentlyContinue) -or (Test-Path -LiteralPath $profilePath)
    return [pscustomobject]@{
        removed = (-not $still)
        pending_reboot = ($still -and (Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce' -Name 'CyberButlerSvcProfileCleanup' -ErrorAction SilentlyContinue))
        reason = ($errors -join '; ')
    }
}

function Show-CyberButlerRemoveProgress {
    param($Owner)
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Cyber-Butler Uninstall" Width="620" Height="210"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize"
        WindowStyle="ToolWindow" ShowInTaskbar="False" Background="#0F172A">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock x:Name="RemoveTitle" Text="正在删除 Cyber-Butler / Uninstalling" Foreground="#F8FAFC" FontSize="18" FontWeight="SemiBold"/>
    <ProgressBar x:Name="RemoveBar" Grid.Row="1" Height="18" Minimum="0" Maximum="100" Value="0" Margin="0,18,0,8" Foreground="#0EA5E9" Background="#1E293B"/>
    <TextBlock x:Name="RemoveDetail" Grid.Row="2" Text="准备开始…" Foreground="#94A3B8" FontSize="12" TextWrapping="Wrap"/>
  </Grid>
</Window>
'@
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dialog = [System.Windows.Markup.XamlReader]::Load($reader)
    if ($Owner) { $dialog.Owner = $Owner }
    $dialog.Show() | Out-Null
    return [pscustomobject]@{
        Window = $dialog
        Bar = $dialog.FindName('RemoveBar')
        Detail = $dialog.FindName('RemoveDetail')
    }
}

function Update-CyberButlerRemoveProgress($Progress, [double]$Percent, [string]$Message) {
    if ($null -eq $Progress) { return }
    try {
        $Progress.Bar.Value = [Math]::Max(0, [Math]::Min(100, $Percent))
        $Progress.Detail.Text = $Message
        $Progress.Window.Dispatcher.Invoke([Action]{}, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
    } catch { }
}

function Remove-CyberButlerGuiInstall([string]$Root, [scriptblock]$OnProgress = $null) {
    $full = [IO.Path]::GetFullPath($Root).TrimEnd([char]92)
    $report = { param($pct, $msg) if ($OnProgress) { & $OnProgress $pct $msg } }
    & $report 2 ('准备删除 / Preparing: ' + $full)
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
    $markers = @('VERSION', 'AstrBot', 'webui', 'tools', 'SnowLuma', 'installer-report', '.cbs-install-root')
    $hasMarker = $false
    foreach ($marker in $markers) {
        if (Test-Path -LiteralPath (Join-Path $full $marker)) { $hasMarker = $true; break }
    }
    # A failed install may have no complete marker set. The default root is
    # still safe to remove; arbitrary user folders remain refused.
    if (-not $hasMarker -and ([IO.Path]::GetFileName($full) -notmatch '(?i)cyber.?butler')) {
        throw ('Refusing to remove non-Cyber-Butler directory: missing install markers at ' + $full)
    }

    $taskNames = @('AstrBot Service', 'AstrBot TOTP Broker', 'Cyber-Butler Web UI Services', 'Cyber-Butler OTP Mailer', 'SnowLuma Startup', 'Cyber-Butler WFP Guard', 'Cyber-Butler Broker Watchdog')
    $env:CBS_IS_UNINSTALLING = '1'
    try {
        $markerDir = Join-Path $env:ProgramData 'CyberButler'
        New-Item -ItemType Directory -Path $markerDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $markerDir 'uninstalling.marker') -Value '1' -Encoding ASCII
    } catch {
        & $report 1 ('无法写入卸载标记 / Cannot write uninstall marker: ' + $_.Exception.Message)
    }
    & $report 5 '停止计划任务 / Stopping scheduled tasks'
    foreach ($taskName in $taskNames) {
        $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        if ($task) {
            Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
        }
    }
    & $report 8 '断开 WFP 出站规则 / Removing WFP egress rules'
    try {
        Get-NetFirewallRule -DisplayName 'CBS-Agent-Egress*' -ErrorAction SilentlyContinue |
            Remove-NetFirewallRule -ErrorAction Stop
    } catch {
        & $report 8 ('WFP 规则删除失败 / WFP rule removal failed: ' + $_.Exception.Message)
    }
    & $report 12 '计划任务已停止 / Scheduled tasks stopped'

    # Stop every process whose executable or command line belongs to this
    # install, including AstrBot, OTP Mailer, Broker, WebUI, SnowLuma and its
    # guardian. Port checks alone missed SnowLuma (5099/3000/3001) and 8766.
    $portSet = @(6185, 18090, 8765, 8766, 5099, 3000, 3001)
    $pids = New-Object System.Collections.Generic.HashSet[int]
    foreach ($port in $portSet) {
        foreach ($conn in @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) {
            if ($conn.OwningProcess) { [void]$pids.Add([int]$conn.OwningProcess) }
        }
    }
    foreach ($item in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        $cmd = [string]$item.CommandLine
        $exe = [string]$item.ExecutablePath
        if (($cmd -and $cmd.IndexOf($full, [StringComparison]::OrdinalIgnoreCase) -ge 0) -or
            ($exe -and $exe.StartsWith($full, [StringComparison]::OrdinalIgnoreCase))) {
            [void]$pids.Add([int]$item.ProcessId)
        }
    }
    & $report 18 ('结束关联进程 / Stopping processes: ' + @($pids).Count)
    foreach ($processId in @($pids)) {
        try { & taskkill.exe /PID $processId /T /F 2>$null | Out-Null } catch { }
        try { Stop-Process -Id $processId -Force -ErrorAction SilentlyContinue } catch { }
    }
    Start-Sleep -Seconds 2
    & $report 28 '删除计划任务 / Unregistering tasks'
    foreach ($taskName in $taskNames) {
        if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }
    Remove-NetFirewallRule -DisplayName 'Cyber-Butler Web UI 8765' -ErrorAction SilentlyContinue

    if (Test-Path -LiteralPath $full) {
        $files = @(Get-ChildItem -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue)
        $total = [Math]::Max(1, $files.Count)
        $seen = 0
        foreach ($file in $files) {
            $seen++
            if (($seen % 20) -eq 0 -or $seen -eq $total) {
                $relative = $file.FullName.Substring($full.Length).TrimStart([char]92)
                & $report (30 + (35 * $seen / $total)) ('盘点 / Preparing: ' + $relative)
            }
        }
        # First try the normal delete. Do not run a recursive takeown upfront:
        # on a venv-sized tree that can take many minutes and looks like a hang.
        $lastError = $null
        for ($attempt = 1; $attempt -le 5; $attempt++) {
            & $report (68 + (5 * $attempt)) ('删除文件 / Removing files (attempt ' + $attempt + '/5)')
            try {
                Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
                $lastError = $null
                break
            } catch {
                $lastError = $_
                if ($attempt -eq 2) {
                    & $report 72 '仅修复根目录权限 / Repairing root ACL only'
                    try {
                        & takeown.exe /F $full /A 2>$null | Out-Null
                        & icacls.exe $full /grant '*S-1-5-32-544:(F)' 2>$null | Out-Null
                    } catch { }
                } elseif ($attempt -eq 3) {
                    $aclSteps = @(
                        @{ Exe = 'takeown.exe'; Args = @('/F', $full, '/A', '/R', '/D', 'Y'); Label = '递归获取所有权 / Recursive takeown' },
                        @{ Exe = 'icacls.exe'; Args = @($full, '/grant', '*S-1-5-32-544:(F)', '/T', '/C'); Label = '递归修复 ACL / Recursive icacls' }
                    )
                    foreach ($aclStep in $aclSteps) {
                        & $report 78 ($aclStep.Label + ' — this can take several minutes, please wait…')
                        try {
                            $aclProcess = Start-Process -FilePath $aclStep.Exe -ArgumentList $aclStep.Args `
                                -WindowStyle Hidden -PassThru
                            $aclDeadline = (Get-Date).AddMinutes(10)
                            while (-not $aclProcess.HasExited) {
                                $elapsed = [int]((Get-Date) - $aclProcess.StartTime).TotalSeconds
                                & $report 78 ($aclStep.Label + ' — ' + $elapsed + 's elapsed, still working…')
                                if ((Get-Date) -gt $aclDeadline) {
                                    try { Stop-Process -Id $aclProcess.Id -Force } catch { }
                                    throw ($aclStep.Label + ' timed out after 10 minutes')
                                }
                                Start-Sleep -Seconds 2
                            }
                        } catch {
                            & $report 79 ('ACL step warning: ' + $_.Exception.Message)
                        }
                    }
                }
                Start-Sleep -Seconds (2 * $attempt)
            }
        }
        if ($lastError) {
            throw ('Could not remove ' + $full + ' after stopping processes. Close QQ/SnowLuma, then retry. Last error: ' + $lastError.Exception.Message)
        }
    }
    & $report 92 '清理 ProgramData / Cleaning ProgramData'
    $programData = Join-Path $env:ProgramData 'CyberButler'
    if (Test-Path -LiteralPath $programData) {
        Remove-Item -LiteralPath $programData -Recurse -Force -ErrorAction SilentlyContinue
    }
    & $report 100 '删除完成 / Uninstall complete'
    return $full
}

function Get-SelectedComboText($combo) {
    if ($null -eq $combo.SelectedItem) { return '' }
    if ($combo.SelectedItem -is [System.Windows.Controls.ComboBoxItem]) {
        if ($combo.SelectedItem.Tag) { return [string]$combo.SelectedItem.Tag }
        return [string]$combo.SelectedItem.Content
    }
    return [string]$combo.SelectedItem
}

function Invoke-GuiPreflight {
    try {
        $installPath = [string]$installPathBox.Text
        if ([string]::IsNullOrWhiteSpace($installPath)) { throw 'Install path is required.' }
        $script:StatusState = 'preflight_running'
        $statusText.Text = Get-UiText 'RunningPreflight'
        Write-GuiLog ('preflight: ' + $installPath)
        . (Join-Path $installerRoot 'lib\Installer.Common.ps1')
        . (Join-Path $installerRoot 'lib\Installer.Tier.ps1')
        . (Join-Path $installerRoot 'lib\Installer.Preflight.ps1')
        $result = Get-CyberButlerPreflight -InstallPath $installPath
        $json = $result | ConvertTo-Json -Depth 6
        Write-GuiLog $json
        $script:StatusState = 'preflight_done'
        $statusText.Text = Get-UiText 'PreflightDone'
    } catch {
        Write-GuiLog ('PREFLIGHT ERROR: ' + $_.Exception.Message)
        $script:StatusState = 'preflight_failed'
        $statusText.Text = Get-UiText 'PreflightFailed'
    }
}

$startButton.Add_Click({
    try {
        if (-not $approvalCheck.IsChecked) {
            [System.Windows.MessageBox]::Show((Get-UiText 'NeedApproval'), (Get-UiText 'Title')) | Out-Null
            return
        }
        $tierValue = Get-SelectedComboText $tierBox
        if ([string]::IsNullOrWhiteSpace($tierValue)) { $tierValue = 'Medium' }
        $physicalCheck = $window.FindName('PhysicalSeparationCheck')
        if (-not $physicalCheck.IsChecked) {
            if ($tierValue -like 'High*' -or $tierValue -eq 'High') {
                [System.Windows.MessageBox]::Show('High 档必须确认 TOTP 验证器不在当前主机。', (Get-UiText 'Title')) | Out-Null
                return
            }
            [System.Windows.MessageBox]::Show('警告：TOTP 验证器与 Agent 同机，物理隔离不成立。', (Get-UiText 'Title')) | Out-Null
        }
        try {
            $physDir = Join-Path ([string]$installPathBox.Text) 'tools'
            New-Item -ItemType Directory -Path $physDir -Force | Out-Null
            @{ schema = 1; separate_device = [bool]$physicalCheck.IsChecked; acknowledged_at = (Get-Date).ToUniversalTime().ToString('o') } |
                ConvertTo-Json | Set-Content -LiteralPath (Join-Path $physDir 'physical-separation.json') -Encoding UTF8
        } catch { }
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
            Cancel = Get-UiText 'Cancel'; TotpReady = Get-UiText 'TotpReady'; TotpConfirmed = Get-UiText 'TotpConfirmed'
        }
        if ($defenderExclusionCheck.IsChecked) {
            $defenderScript = Join-Path $installerRoot 'lib\Add-DefenderExclusion.ps1'
            try {
                $defOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $defenderScript -InstallRoot $installPath 2>&1
                if ($LASTEXITCODE -ne 0) { throw (($defOut | ForEach-Object { [string]$_ }) -join ' ') }
                Write-GuiLog (Get-UiText 'DefenderExclusionDone')
            } catch {
                [System.Windows.MessageBox]::Show(((Get-UiText 'DefenderExclusionFailed') + $_.Exception.Message), (Get-UiText 'Title')) | Out-Null
                Write-GuiLog ((Get-UiText 'DefenderExclusionFailed') + $_.Exception.Message)
            }
        }
        $adminEmailValue = ([string]$webUIEmailBox.Text).Trim()
        $smtpAuthValue = [string]$smtpAuthBox.Password
        $emailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
        if ($adminEmailValue -notmatch $emailPattern) {
            [System.Windows.MessageBox]::Show('请输入合法的管理员邮箱（例如 admin@example.com）。Email TOTP 审批需要该邮箱。', (Get-UiText 'Title')) | Out-Null
            return
        }
        if ([string]::IsNullOrWhiteSpace($smtpAuthValue)) {
            [System.Windows.MessageBox]::Show('请输入 SMTP 授权码；没有它 WebUI 邮件 OTP 和 TOTP 邮件审批无法工作。', (Get-UiText 'Title')) | Out-Null
            return
        }
        $smtpHostValue = ([string]$smtpHostBox.Text).Trim()
        $smtpPortValue = 0
        if ([string]::IsNullOrWhiteSpace($smtpHostValue) -or -not [int]::TryParse(([string]$smtpPortBox.Text).Trim(), [ref]$smtpPortValue) -or $smtpPortValue -lt 1 -or $smtpPortValue -gt 65535) {
            [System.Windows.MessageBox]::Show('请输入合法的 SMTP 主机和端口（例如 smtp.163.com / 465）。', (Get-UiText 'Title')) | Out-Null
            return
        }

        Set-GuiBusy $true
        $script:GuiInstallPath = $installPath
        $script:GuiCompletionShown = $false
        $script:GuiExitNoticeAt = $null
        $script:GuiStageStartedAt = Get-Date
        $script:GuiStagePercent = 0
        Write-GuiLog (Get-UiText 'Starting')
        $installProgress.Value = 2
        Start-CyberButlerGuiInstall `
            -Window $window -InstallerPath $installerPath -InstallPath $installPath `
            -Tier $tierValue -OwnerQQ ([string]$ownerQQBox.Text) -WebUIBind $bindValue `
            -PersonalPluginsPath ([string]$personalPluginsBox.Text) `
            -ApiKeyFile ([string]$apiKeyFileBox.Text) `
            -WebUIAdminEmail ([string]$webUIEmailBox.Text) `
            -SmtpAuth ([string]$smtpAuthBox.Password) `
            -SmtpHost ([string]$smtpHostBox.Text) `
            -SmtpPort ([string]$smtpPortBox.Text) `
            -OnLog { param($line) Write-GuiLog $line } `
            -OnStatus {
                param($line)
                $statusText.Text = $line
                if ($line -match 'finished|failed') { Show-GuiCompletionIfReady }
            } `
            -OnProgress {
                param($percent, $message)
                if ([int]$percent -gt $script:GuiStagePercent) {
                    $script:GuiStagePercent = [int]$percent
                    $script:GuiStageStartedAt = Get-Date
                }
                if ([int]$percent -gt $installProgress.Value) { $installProgress.Value = [int]$percent }
                if ($message -and $message -ne $script:LastProgressMessage) {
                    $script:LastProgressMessage = $message
                    Write-GuiLog ('progress ' + [int]$percent + '% · ' + $message)
                }
            } `
            -Text $text | Out-Null
        $script:GuiCompletionTimer = New-Object System.Windows.Threading.DispatcherTimer
        $script:GuiCompletionTimer.Interval = [TimeSpan]::FromSeconds(2)
        $script:GuiCompletionTimer.add_Tick({ try { Show-GuiCompletionIfReady } catch { } })
        $script:GuiCompletionTimer.Start()
    } catch {
        Set-GuiBusy $false
        Write-GuiLog ('START ERROR: ' + $_.Exception.Message)
        $statusText.Text = Get-UiText 'StartFailed'
    }
})

$reportButton.Add_Click({
    $reportDir = Split-Path -Parent (Get-GuiReportPath)
    if (Test-Path -LiteralPath $reportDir) {
        Start-Process -FilePath 'explorer.exe' -ArgumentList $reportDir | Out-Null
    } else {
        Write-GuiLog ('Report directory not found: ' + $reportDir)
    }
})

$helpButton.Add_Click({
    try { Show-CyberButlerHelp } catch {
        [System.Windows.MessageBox]::Show(((Get-UiText 'HelpBody') + "`n`n" + (Get-EmailHelpText)), (Get-UiText 'Help')) | Out-Null
    }
})

$statusButton.Add_Click({
    try { Show-GuiInstallStatus } catch {
        [System.Windows.MessageBox]::Show(('Status check failed: ' + $_.Exception.Message), 'Install status') | Out-Null
    }
})

$removeButton.Add_Click({
    if ($script:cbGuiProcess -and -not $script:cbGuiProcess.HasExited) {
        [System.Windows.MessageBox]::Show('Installation is running. Wait or use Exit to stop it first.', (Get-UiText 'Remove')) | Out-Null
        return
    }
    $choice = Show-CyberButlerRemoveDialog -Owner $window -Text @{
        RemoveTitle = Get-UiText 'RemoveTitle'
        RemoveHint = Get-UiText 'RemoveHint'
        RemovePackage = Get-UiText 'RemovePackage'
        RemoveProject = Get-UiText 'RemoveProject'
        RemoveBoth = Get-UiText 'RemoveBoth'
        Continue = Get-UiText 'Continue'
        Cancel = Get-UiText 'Cancel'
    }
    if (-not $choice) { return }
    $answer = [System.Windows.MessageBox]::Show((Get-UiText 'RemoveConfirm2'), (Get-UiText 'Remove'), 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }
    $removeProgress = $null
    try {
        $messages = @()
        if ($choice -in @('project', 'both')) {
            $removeProgress = Show-CyberButlerRemoveProgress -Owner $window
            Remove-CyberButlerGuiInstall ([string]$installPathBox.Text) -OnProgress {
                param($percent, $detail)
                Update-CyberButlerRemoveProgress -Progress $removeProgress -Percent $percent -Message $detail
            } | Out-Null
            $messages += (Get-UiText 'RemoveProjectDone')
        }
        if ($choice -in @('package', 'both')) {
            Remove-CyberButlerPackage -InstallerRoot $installerRoot | Out-Null
            $messages += $(if ($choice -eq 'both') { Get-UiText 'RemoveBothDone' } else { Get-UiText 'RemovePackageDone' })
        }
        $serviceAccountMessage = ''
        $serviceUser = Get-LocalUser -Name 'CyberButlerSvc' -ErrorAction SilentlyContinue
        $serviceProfile = Join-Path $env:SystemDrive 'Users\CyberButlerSvc'
        if ($script:cbRemoveCleanup) {
            Update-CyberButlerRemoveProgress -Progress $removeProgress -Percent 97 -Message '清理 CyberButlerSvc 服务账户 / Cleaning service account'
            $cleanup = Remove-CyberButlerServiceAccountProfile
            if ($cleanup.removed) { $serviceAccountMessage = 'CyberButlerSvc 服务账户及 profile 已删除。' }
            elseif ($cleanup.pending_reboot) { $serviceAccountMessage = 'CyberButlerSvc 服务账户已删除；profile 仍被系统占用，已安排下次重启自动清理。' }
            else { $serviceAccountMessage = 'CyberButlerSvc 未完全删除：' + $cleanup.reason }
        } elseif ($serviceUser -or (Test-Path -LiteralPath $serviceProfile)) {
            $serviceAccountMessage = '保留了 CyberButlerSvc 服务账户/profile；如确认不再使用，可重新运行删除并勾选清理。'
        }
        $desktopPath = [Environment]::GetFolderPath('Desktop')
        $bigFishPath = Join-Path $desktopPath '大肥鱼专用文件夹'
        $dashboardShortcut = Join-Path $desktopPath 'Cyber-Butler 主控台.lnk'
        $dataNote = ''
        if ($script:cbRemoveBigFish) {
            Update-CyberButlerRemoveProgress -Progress $removeProgress -Percent 98 -Message '删除桌面大肥鱼专用文件夹 / Removing Big Fish folder'
            try {
                if (Test-Path -LiteralPath $bigFishPath) { Remove-Item -LiteralPath $bigFishPath -Recurse -Force -ErrorAction Stop }
                $dataNote = '桌面大肥鱼专用文件夹已删除。'
            } catch { $dataNote = '大肥鱼专用文件夹删除失败：' + $_.Exception.Message }
        } else {
            $dataNote = '保留桌面大肥鱼专用文件夹（用户文件）：' + $bigFishPath
        }
        if ($script:cbRemoveDashboardShortcut) {
            try { if (Test-Path -LiteralPath $dashboardShortcut) { Remove-Item -LiteralPath $dashboardShortcut -Force -ErrorAction Stop } }
            catch { $dataNote += "`n主控台快捷方式删除失败：" + $_.Exception.Message }
        }
        if ($removeProgress) { $removeProgress.Window.Close() }
        $profileNote = $env:USERPROFILE + ' 是 Windows 当前用户 profile（不是项目数据），不能删除。项目数据原本在 C:\CyberButler 和 C:\ProgramData\CyberButler。'
        if ($serviceAccountMessage) { $profileNote += "`n" + $serviceAccountMessage }
        if ($dataNote) { $profileNote += "`n" + $dataNote }
        [System.Windows.MessageBox]::Show((($messages -join "`n") + "`n`n" + $profileNote), (Get-UiText 'Remove')) | Out-Null
        if ($choice -in @('package', 'both')) { $window.Close() }
    } catch {
        if ($removeProgress) { $removeProgress.Window.Close() }
        [System.Windows.MessageBox]::Show(((Get-UiText 'RemoveFailed') + $_.Exception.Message), (Get-UiText 'Remove')) | Out-Null
    }
})

function Stop-GuiProcessTree([int]$ProcessId) {
    try {
        foreach ($child in @(Get-CimInstance Win32_Process -Filter ("ParentProcessId = " + $ProcessId) -ErrorAction SilentlyContinue)) {
            Stop-GuiProcessTree -ProcessId ([int]$child.ProcessId)
        }
    } catch { }
    try { Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue } catch { }
}

$script:GuiCloseConfirmed = $false
$window.Add_Closing({
    param($sender, $eventArgs)
    if ($script:GuiCloseConfirmed) { return }
    if ($script:cbGuiProcess -and -not $script:cbGuiProcess.HasExited) {
        $answer = [System.Windows.MessageBox]::Show(
            (Get-UiText 'CloseConfirm'), (Get-UiText 'CloseConfirmTitle'), 'YesNo', 'Warning')
        if ($answer -ne 'Yes') {
            $eventArgs.Cancel = $true
            return
        }
        if ($script:GuiCompletionTimer) { $script:GuiCompletionTimer.Stop() }
        $script:GuiCompletionShown = $true
        Stop-GuiProcessTree -ProcessId $script:cbGuiProcess.Id
    }
    $script:GuiCloseConfirmed = $true
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
    Invoke-GuiPreflight
})

if ($SelfTest) {
    Write-Output 'GUI_XAML_OK'
    Write-Output ('INSTALLER=' + $installerPath)
    return
}

[void]$window.ShowDialog()
