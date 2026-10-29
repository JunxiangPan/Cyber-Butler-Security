#Requires -Version 5.1
<#
Cyber-Butler Dashboard - Phase 1 read-only shell.

This is a local WPF desktop application. It is not an AstrBot plugin and is not
registered as an LLM tool. Phase 1 only reads ports, GPU, provider configuration,
audit log, persona prompt, and game-list files; write buttons are disabled.
#>
param(
    [string]$ProjectRoot = '',
    [switch]$SmokeTest,
    [switch]$SmokeSettings,
    [switch]$SmokeThemes,
    [switch]$SmokeSettingsDialog,
    [switch]$SmokeBackground,
    [switch]$SmokeModules,
    [switch]$SmokeUi,
    [string]$SmokeAssetDir = '',
    [string]$SmokeSettingsShot = '',
    [string]$SmokeTheme = '',
    [string]$SettingsFile = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$toolsRoot = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $toolsRoot }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
$script:ToolsRoot = $toolsRoot
$script:ProjectRoot = $ProjectRoot
$script:CheckScript = Join-Path $toolsRoot 'check_update.ps1'
$script:MergeScript = Join-Path $ProjectRoot 'tools\update_merge.ps1'
$script:ActionScript = Join-Path $toolsRoot 'dashboard_actions.ps1'
$script:I18nFile = Join-Path $toolsRoot 'dashboard_i18n.json'
$settingsFileOverride = $SettingsFile
$script:SettingsFile = Join-Path $env:LOCALAPPDATA 'CyberButler\dashboard-settings.json'
if ($settingsFileOverride) { $script:SettingsFile = $settingsFileOverride }
$script:GameScanner = Join-Path $toolsRoot 'dashboard_game.ps1'
function Load-XamlDictionary([string]$path) {
    $xml = Get-Content -LiteralPath $path -Raw -Encoding UTF8
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xml)
    return [Windows.Markup.XamlReader]::Load($reader)
}
$script:CurrentLanguage = 'zh'
$script:DashboardVersion = '1.2.0'
$script:I18nZhIndex = $null
function Get-I18nEntry([string]$zh) {
    if (-not $script:I18nZhIndex) {
        $script:I18nZhIndex = @{}
        try {
            $file = Join-Path $PSScriptRoot 'dashboard_i18n.json'
            if (Test-Path -LiteralPath $file) {
                $data = Get-Content -LiteralPath $file -Raw -Encoding UTF8 | ConvertFrom-Json
                foreach ($entry in @($data.entries)) {
                    if ($entry.zh) { $script:I18nZhIndex[[string]$entry.zh] = $entry }
                }
            }
        } catch { }
    }
    return $script:I18nZhIndex[$zh]
}
function T([string]$zh, [string]$en) {
    $lang = [string]$script:CurrentLanguage
    if ($lang -eq 'zh') { return $zh }
    $entry = Get-I18nEntry $zh
    if ($entry) {
        $value = [string]$entry.$lang
        if ($value) { return $value }
    }
    if ($lang -eq 'en') { return $en }
    return $en
}
. (Join-Path $toolsRoot 'dashboard_core.ps1')
. (Join-Path $toolsRoot 'plugin_security_scanner.ps1')
. (Join-Path $toolsRoot 'plugin_hub.ps1')
. (Join-Path $toolsRoot 'plugin_market.ps1')
. (Join-Path $toolsRoot 'dashboard_modules.ps1')
. (Join-Path $toolsRoot 'plugin_review_dialog.ps1')
. (Join-Path $toolsRoot 'dashboard_errors.ps1')
. (Join-Path $toolsRoot 'dashboard_persona.ps1')

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        xmlns:po="http://schemas.microsoft.com/winfx/2006/xaml/presentation/options"
        Title="Cyber-Butler 主控台" Width="1120" Height="760"
        WindowStartupLocation="CenterScreen"
        Background="{DynamicResource PageBrush}" Foreground="{DynamicResource TextBrush}" FontFamily="Microsoft YaHei UI, Segoe UI, Yu Gothic UI, Malgun Gothic">
  <Window.Resources />
  <Grid x:Name="WindowRoot">
    <Grid x:Name="BackgroundLayer" Background="{DynamicResource PageBrush}" ClipToBounds="True" IsHitTestVisible="False"/>
    <Border x:Name="BackgroundOverlay" Background="{DynamicResource OverlayBrush}" IsHitTestVisible="False" Visibility="Collapsed"/>
    <Grid x:Name="RootGrid" Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="Transparent" CornerRadius="6" Padding="14">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="Cyber-Butler 主控台" FontSize="22" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <TextBlock Text="   本地主控台" Foreground="{DynamicResource MutedBrush}" FontSize="13" VerticalAlignment="Center"/>
        <TextBlock x:Name="AstrBotLight" Text="● AstrBot" Margin="28,0,0,0" FontSize="15" VerticalAlignment="Center" Cursor="Hand" ToolTip="打开 AstrBot WebUI"/>
        <TextBlock x:Name="BrokerLight" Text="● Broker" Margin="18,0,0,0" FontSize="15" VerticalAlignment="Center" Cursor="Hand" ToolTip="TOTP Broker 为后台无头服务，无 Web 管理界面"/>
        <TextBlock x:Name="SnowLumaLight" Text="● SnowLuma" Margin="18,0,0,0" FontSize="15" VerticalAlignment="Center" Cursor="Hand" ToolTip="打开 SnowLuma WebUI"/>
        <TextBlock x:Name="VersionLabel" Text="版本读取中..." Margin="30,0,0,0" FontSize="13" Foreground="{DynamicResource AccentBrush}" Cursor="Hand" ToolTip="点击检查更新"/>
        <Button x:Name="SettingsButton" Content="设置" Width="70" Height="28" Margin="18,0,0,0"/>
      </StackPanel>
    </Border>

    <TabControl Grid.Row="2" x:Name="MainTabs" Margin="0,14,0,0">
      <TabItem Header="状态大盘">
        <Grid Margin="18">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <UniformGrid Grid.Row="0" Columns="3">
            <Border Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,10,0">
              <StackPanel>
                <TextBlock Text="AstrBot" FontSize="16" FontWeight="SemiBold"/>
                <TextBlock x:Name="AstrBotCardStatus" Text="检测中..." Margin="0,8,0,0" FontSize="24"/>
                <TextBlock Text="端口 6185" Foreground="{DynamicResource MutedBrush}"/>
              </StackPanel>
            </Border>
            <Border Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,10,0">
              <StackPanel>
                <TextBlock Text="TOTP Broker" FontSize="16" FontWeight="SemiBold"/>
                <TextBlock x:Name="BrokerCardStatus" Text="检测中..." Margin="0,8,0,0" FontSize="24"/>
                <TextBlock Text="端口 18090" Foreground="{DynamicResource MutedBrush}"/>
              </StackPanel>
            </Border>
            <Border Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="16">
              <StackPanel>
                <TextBlock Text="SnowLuma" FontSize="16" FontWeight="SemiBold"/>
                <TextBlock x:Name="SnowLumaCardStatus" Text="检测中..." Margin="0,8,0,0" FontSize="24"/>
                <TextBlock Text="端口 5099" Foreground="{DynamicResource MutedBrush}"/>
              </StackPanel>
            </Border>
          </UniformGrid>

          <Border Grid.Row="1" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,14,0,0">
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="360"/>
              </Grid.ColumnDefinitions>
              <StackPanel>
                <TextBlock Text="GPU 显存" FontSize="16" FontWeight="SemiBold"/>
                <TextBlock x:Name="GpuText" Text="读取中..." Margin="0,8,0,6" FontSize="15"/>
                <ProgressBar x:Name="GpuBar" Height="14" Minimum="0" Maximum="100" Value="0"/>
              </StackPanel>
              <StackPanel Grid.Column="1">
                <TextBlock Text="当前 Provider（配置读取）" FontSize="16" FontWeight="SemiBold"/>
                <TextBlock x:Name="ProviderText" Text="读取中..." Margin="0,8,0,0" FontSize="15"/>
              </StackPanel>
            </Grid>
          </Border>

          <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,16,0,0">
            <Button x:Name="RestartButton" Content="重启 AstrBot 服务" Width="150" Height="36" Margin="0,0,8,0"/>
            <Button x:Name="VramButton" Content="一键释放显存" Width="130" Height="36" Margin="0,0,8,0"/>
            <Button x:Name="LogsButton" Content="打开运行日志目录" Width="150" Height="36"/>
          </StackPanel>

          <TextBlock Grid.Row="3" Text="Phase 1：按钮暂不执行写操作。" Foreground="{DynamicResource MutedBrush}" Margin="0,18,0,0"/>
        </Grid>
      </TabItem>

      <TabItem Header="安全风控">
        <Grid Margin="18">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <TextBlock Text="最近 TOTP 审批 / 拦截记录" FontSize="17" FontWeight="SemiBold"/>
          <DataGrid Grid.Row="1" x:Name="AuditGrid" Margin="0,10,0,12" IsReadOnly="True"
                    AutoGenerateColumns="True" CanUserAddRows="False" HeadersVisibility="Column"/>
          <StackPanel Grid.Row="2" Orientation="Horizontal">
            <Button x:Name="FuseButton" Content="紧急熔断" Width="150" Height="40"
                    Background="#C62828" Foreground="White" FontWeight="Bold"/>
            <TextBlock Text="   紧急熔断功能将在第二阶段接入，需要二次确认和 UAC。" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/>
          </StackPanel>
          <Border Grid.Row="3" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="14" Margin="0,14,0,0">
            <StackPanel>
              <TextBlock Text="配置（只读预览）" FontSize="16" FontWeight="SemiBold"/>
              <Grid Margin="0,10,0,0">
                <Grid.ColumnDefinitions>
                  <ColumnDefinition Width="120"/>
                  <ColumnDefinition Width="320"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                  <RowDefinition Height="Auto"/>
                  <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Text="QQ 号" VerticalAlignment="Center"/>
                <TextBox Grid.Column="1" x:Name="QqBox" Height="28"/>
                <TextBlock Grid.Row="1" Text="API Key" Margin="0,10,0,0" VerticalAlignment="Center"/>
                <PasswordBox Grid.Row="1" Grid.Column="1" x:Name="ApiKeyBox" Height="28" Margin="0,10,0,0"/>
              </Grid>
              <Button x:Name="SaveConfigButton" Content="保存并同步" Width="120" Height="32" HorizontalAlignment="Left" Margin="0,14,0,0"/>
            </StackPanel>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="人格与记忆">
        <Grid Margin="18">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Grid.Row="0" Orientation="Horizontal">
            <Button x:Name="PersonaRefreshButton" Content="刷新人格列表" MinWidth="100" Padding="10,0" Height="32"/>
            <Button x:Name="PersonaSwitchButton" Content="切换为人格" MinWidth="100" Padding="10,0" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="PersonaNewButton" Content="新建空白人格" MinWidth="100" Padding="10,0" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="PersonaCopyButton" Content="复制当前人格" MinWidth="100" Padding="10,0" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="PersonaDeleteButton" Content="删除人格" MinWidth="100" Padding="10,0" Height="32" Margin="8,0,0,0"/>
            <TextBlock x:Name="PersonaStatusText" Margin="12,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/>
          </StackPanel>
          <Grid Grid.Row="1" Margin="0,10,0,10">
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="240"/>
              <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <ListBox x:Name="PersonaListBox" Grid.Column="0" DisplayMemberPath="Display" Margin="0,0,10,0"/>
            <Grid Grid.Column="1">
              <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
              </Grid.RowDefinitions>
              <TextBlock x:Name="PersonaActiveText" Foreground="{DynamicResource MutedBrush}"/>
              <TextBox x:Name="PromptBox" Grid.Row="1" Margin="0,6,0,0" AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
            </Grid>
          </Grid>
          <TextBlock Grid.Row="2" Text="切换人格会更新 AstrBot 的默认人格并重载配置；删除非默认人格前会自动备份到 backups/personas。" TextWrapping="Wrap" Foreground="{DynamicResource MutedBrush}"/>
          <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,12,0,0">
            <Button x:Name="SavePromptButton" Content="保存并重载 AstrBot" Width="170" Height="36" Margin="0,0,8,0"/>
            <Button x:Name="ClearConversationButton" Content="清空当前对话历史" Width="170" Height="36"/>
          </StackPanel>
        </Grid>
      </TabItem>

      <TabItem Header="游戏白名单">
        <Grid Margin="18">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Orientation="Horizontal">
            <Button x:Name="ScanGamesButton" Content="扫描本地游戏库并同步" Width="190" Height="36"/>
            <ProgressBar x:Name="ScanProgressBar" Width="120" Height="12" IsIndeterminate="True" Visibility="Collapsed" Margin="12,0,0,0" VerticalAlignment="Center"/>
            <TextBlock x:Name="ScanStatusText" Text="" Margin="10,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/>
            <TextBlock x:Name="GameCountText" Text="当前白名单：0 个" Margin="18,0,0,0" VerticalAlignment="Center" FontSize="15"/>
          </StackPanel>
          <ListBox Grid.Row="1" x:Name="GameListBox" Margin="0,12,0,12"/>
          <StackPanel Grid.Row="2" Orientation="Horizontal">
            <TextBlock Text="进程名：" VerticalAlignment="Center"/>
            <TextBox x:Name="GameInput" Width="240" Height="28"/>
            <Button x:Name="AddGameButton" Content="手动添加" Width="95" Height="30" Margin="8,0,0,0"/>
            <Button x:Name="RemoveGameButton" Content="移除选中" Width="95" Height="30" Margin="8,0,0,0"/>
          </StackPanel>
          <Border Grid.Row="3" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="12" Margin="0,12,0,0">
            <StackPanel>
              <TextBlock Text="内置忽略名单（不会触发模型卸载）" FontWeight="SemiBold"/>
              <TextBlock x:Name="IgnoreText" Text="读取中..." TextWrapping="Wrap" Foreground="{DynamicResource MutedBrush}" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="智能体插件">
        <Grid Margin="14">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Orientation="Horizontal">
            <Button x:Name="PluginRefreshButton" Content="刷新" Width="70" Height="32"/>
            <Button x:Name="PluginEnableButton" Content="启用" Width="70" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="PluginDisableButton" Content="禁用" Width="70" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="PluginDeleteButton" Content="删除（回收站）" Width="130" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="PluginResetButton" Content="恢复默认配置" Width="120" Height="32" Margin="8,0,0,0"/>
            <TextBlock x:Name="PluginStatusText" Margin="12,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/>
          </StackPanel>
          <DataGrid Grid.Row="1" x:Name="PluginGrid" Margin="0,12,0,10" IsReadOnly="True"
                    AutoGenerateColumns="False" CanUserAddRows="False" HeadersVisibility="Column"
                    SelectionMode="Single" GridLinesVisibility="Horizontal">
            <DataGrid.Columns>
              <DataGridTextColumn Header="插件" Binding="{Binding Name}" Width="210"/>
              <DataGridTextColumn Header="显示名" Binding="{Binding DisplayName}" Width="190"/>
              <DataGridTextColumn Header="版本" Binding="{Binding Version}" Width="80"/>
              <DataGridTextColumn Header="作者" Binding="{Binding Author}" Width="110"/>
              <DataGridTextColumn Header="状态" Binding="{Binding StateText}" Width="70"/>
              <DataGridTextColumn Header="兼容" Binding="{Binding CompatText}" Width="90"/>
            </DataGrid.Columns>
          </DataGrid>
          <Border Grid.Row="2" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="12">
            <TextBlock x:Name="PluginDetailText" Text="选择一个插件查看详情。" TextWrapping="Wrap" Foreground="{DynamicResource MutedBrush}"/>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="控制台模块">
        <Grid Margin="14">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <Border x:Name="ModuleTrustWarning" Grid.Row="0" Background="#FFF4CE" BorderBrush="#E0B400" BorderThickness="1" CornerRadius="6" Padding="10,7" Margin="0,0,0,10" Visibility="Collapsed">
            <TextBlock Text="⚠️ 注意：控制台插件运行在当前用户的最高权限下，请仅安装你信任的插件！" Foreground="#5C4B00" TextWrapping="Wrap" FontWeight="SemiBold"/>
          </Border>
          <StackPanel Grid.Row="1" Orientation="Horizontal">
            <Button x:Name="ModuleRefreshButton" Content="重新加载" Width="100" Height="32"/>
            <Button x:Name="ModuleEnableButton" Content="启用" Width="70" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="ModuleDisableButton" Content="禁用" Width="70" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="ModuleFolderButton" Content="打开模块目录" Width="120" Height="32" Margin="8,0,0,0"/>
            <TextBlock x:Name="ModuleStatusText" Margin="12,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/>
          </StackPanel>
          <ListBox Grid.Row="2" x:Name="ModuleListBox" Margin="0,12,0,10" DisplayMemberPath="Display"/>
          <Border Grid.Row="3" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="12">
            <StackPanel>
              <TextBlock x:Name="ModuleDetailText" Text="第三方模块以本地 PowerShell 运行，请只启用可信来源。" TextWrapping="Wrap" Foreground="{DynamicResource MutedBrush}"/>
              <TextBlock Text="规范：tools\dashboard_plugins\&lt;id&gt;\manifest.json + ui.xaml + logic.ps1；禁用后不会加载对应 XAML 与脚本。"
                         TextWrapping="Wrap" Margin="0,6,0,0" Foreground="{DynamicResource MutedBrush}"/>
            </StackPanel>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="插件市场">
        <Grid Margin="14">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Orientation="Horizontal">
            <TextBox x:Name="MarketQueryBox" Width="240" Height="30" ToolTip="输入关键词，留空显示热门插件"/>
            <ComboBox x:Name="MarketSourceCombo" Width="150" Height="30" Margin="8,0,0,0" SelectedIndex="0">
              <ComboBoxItem Content="AstrBot 官方市场"/>
              <ComboBoxItem Content="GitHub"/>
            </ComboBox>
            <Button x:Name="MarketSearchButton" Content="搜索" Width="80" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="MarketInstallButton" Content="审查并安装" Width="110" Height="32" Margin="8,0,0,0"/>
            <TextBlock x:Name="MarketStatusText" Margin="12,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/>
          </StackPanel>
          <DataGrid Grid.Row="1" x:Name="MarketGrid" Margin="0,12,0,10" IsReadOnly="True"
                    AutoGenerateColumns="False" CanUserAddRows="False" HeadersVisibility="Column"
                    SelectionMode="Single" GridLinesVisibility="Horizontal">
            <DataGrid.Columns>
              <DataGridTextColumn Header="插件" Binding="{Binding Name}" Width="220"/>
              <DataGridTextColumn Header="作者" Binding="{Binding Author}" Width="120"/>
              <DataGridTextColumn Header="版本" Binding="{Binding Version}" Width="80"/>
              <DataGridTextColumn Header="星标" Binding="{Binding Stars}" Width="60"/>
              <DataGridTextColumn Header="来源" Binding="{Binding SourceLabel}" Width="90"/>
            </DataGrid.Columns>
          </DataGrid>
          <Border Grid.Row="2" Background="{DynamicResource SurfaceBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="12">
            <TextBlock x:Name="MarketDetailText" Text="搜索插件后，安装前会自动做静态安全扫描与 AstrBot 版本兼容检查。" TextWrapping="Wrap" Foreground="{DynamicResource MutedBrush}"/>
          </Border>
        </Grid>
      </TabItem>

      <TabItem Header="系统日志">
        <Grid Margin="14">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>
          <StackPanel Orientation="Horizontal">
            <Button x:Name="ErrorCopyButton" Content="一键复制错误信息" Width="150" Height="32"/>
            <Button x:Name="ErrorClearButton" Content="清空" Width="70" Height="32" Margin="8,0,0,0"/>
            <Button x:Name="ErrorRefreshButton" Content="刷新" Width="70" Height="32" Margin="8,0,0,0"/>
            <TextBlock x:Name="ErrorStatusText" Margin="12,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/>
          </StackPanel>
          <TextBox Grid.Row="1" x:Name="ErrorLogBox" IsReadOnly="True" Margin="0,12,0,10"
                   AcceptsReturn="True" TextWrapping="NoWrap" VerticalScrollBarVisibility="Auto"
                   HorizontalScrollBarVisibility="Auto" FontFamily="Consolas" FontSize="12"/>
          <TextBlock Grid.Row="2" x:Name="ErrorPathText" Text="日志文件：%LOCALAPPDATA%/CyberButler/ui-errors.log" TextWrapping="Wrap" Foreground="{DynamicResource MutedBrush}"/>
        </Grid>
      </TabItem>
    </TabControl>
    <Border Grid.Row="3" Background="Transparent" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="0,1,0,0" Padding="10,6">
      <StackPanel>
        <ProgressBar x:Name="UpdateProgressBar" Height="10" Minimum="0" Maximum="100" Value="0" Visibility="Collapsed"/>
        <TextBlock x:Name="UpdateStatusText" Text="" FontSize="12" Foreground="{DynamicResource MutedBrush}" Margin="0,4,0,0" Visibility="Collapsed"/>
      </StackPanel>
    </Border>
    </Grid>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$themeDictionary = Load-XamlDictionary (Join-Path $toolsRoot 'dashboard_theme_light.xaml')
$styleDictionary = Load-XamlDictionary (Join-Path $toolsRoot 'dashboard_styles.xaml')
$window.Resources.MergedDictionaries.Add($themeDictionary)
$window.Resources.MergedDictionaries.Add($styleDictionary)
if ($SmokeTest) { Write-Output 'DASHBOARD_XAML_OK'; exit 0 }
$astrBotLight = $window.FindName('AstrBotLight')
$brokerLight = $window.FindName('BrokerLight')
$snowLumaLight = $window.FindName('SnowLumaLight')
$astrBotCard = $window.FindName('AstrBotCardStatus')
$brokerCard = $window.FindName('BrokerCardStatus')
$snowLumaCard = $window.FindName('SnowLumaCardStatus')
$gpuText = $window.FindName('GpuText')
$gpuBar = $window.FindName('GpuBar')
$providerText = $window.FindName('ProviderText')
$auditGrid = $window.FindName('AuditGrid')
$qqBox = $window.FindName('QqBox')
$apiKeyBox = $window.FindName('ApiKeyBox')
$promptBox = $window.FindName('PromptBox')
$gameCountText = $window.FindName('GameCountText')
$gameListBox = $window.FindName('GameListBox')
$ignoreText = $window.FindName('IgnoreText')
$versionLabel = $window.FindName('VersionLabel')
$settingsButton = $window.FindName('SettingsButton')
$rootGrid = $window.FindName('RootGrid')
$backgroundLayer = $window.FindName('BackgroundLayer')
$backgroundOverlay = $window.FindName('BackgroundOverlay')
$mainTabs = $window.FindName('MainTabs')
$pluginGrid = $window.FindName('PluginGrid')
$pluginStatusText = $window.FindName('PluginStatusText')
$pluginDetailText = $window.FindName('PluginDetailText')
$pluginRefreshButton = $window.FindName('PluginRefreshButton')
$pluginEnableButton = $window.FindName('PluginEnableButton')
$pluginDisableButton = $window.FindName('PluginDisableButton')
$pluginDeleteButton = $window.FindName('PluginDeleteButton')
$pluginResetButton = $window.FindName('PluginResetButton')
$moduleListBox = $window.FindName('ModuleListBox')
$moduleStatusText = $window.FindName('ModuleStatusText')
$moduleTrustWarning = $window.FindName('ModuleTrustWarning')
$moduleDetailText = $window.FindName('ModuleDetailText')
$moduleRefreshButton = $window.FindName('ModuleRefreshButton')
$moduleEnableButton = $window.FindName('ModuleEnableButton')
$moduleDisableButton = $window.FindName('ModuleDisableButton')
$moduleFolderButton = $window.FindName('ModuleFolderButton')
$marketQueryBox = $window.FindName('MarketQueryBox')
$marketSourceCombo = $window.FindName('MarketSourceCombo')
$marketSearchButton = $window.FindName('MarketSearchButton')
$marketInstallButton = $window.FindName('MarketInstallButton')
$marketStatusText = $window.FindName('MarketStatusText')
$marketGrid = $window.FindName('MarketGrid')
$marketDetailText = $window.FindName('MarketDetailText')
$personaListBox = $window.FindName('PersonaListBox')
$personaStatusText = $window.FindName('PersonaStatusText')
$personaActiveText = $window.FindName('PersonaActiveText')
$personaRefreshButton = $window.FindName('PersonaRefreshButton')
$personaSwitchButton = $window.FindName('PersonaSwitchButton')
$personaNewButton = $window.FindName('PersonaNewButton')
$personaCopyButton = $window.FindName('PersonaCopyButton')
$personaDeleteButton = $window.FindName('PersonaDeleteButton')
$errorLogBox = $window.FindName('ErrorLogBox')
$errorStatusText = $window.FindName('ErrorStatusText')
$errorCopyButton = $window.FindName('ErrorCopyButton')
$errorClearButton = $window.FindName('ErrorClearButton')
$errorRefreshButton = $window.FindName('ErrorRefreshButton')
Register-UiErrorBox $errorLogBox $errorStatusText
$scanProgressBar = $window.FindName('ScanProgressBar')
$scanStatusText = $window.FindName('ScanStatusText')
$updateProgressBar = $window.FindName('UpdateProgressBar')
$updateStatusText = $window.FindName('UpdateStatusText')
$restartButton = $window.FindName('RestartButton')
$vramButton = $window.FindName('VramButton')
$logsButton = $window.FindName('LogsButton')
$fuseButton = $window.FindName('FuseButton')
$savePromptButton = $window.FindName('SavePromptButton')
$saveConfigButton = $window.FindName('SaveConfigButton')
$clearConversationButton = $window.FindName('ClearConversationButton')
$scanGamesButton = $window.FindName('ScanGamesButton')
$addGameButton = $window.FindName('AddGameButton')
$removeGameButton = $window.FindName('RemoveGameButton')
$gameInput = $window.FindName('GameInput')
. (Join-Path $toolsRoot 'dashboard_settings.ps1')
if ($SmokeModules) {
    Register-DashboardModuleExceptionHook $window
    $moduleSmoke = Initialize-DashboardModules -Tabs $mainTabs -ToolsRoot $script:ToolsRoot
    foreach ($loadedModule in @($moduleSmoke.Loaded)) { Write-Output ('LOADED ' + $loadedModule.Id) }
    foreach ($failedModule in @($moduleSmoke.Failed)) { Write-Output ('FAILED ' + $failedModule.Id + ' :: ' + $failedModule.Error) }
    Write-Output ('MODULES=' + $moduleSmoke.Total + ' LOADED=' + @($moduleSmoke.Loaded).Count)
    exit 0
}
if ($SmokeSettings) {
    $s = Read-DashboardSettings
    Set-UiTheme $s.theme
    Set-UiBackground $s.background $s | Out-Null
    Apply-Language $s.language
    $snapshot = Get-BgStateSnapshot
    Write-Output ('DASHBOARD_SETTINGS_OK theme=' + $s.theme + ' language=' + $s.language + ' animated=' + $s.enable_animated_bg + ' kind=' + $snapshot.Kind + ' frames=' + $snapshot.FrameCount + ' background=' + $s.background)
    exit 0
}

function Set-Light($light, $card, [string]$name, [bool]$online) {
    $color = if ($online) { '#1B8A3A' } else { '#C62828' }
    $text = if ($online) { T '● 在线' '● Online' } else { T '● 离线' '● Offline' }
    $light.Foreground = $color
    $light.Text = "● $name"
    $card.Text = $text
    $card.Foreground = $color
}

function Update-Dashboard {
    $a = Test-Port 6185
    $b = Test-Port 18090
    $s = Test-Port 5099
    Set-Light $astrBotLight $astrBotCard 'AstrBot' $a
    Set-Light $brokerLight $brokerCard 'Broker' $b
    Set-Light $snowLumaLight $snowLumaCard 'SnowLuma' $s
    $gpu = Get-GpuInfo
    if ($gpu) {
        $gpuText.Text = ('{0:N1} / {1:N1} GB' -f ($gpu.UsedMB / 1024), ($gpu.TotalMB / 1024))
        $pct = 0
        if ($gpu.TotalMB -gt 0) { $pct = [math]::Round(($gpu.UsedMB / $gpu.TotalMB) * 100, 1) }
        $gpuBar.Value = $pct
    } else {
        $gpuText.Text = T 'GPU 读取失败' 'GPU read failed'
        $gpuBar.Value = 0
    }
    $provider = Get-ProviderInfo $script:ProjectRoot
    $providerText.Text = "$($provider.Mode) / $($provider.Name) / $($provider.Model)"
}

$auditGrid.ItemsSource = @(Get-AuditTail $script:ProjectRoot 10)
$promptBox.Text = Get-PersonaPrompt $script:ProjectRoot
$games = @(Get-GameWhitelist $script:ProjectRoot)
$gameCountText.Text = if ($script:CurrentLanguage -ne 'zh') { "Current allowlist: $($games.Count)" } else { "当前白名单：$($games.Count) 个" }
$gameListBox.ItemsSource = @($games | ForEach-Object { "$($_.Name)  [$($_.Source)]" })
$ignoreText.Text = (@(Get-GameIgnoreList $script:ProjectRoot) -join ', ')


$actionScript = $script:ActionScript
$gameModeScript = Join-Path $script:ProjectRoot 'tools\game-mode.ps1'
if (-not (Test-Path -LiteralPath $gameModeScript)) { $gameModeScript = Join-Path $toolsRoot 'game-mode.ps1' }
$manualGameFile = Join-Path $script:ProjectRoot 'tools\game-list.txt'

function Show-Message([string]$text, [string]$title = '') {
    if (-not $title) { $title = T 'Cyber-Butler 主控台' 'Cyber-Butler Dashboard' }
    if ($text -match '失败|错误|异常|Error|failed|exception') {
        if (Get-Command Write-UiError -ErrorAction SilentlyContinue) {
            Write-UiError ('dialog: ' + $title) $text
        }
    }
    [Windows.MessageBox]::Show($text, $title) | Out-Null
}

function Read-InputDialog([string]$title, [string]$prompt, $Owner = $null) {
    $w = New-Object Windows.Window
    $w.Title = $title
    $w.Width = 430
    $w.Height = 210
    $w.WindowStartupLocation = 'CenterScreen'
    $w.ShowInTaskbar = $false
    # Topmost keeps the prompt above the modal settings dialog; without it the
    # nested window can appear behind and look like "nothing happened".
    $w.Topmost = $true
    if ($Owner) { $w.Owner = $Owner }
    $panel = New-Object Windows.Controls.StackPanel
    $panel.Margin = '20'
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = $prompt
    $label.TextWrapping = 'Wrap'
    $panel.Children.Add($label) | Out-Null
    $box = New-Object Windows.Controls.TextBox
    $box.Margin = '0,12,0,12'
    $panel.Children.Add($box) | Out-Null
    $ok = New-Object Windows.Controls.Button
    $ok.Content = (T '确认' 'OK')
    $ok.Width = 80
    $ok.HorizontalAlignment = 'Right'
    $ok.Add_Click({ $w.DialogResult = $true })
    $panel.Children.Add($ok) | Out-Null
    $w.Content = $panel
    $w.Add_Loaded({ try { $box.Focus() | Out-Null } catch { } })
    $w.ShowDialog() | Out-Null
    return $box.Text
}

function Get-VersionLabel {
    $versionFile = Join-Path $script:ProjectRoot 'VERSION'
    if (Test-Path -LiteralPath $versionFile) {
        return (T '当前版本：' 'Current version: ') + 'v' + (Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8).Trim()
    }
    return (T '当前版本：未知' 'Current version: unknown')
}

function Show-UpdateDialog($info) {
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="发现新版本" Width="620" Height="480"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" x:Name="Title" Text="发现新版本" FontSize="22" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="1" x:Name="Versions" Margin="0,12,0,8" FontSize="14"/>
    <TextBox Grid.Row="2" x:Name="Notes" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto" Margin="0,8,0,12"/>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="Install" Content="立即更新" Width="110" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="Skip" Content="跳过此版本" Width="110" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="Later" Content="稍后提醒" Width="100" Height="34"/>
    </StackPanel>
  </Grid>
</Window>
'@
    $r = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dlg = [Windows.Markup.XamlReader]::Load($r)
    $dlg.Owner = $window
    $dlg.FindName('Title').Text = '发现新版本 v' + $info.latest
    $dlg.FindName('Versions').Text = "当前版本：$($info.current)    最新版本：$($info.latest)"
    $notes = [string]$info.body
    if ($notes.Length -gt 500) { $notes = $notes.Substring(0, 500) + '...' }
    $dlg.FindName('Notes').Text = $notes
    $dlg.FindName('Skip').Add_Click({
        $skipPath = Join-Path $script:ProjectRoot 'tools\skip_version.json'
        @{ schema = 1; version = [string]$info.latest; skipped_at = (Get-Date).ToString('o') } |
            ConvertTo-Json | Set-Content -LiteralPath $skipPath -Encoding UTF8
        $dlg.Close()
    })
    $dlg.FindName('Later').Add_Click({ $dlg.Close() })
    $dlg.FindName('Install').Add_Click({
        $phrase = Read-InputDialog '生产更新确认' '这是生产环境更新。请输入 UPDATE PRODUCTION：'
        if ($phrase -cne 'UPDATE PRODUCTION') { return }
        $dlg.Close()
        Start-ElevatedUpdate
    })
    $dlg.ShowDialog() | Out-Null
}

function Start-UpdateCheck([bool]$Manual = $false) {
    if ($script:checkProcess -and -not $script:checkProcess.HasExited) { return }
    if (-not (Test-Path -LiteralPath $script:CheckScript)) {
        if ($Manual) { Show-Message ('找不到更新检查脚本：' + $script:CheckScript) }
        return
    }
    $script:manualCheck = $Manual
    $script:checkStatusFile = Join-Path $env:TEMP ('cyberbutler-check-' + [guid]::NewGuid().ToString('N') + '.json')
    Remove-Item -LiteralPath $script:checkStatusFile -Force -ErrorAction SilentlyContinue
    $argString = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script:CheckScript + '" -ProjectRoot "' + $script:ProjectRoot + '" -StatusFile "' + $script:checkStatusFile + '"'
    $script:checkProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $argString -WindowStyle Hidden -PassThru
    $checkTimer.Start()
}

function Invoke-ManualUpdateCheck {
    $status = Join-Path $env:TEMP ('cyberbutler-manual-' + [guid]::NewGuid().ToString('N') + '.json')
    try {
        if (-not (Test-Path -LiteralPath $script:CheckScript)) {
            throw ('找不到更新检查脚本：' + $script:CheckScript)
        }
        Remove-Item -LiteralPath $status -Force -ErrorAction SilentlyContinue
        & $script:CheckScript -ProjectRoot $script:ProjectRoot -StatusFile $status | Out-Null
        if (-not (Test-Path -LiteralPath $status)) { throw 'check_update.ps1 did not write its status file' }
        $info = Get-Content -LiteralPath $status -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($info.update_available -and -not $info.skipped) {
            Show-UpdateDialog $info
        } elseif ($info.skipped) {
            Show-Message ("已跳过 v" + $info.latest + "。删除 tools\skip_version.json 后可重新提示。")
        } else {
            Show-Message ("当前已是最新版本 v" + $info.current + "。")
        }
    } catch {
        Show-Message ('检查更新失败：' + $_.Exception.Message)
    } finally {
        Remove-Item -LiteralPath $status -Force -ErrorAction SilentlyContinue
    }
}

function Start-ElevatedUpdate {
    try {
        $script:updateStatusFile = Join-Path $env:TEMP ('cyberbutler-update-' + [guid]::NewGuid().ToString('N') + '.json')
        Remove-Item -LiteralPath $script:updateStatusFile -Force -ErrorAction SilentlyContinue
        $argString = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script:MergeScript + '" -TargetRoot "' + $script:ProjectRoot + '" -PythonPath "' + (Join-Path $script:ProjectRoot 'AstrBot\.venv\Scripts\python.exe') + '" -ConfirmationText "UPDATE PRODUCTION" -StatusFile "' + $script:updateStatusFile + '"'
        $script:updateProcess = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argString -PassThru
        $updateProgressBar.Visibility = 'Visible'
        $updateStatusText.Visibility = 'Visible'
        $updateProgressBar.Value = 0
        $updateStatusText.Text = '正在请求管理员权限并准备更新...'
        $updateTimer.Start()
    } catch {
        Show-Message ('无法启动管理员更新：' + $_.Exception.Message)
    }
}

function Invoke-ElevatedAction([string]$Action, [hashtable]$Extra = @{}) {
    $argParts = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $actionScript + '"'),
        '-Action', $Action,
        '-ProjectRoot', ('"' + $script:ProjectRoot + '"')
    )
    foreach ($key in $Extra.Keys) {
        $argParts += ('-' + $key)
        $argParts += ('"' + ([string]$Extra[$key]).Replace('"', '\"') + '"')
    }
    $proc = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList ($argParts -join ' ') -PassThru
    $proc.WaitForExit()
    return $proc.ExitCode
}

function Refresh-DashboardData {
    $auditGrid.ItemsSource = @(Get-AuditTail $script:ProjectRoot 10)
    $games = @(Get-GameWhitelist $script:ProjectRoot)
    $gameCountText.Text = if ($script:CurrentLanguage -ne 'zh') { "Current allowlist: $($games.Count)" } else { "当前白名单：$($games.Count) 个" }
    $gameListBox.ItemsSource = @($games | ForEach-Object { "$($_.Name)  [$($_.Source)]" })
    $ignoreText.Text = (@(Get-GameIgnoreList $script:ProjectRoot) -join ', ')
}

function Show-AstrBotPluginList {
    try {
        $data = Get-AstrBotPluginList -ProjectRoot $script:ProjectRoot
        $view = New-Object System.Collections.ArrayList
        foreach ($plugin in $data.Plugins) {
            $state = T '未知' 'Unknown'
            if ($plugin.Reserved) { $state = T '内置' 'Built-in' }
            elseif ($plugin.Activated -eq $true) { $state = T '启用' 'Enabled' }
            elseif ($plugin.Activated -eq $false) { $state = T '禁用' 'Disabled' }
            $compat = T '兼容' 'Compatible'
            if (-not $plugin.Compat) { $compat = T '不兼容' 'Incompatible' }
            [void]$view.Add([pscustomobject]@{
                Name           = $plugin.Name
                DisplayName    = $plugin.DisplayName
                Version        = $plugin.Version
                Author         = $plugin.Author
                StateText      = $state
                CompatText     = $compat
                CompatReason   = $plugin.CompatReason
                RootDirName    = $plugin.RootDirName
                Reserved       = $plugin.Reserved
                Activated      = $plugin.Activated
                Desc           = $plugin.Desc
                Repo           = $plugin.Repo
                AstrBotVersion = $plugin.AstrBotVersion
                ConfigPath     = $plugin.ConfigPath
                Platforms      = (@($plugin.Platforms) -join ', ')
            })
        }
        $pluginGrid.ItemsSource = @($view)
        $suffix = ''
        if ($data.ApiError) { $suffix = T '（AstrBot 离线，仅显示磁盘信息）' ' (AstrBot offline; disk data only)' }
        if ($script:CurrentLanguage -ne 'zh') {
            $pluginStatusText.Text = ('AstrBot v' + $data.Version + ' · ' + @($view).Count + ' plugins' + $suffix)
        } else {
            $pluginStatusText.Text = ('AstrBot v' + $data.Version + ' · ' + @($view).Count + ' 个插件' + $suffix)
        }
    } catch {
        Write-UiError 'plugin list' $_
        $pluginStatusText.Text = (T '读取失败：' 'Load failed: ') + $_.Exception.Message
    }
}

function Get-SelectedAstrBotPlugin {
    $item = $pluginGrid.SelectedItem
    if (-not $item) { Show-Message (T '请先在列表中选择一个插件。' 'Select a plugin in the list first.'); return $null }
    return $item
}

$pluginGrid.Add_SelectionChanged({
    $item = $pluginGrid.SelectedItem
    if (-not $item) { return }
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add([string]$item.Name)
    [void]$lines.Add('版本 ' + $item.Version + ' · 作者 ' + $item.Author + ' · 状态 ' + $item.StateText)
    $compatLine = '兼容性：' + $item.CompatText
    if ($item.CompatReason) { $compatLine += ' · ' + $item.CompatReason }
    [void]$lines.Add($compatLine)
    [void]$lines.Add('目录：AstrBot\data\plugins\' + $item.RootDirName)
    if ($item.ConfigPath) { [void]$lines.Add('配置：' + $item.ConfigPath) }
    if ($item.Platforms) { [void]$lines.Add('平台：' + $item.Platforms) }
    if ($item.Desc) { [void]$lines.Add(''); [void]$lines.Add([string]$item.Desc) }
    if ($item.Repo) { [void]$lines.Add(''); [void]$lines.Add('仓库：' + $item.Repo) }
    $pluginDetailText.Text = ($lines -join [Environment]::NewLine)
})

$pluginRefreshButton.Add_Click({ Show-AstrBotPluginList })

$pluginEnableButton.Add_Click({
    $item = Get-SelectedAstrBotPlugin
    if (-not $item) { return }
    try {
        $message = Set-AstrBotPluginEnabled -ProjectRoot $script:ProjectRoot -PluginId $item.Name -Enabled $true
        Show-AstrBotPluginList
        $pluginStatusText.Text = $message
    } catch {
        Show-Message ((T '启用失败：' 'Enable failed: ') + $_.Exception.Message)
    }
})

$pluginDisableButton.Add_Click({
    $item = Get-SelectedAstrBotPlugin
    if (-not $item) { return }
    try {
        $message = Set-AstrBotPluginEnabled -ProjectRoot $script:ProjectRoot -PluginId $item.Name -Enabled $false
        Show-AstrBotPluginList
        $pluginStatusText.Text = $message
    } catch {
        Show-Message ((T '禁用失败：' 'Disable failed: ') + $_.Exception.Message)
    }
})

$pluginDeleteButton.Add_Click({
    $item = Get-SelectedAstrBotPlugin
    if (-not $item) { return }
    if ($item.Reserved) { Show-Message '这是 AstrBot 保留插件，不能删除。'; return }
    $answer = Read-InputDialog '删除插件' ('将把 ' + $item.Name + ' 移动到 backups\deleted_plugins\，不会直接删除。' + [Environment]::NewLine + [Environment]::NewLine + '输入 DELETE PLUGIN 继续：')
    if ($answer -cne 'DELETE PLUGIN') { Show-Message '确认文本不正确，已取消。'; return }
    try {
        if ($item.Activated -eq $true) {
            Set-AstrBotPluginEnabled -ProjectRoot $script:ProjectRoot -PluginId $item.Name -Enabled $false | Out-Null
        }
        $record = Move-AstrBotPluginToRecycleBin -ProjectRoot $script:ProjectRoot -RootDirName $item.RootDirName
        try { Reload-AstrBotPlugins $script:ProjectRoot | Out-Null } catch { }
        Show-AstrBotPluginList
        Show-Message ('已移入回收站：' + [Environment]::NewLine + $record.destination)
    } catch {
        Show-Message ((T '删除失败：' 'Delete failed: ') + $_.Exception.Message)
    }
})

$pluginResetButton.Add_Click({
    $item = Get-SelectedAstrBotPlugin
    if (-not $item) { return }
    $answer = Read-InputDialog '恢复默认配置' ('将备份并删除 ' + $item.RootDirName + '_config.json，然后重新加载插件以生成默认配置。' + [Environment]::NewLine + [Environment]::NewLine + '输入 RESTORE DEFAULTS 继续：')
    if ($answer -cne 'RESTORE DEFAULTS') { Show-Message '确认文本不正确，已取消。'; return }
    try {
        $result = Restore-AstrBotPluginDefaults -ProjectRoot $script:ProjectRoot -PluginId $item.Name -RootDirName $item.RootDirName
        Show-AstrBotPluginList
        $message = '已恢复默认配置。'
        if ($result.BackupPath) { $message += [Environment]::NewLine + '原配置备份：' + $result.BackupPath }
        Show-Message $message
    } catch {
        Show-Message ((T '恢复失败：' 'Reset failed: ') + $_.Exception.Message)
    }
})

function Show-DashboardModuleList {
    $scan = Get-DashboardModules -ToolsRoot $script:ToolsRoot
    $view = New-Object System.Collections.ArrayList
    foreach ($module in $scan.Modules) {
        $status = if ($module.Problem) { T '错误' 'Error' } elseif ($module.Enabled) { T '启用' 'Enabled' } else { T '禁用' 'Disabled' }
        $display = '[' + $status + '] ' + $module.Name + ' v' + $module.Version
        if ($module.Author) { $display += ' · ' + $module.Author }
        if ($module.Problem) { $display += ' · ' + $module.Problem }
        elseif ($script:LoadedDashboardModules.ContainsKey($module.Id)) { $display += ' · ' + (T '已加载' 'loaded') }
        [void]$view.Add([pscustomobject]@{
            Display = $display
            Id      = $module.Id
            Enabled = $module.Enabled
            Problem = $module.Problem
            Module  = $module
        })
    }
    $officialModuleIds = @('hello_world', 'sys_monitor', 'quick_cmd')
    $thirdParty = @($scan.Modules | Where-Object { $_.Id -notin $officialModuleIds })
    if ($moduleTrustWarning) {
        $moduleTrustWarning.Visibility = if ($thirdParty.Count -gt 0) { 'Visible' } else { 'Collapsed' }
    }
    $moduleListBox.ItemsSource = @($view)
    if ($script:CurrentLanguage -ne 'zh') {
        $moduleStatusText.Text = ('{0} modules · {1} loaded' -f @($scan.Modules).Count, $script:LoadedDashboardModules.Count)
    } else {
        $moduleStatusText.Text = ('共 ' + @($scan.Modules).Count + ' 个模块 · 已加载 ' + $script:LoadedDashboardModules.Count)
    }
}

$moduleListBox.Add_SelectionChanged({
    $item = $moduleListBox.SelectedItem
    if (-not $item) { return }
    $module = $item.Module
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add([string]$module.Name + ' v' + $module.Version)
    [void]$lines.Add('id：' + $module.Id)
    [void]$lines.Add('目录：' + $module.Path)
    [void]$lines.Add('状态：' + $(if ($module.Problem) { '加载失败' } elseif ($module.Enabled) { '启用' } else { '禁用' }))
    if ($module.Description) { [void]$lines.Add(''); [void]$lines.Add([string]$module.Description) }
    if ($module.Problem) { [void]$lines.Add(''); [void]$lines.Add('错误：' + $module.Problem) }
    $moduleDetailText.Text = ($lines -join [Environment]::NewLine)
})

$moduleEnableButton.Add_Click({
    $item = $moduleListBox.SelectedItem
    if (-not $item) { Show-Message '请先选择一个模块。'; return }
    if ($item.Problem) { Show-Message ('该模块本身有问题，无法启用：' + $item.Problem); return }
    $result = Set-DashboardModuleEnabled -Id $item.Id -Enabled $true -Tabs $mainTabs -ToolsRoot $script:ToolsRoot
    if (-not $result.Ok) { Show-Message ('模块加载失败：' + $item.Id + [Environment]::NewLine + $result.Error) }
    Show-DashboardModuleList
})

$moduleDisableButton.Add_Click({
    $item = $moduleListBox.SelectedItem
    if (-not $item) { Show-Message '请先选择一个模块。'; return }
    Set-DashboardModuleEnabled -Id $item.Id -Enabled $false -Tabs $mainTabs -ToolsRoot $script:ToolsRoot | Out-Null
    Show-DashboardModuleList
})

$moduleRefreshButton.Add_Click({
    foreach ($id in @($script:LoadedDashboardModules.Keys)) {
        Unload-DashboardModule -Id $id -Tabs $mainTabs | Out-Null
    }
    $init = Initialize-DashboardModules -Tabs $mainTabs -ToolsRoot $script:ToolsRoot
    Show-DashboardModuleList
    if (@($init.Failed).Count -gt 0) {
        $names = @($init.Failed | ForEach-Object { $_.Name + '：' + $_.Error })
        Show-Message ('以下模块加载失败，已跳过：' + [Environment]::NewLine + [Environment]::NewLine + ($names -join [Environment]::NewLine))
    } else {
        $moduleStatusText.Text = '模块已重新加载。'
    }
})

$moduleFolderButton.Add_Click({
    try { Start-Process explorer.exe (Join-Path $script:ToolsRoot 'dashboard_plugins') } catch { Show-Message '无法打开模块目录。' }
})

function Show-PluginMarketResults {
    $source = 'official'
    if ($marketSourceCombo.SelectedIndex -eq 1) { $source = 'github' }
    [Windows.Input.Mouse]::OverrideCursor = [Windows.Input.Cursors]::Wait
    try {
        $entries = @(Get-PluginMarketEntries -Source $source -Query $marketQueryBox.Text -Limit 40)
        $view = New-Object System.Collections.ArrayList
        foreach ($entry in $entries) {
            $label = if ($entry.Source -eq 'github') { 'GitHub' } else { T '官方市场' 'Official' }
            [void]$view.Add([pscustomobject]@{
                Name        = $entry.Name
                Author      = $entry.Author
                Version     = $entry.Version
                Stars       = $entry.Stars
                SourceLabel = $label
                Entry       = $entry
            })
        }
        $marketGrid.ItemsSource = @($view)
        $marketStatusText.Text = if ($script:CurrentLanguage -ne 'zh') {
            ('{0} results' -f @($view).Count)
        } else {
            ('找到 ' + @($view).Count + ' 个结果')
        }
    } catch {
        Write-UiError 'market search' $_
        $marketStatusText.Text = (T '搜索失败：' 'Search failed: ') + $_.Exception.Message
    } finally {
        [Windows.Input.Mouse]::OverrideCursor = $null
    }
}

$marketSearchButton.Add_Click({ Show-PluginMarketResults })

$marketGrid.Add_SelectionChanged({
    $item = $marketGrid.SelectedItem
    if (-not $item) { return }
    $entry = $item.Entry
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add([string]$entry.Name)
    if ($entry.DisplayName) { [void]$lines.Add('显示名：' + $entry.DisplayName) }
    [void]$lines.Add('作者：' + $entry.Author + ' · 版本：' + $entry.Version)
    if ($entry.Stars) { [void]$lines.Add('GitHub 星标：' + $entry.Stars) }
    if ($entry.Downloads) { [void]$lines.Add('下载量：' + $entry.Downloads) }
    [void]$lines.Add('仓库：' + $entry.Repo)
    if ($entry.AstrBotVersion) { [void]$lines.Add('要求 AstrBot：' + $entry.AstrBotVersion) }
    if ($entry.Desc) { [void]$lines.Add(''); [void]$lines.Add([string]$entry.Desc) }
    $marketDetailText.Text = ($lines -join [Environment]::NewLine)
})

$marketInstallButton.Add_Click({
    $item = $marketGrid.SelectedItem
    if (-not $item) { Show-Message '请先选择一个插件。'; return }
    $entry = $item.Entry
    if (-not $entry.DownloadUrl) { Show-Message '该条目没有可用的下载地址。'; return }
    $confirm = [Windows.MessageBox]::Show(
        ('即将下载并审查：' + $entry.Name + [Environment]::NewLine + '来源：' + $entry.Repo + [Environment]::NewLine + [Environment]::NewLine + '继续？'),
        '安装插件', 'YesNo', 'Question')
    if ($confirm -ne 'Yes') { return }

    $work = Join-Path $env:TEMP ('cb-plugin-' + [guid]::NewGuid().ToString('N'))
    try {
        New-Item -ItemType Directory -Path $work -Force | Out-Null
        [Windows.Input.Mouse]::OverrideCursor = [Windows.Input.Cursors]::Wait
        $marketStatusText.Text = '正在下载...'
        $archive = Join-Path $work 'plugin.zip'
        Save-PluginArchive -Url $entry.DownloadUrl -Destination $archive | Out-Null

        $marketStatusText.Text = '正在解压...'
        $extract = Join-Path $work 'extract'
        Expand-PluginArchive -ArchivePath $archive -Destination $extract | Out-Null
        $packageRoot = Find-PluginPackageRoot $extract

        $marketStatusText.Text = '正在做静态安全审查...'
        $localVersion = Get-LocalAstrBotVersion $script:ProjectRoot
        $review = Get-PluginReviewSummary -PackageRoot $packageRoot -LocalVersion $localVersion

        [Windows.Input.Mouse]::OverrideCursor = $null
        $approved = Show-PluginReviewDialog -Review $review -SourceLabel ($item.SourceLabel + ' · ' + $entry.Repo) -TempPath $work
        if (-not $approved) { $marketStatusText.Text = '已取消安装。'; return }

        [Windows.Input.Mouse]::OverrideCursor = [Windows.Input.Cursors]::Wait
        $marketStatusText.Text = '正在安装...'
        $installed = Install-PluginPackage -ProjectRoot $script:ProjectRoot -PackageRoot $packageRoot -TargetKind 'agent'
        $reloadError = ''
        try { Reload-AstrBotPlugins $script:ProjectRoot | Out-Null } catch { $reloadError = $_.Exception.Message }
        Show-AstrBotPluginList
        $message = '安装完成：' + $installed.Id + [Environment]::NewLine + $installed.Path
        if ($reloadError) { $message += [Environment]::NewLine + [Environment]::NewLine + '插件已落盘，但重载失败：' + $reloadError }
        else { $message += [Environment]::NewLine + [Environment]::NewLine + 'AstrBot 已请求重载插件。' }
        Show-Message $message
        $marketStatusText.Text = '安装完成：' + $installed.Id
    } catch {
        Show-Message ((T '安装失败：' 'Install failed: ') + $_.Exception.Message)
        $marketStatusText.Text = '安装失败'
    } finally {
        [Windows.Input.Mouse]::OverrideCursor = $null
        try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
    }
})

function Save-ManualGameList([string[]]$lines) {
    $backup = $manualGameFile + '.bak-dashboard'
    if (Test-Path -LiteralPath $manualGameFile) { Copy-Item -LiteralPath $manualGameFile -Destination $backup -Force }
    [IO.File]::WriteAllLines($manualGameFile, $lines, (New-Object Text.UTF8Encoding($false)))
}

function Set-ManualGame([string]$name, [switch]$Remove) {
    $value = $name.Trim()
    if (-not $value -or $value.StartsWith('#')) { throw '进程名不能为空或以 # 开头' }
    if ($value -match '[\/:*?"<>|]') { throw '进程名不能包含路径或非法字符' }
    $lines = @()
    if (Test-Path -LiteralPath $manualGameFile) {
        $lines = @(Get-Content -LiteralPath $manualGameFile -Encoding UTF8)
    } else {
        $lines = @('# Optional extra game process names, one per line, without .exe.')
    }
    $filtered = @($lines | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') -and $_.Trim().ToLowerInvariant() -ne $value.ToLowerInvariant() })
    if (-not $Remove) { $filtered += $value }
    $comments = @($lines | Where-Object { $_.Trim().StartsWith('#') })
    Save-ManualGameList (@($comments + $filtered))
}

function Try-ClearConversationViaApi {
    $tokenFile = Join-Path $script:ProjectRoot '.astrbot_token'
    if (-not (Test-Path -LiteralPath $tokenFile)) { return $false }
    $token = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
    if (-not $token) { return $false }
    $overlay = Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'local-overlay.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $umo = [string]$overlay.values.YOUR_PLATFORM_ID + ':FriendMessage:' + [string]$overlay.values.YOUR_QQ_ID
    $headers = @{ Authorization = 'Bearer ' + $token }
    try {
        $query = [uri]::EscapeDataString($umo)
        $result = Invoke-RestMethod -Uri ("http://127.0.0.1:6185/api/conversation/conversations?umo=" + $query + "&page_size=100") -Headers $headers -TimeoutSec 10
        $data = $result
        if ($result.PSObject.Properties.Name -contains 'data') { $data = $result.data }
        $items = @($data)
        if ($data.PSObject.Properties.Name -contains 'items') { $items = @($data.items) }
        if (-not $items -or $items.Count -eq 0) { return $false }
        foreach ($item in $items) {
            $cid = [string]$item.conversation_id
            if (-not $cid) { $cid = [string]$item.id }
            $uid = [string]$item.user_id
            if (-not $uid) { $uid = $umo }
            if ($cid) {
                Invoke-RestMethod -Method Delete -Uri ("http://127.0.0.1:6185/api/conversation/conversations/" + [uri]::EscapeDataString($cid) + "?user_id=" + [uri]::EscapeDataString($uid)) -Headers $headers -TimeoutSec 10 | Out-Null
            }
        }
        return $true
    } catch { return $false }
}

$overlayFile = Join-Path $script:ProjectRoot 'local-overlay.json'
if (Test-Path -LiteralPath $overlayFile) {
    try {
        $overlay = Get-Content -LiteralPath $overlayFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $qqBox.Text = [string]$overlay.values.YOUR_QQ_ID
        if (Test-Path (Join-Path $script:ProjectRoot 'tools\deepseek.key.dpapi')) {
            $apiKeyBox.ToolTip = '已配置；留空表示不修改'
        } else {
            $apiKeyBox.ToolTip = '未配置；输入新 Key 后保存'
        }
    } catch { $qqBox.Text = 'overlay 读取失败' }
}

$restartButton.Add_Click({
    try {
        $code = Invoke-ElevatedAction 'RestartAstrBot'
        if ($code -eq 0) { Show-Message 'AstrBot 已重启。' } else { Show-Message '重启失败，请查看 AstrBot/data/dashboard-actions.log。' }
        Update-Dashboard
    } catch { Show-Message ('无法启动管理员操作：' + $_.Exception.Message) }
})

$vramButton.Add_Click({
    try {
        $code = Invoke-ElevatedAction 'ReleaseVram'
        if ($code -eq 0) { Show-Message '已请求释放本地模型显存。' } else { Show-Message '释放显存失败，请查看日志。' }
        Update-Dashboard
    } catch { Show-Message ('无法启动管理员操作：' + $_.Exception.Message) }
})

$logsButton.Add_Click({
    try { Start-Process explorer.exe (Join-Path $script:ProjectRoot 'AstrBot\data') } catch { Show-Message '无法打开日志目录。' }
})

$fuseButton.Add_Click({
    $answer = Read-InputDialog '紧急熔断' '这会立即停止 AstrBot 和 Broker，且不会自动重启。请输入 FUSE 确认：'
    if ($answer -cne 'FUSE') { Show-Message '确认文本不正确，已取消。'; return }
    try {
        $code = Invoke-ElevatedAction 'Fuse' @{ ConfirmationText = 'FUSE' }
        if ($code -eq 0) { Show-Message '紧急熔断完成：AstrBot 与 Broker 已停止。' } else { Show-Message '熔断失败，请查看日志。' }
        Update-Dashboard
    } catch { Show-Message ('无法启动管理员操作：' + $_.Exception.Message) }
})

$savePromptButton.Add_Click({
    $item = $personaListBox.SelectedItem
    if (-not $item) {
        Show-Message (T '请先选择一个人格。' 'Select a persona first.')
        return
    }
    try {
        $response = Invoke-AstrBotApi -Method POST -ApiPath '/api/persona/update' -Body @{
            persona_id    = $item.Id
            system_prompt = $promptBox.Text
        }
        if (-not $response -or $response.status -eq 'error') { throw [string]$response.message }
        $active = Get-AstrBotActivePersona
        if ($active -eq $item.Id) { $null = Set-AstrBotActivePersona $item.Id }
        Show-PersonaList
        Refresh-DashboardData
        Show-Message (T '人格提示词已保存，配置已重载。' 'Persona prompt saved and config reloaded.')
    } catch {
        Write-UiError 'persona save' $_
        Show-Message ((T '保存失败：' 'Save failed: ') + $_.Exception.Message)
    }
})

$clearConversationButton.Add_Click({
    if (Try-ClearConversationViaApi) {
        Show-Message '当前对话历史已通过 AstrBot API 清空。'
        return
    }
    $choice = [Windows.MessageBox]::Show('API 清空失败。是否使用停服兜底？这会短暂停止 AstrBot，并先备份数据库。', '清空对话', 'YesNo', 'Warning')
    if ($choice -ne 'Yes') { return }
    try {
        $overlay = Get-Content -LiteralPath (Join-Path $script:ProjectRoot 'local-overlay.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $umo = [string]$overlay.values.YOUR_PLATFORM_ID + ':FriendMessage:' + [string]$overlay.values.YOUR_QQ_ID
        $code = Invoke-ElevatedAction 'ClearConversation' @{ Umo = $umo }
        if ($code -eq 0) { Show-Message '当前对话历史已清空，AstrBot 已重启。' } else { Show-Message '清空失败，请查看日志。' }
    } catch { Show-Message ('清空失败：' + $_.Exception.Message) }
})

function Reset-ScanUi {
    try { $scanTimer.Stop() } catch { }
    $scanGamesButton.IsEnabled = $true
    $scanProgressBar.Visibility = 'Collapsed'
    $scanProgressBar.IsIndeterminate = $true
    $scanStatusText.Text = ''
    $script:scanProcess = $null
}

$scanGamesButton.Add_Click({
    if ($script:scanProcess -and -not $script:scanProcess.HasExited) { return }
    try {
        if (-not (Test-Path -LiteralPath $script:GameScanner)) { throw ('找不到扫描脚本：' + $script:GameScanner) }
        $script:scanStatusFile = Join-Path $env:TEMP ('cyberbutler-games-' + [guid]::NewGuid().ToString('N') + '.json')
        $script:scanOutFile = Join-Path $env:TEMP ('cyberbutler-game-out-' + [guid]::NewGuid().ToString('N') + '.log')
        $script:scanErrFile = Join-Path $env:TEMP ('cyberbutler-game-err-' + [guid]::NewGuid().ToString('N') + '.log')
        $script:scanStartedAt = Get-Date
        Remove-Item -LiteralPath $script:scanStatusFile,$script:scanOutFile,$script:scanErrFile -Force -ErrorAction SilentlyContinue
        $arguments = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $script:GameScanner + '" -ProjectRoot "' + $script:ProjectRoot + '" -StatusFile "' + $script:scanStatusFile + '" -WriteAuto'
        $script:scanProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $script:scanOutFile -RedirectStandardError $script:scanErrFile
        $scanProgressBar.Visibility = 'Visible'
        $scanProgressBar.IsIndeterminate = $true
        $scanStatusText.Text = '正在扫描 Steam / Epic / WeGame...'
        $scanGamesButton.IsEnabled = $false
        $scanTimer.Start()
    } catch {
        Reset-ScanUi
        Show-Message ('扫描失败：' + $_.Exception.Message)
    }
})

$addGameButton.Add_Click({
    try { Set-ManualGame $gameInput.Text; $gameInput.Text = ''; Refresh-DashboardData; Show-Message '已加入手动白名单。' }
    catch { Show-Message ('添加失败：' + $_.Exception.Message) }
})

$removeGameButton.Add_Click({
    $selected = [string]$gameListBox.SelectedItem
    if (-not $selected) { Show-Message '请先选中一个条目。'; return }
    $name = ($selected -replace '\s+\[(AUTO|MANUAL)\]$', '').Trim()
    try { Set-ManualGame $name -Remove; Refresh-DashboardData; Show-Message '已从手动白名单移除（自动条目不会被删除）。' }
    catch { Show-Message ('移除失败：' + $_.Exception.Message) }
})

$saveConfigButton.Add_Click({
    try {
        $qq = $qqBox.Text.Trim()
        if ($qq -notmatch '^\d{5,12}$') { throw 'QQ 号必须是 5-12 位数字。' }
        $overlayPath = Join-Path $script:ProjectRoot 'local-overlay.json'
        $overlay = Get-Content -LiteralPath $overlayPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $overlay.values.YOUR_QQ_ID = $qq
        Copy-Item -LiteralPath $overlayPath -Destination ($overlayPath + '.bak-dashboard') -Force
        [IO.File]::WriteAllText($overlayPath, ($overlay | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        $gate = Join-Path $script:ProjectRoot 'AstrBot\data\config\astrbot_plugin_at_gate_config.json'
        if (Test-Path -LiteralPath $gate) {
            Copy-Item -LiteralPath $gate -Destination ($gate + '.bak-dashboard') -Force
            $cfg = Get-Content -LiteralPath $gate -Raw -Encoding UTF8 | ConvertFrom-Json
            $cfg.owner_ids = $qq
            [IO.File]::WriteAllText($gate, ($cfg | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        }
        if ($apiKeyBox.Password) {
            $tempSecret = Join-Path $env:TEMP ('cyberbutler-key-' + [guid]::NewGuid().ToString('N') + '.txt')
            [IO.File]::WriteAllBytes($tempSecret, [Text.Encoding]::UTF8.GetBytes($apiKeyBox.Password))
            & icacls $tempSecret /inheritance:r /grant:r ("${env:USERNAME}:(F)") | Out-Null
            $code = Invoke-ElevatedAction 'SaveApiKey' @{ SecretFile = $tempSecret }
            Remove-Item -LiteralPath $tempSecret -Force -ErrorAction SilentlyContinue
            if ($code -ne 0) { throw 'API Key 加密保存失败。' }
            $apiKeyBox.Password = ''
        }
        $choice = [Windows.MessageBox]::Show('配置已保存。AstrBot 需要重启后才会使用新 QQ/API Key。现在重启吗？', '保存成功', 'YesNo', 'Question')
        if ($choice -eq 'Yes') {
            $code = Invoke-ElevatedAction 'RestartAstrBot'
            if ($code -ne 0) { Show-Message '配置已保存，但 AstrBot 重启失败。' }
        }
        Update-Dashboard
    } catch { Show-Message ('保存失败：' + $_.Exception.Message) }
})

$astrBotLight.Add_MouseLeftButtonDown({
    try { Start-Process 'http://127.0.0.1:6185' } catch { Write-UiError 'open AstrBot WebUI' $_; Show-Message ((T '无法打开浏览器：' 'Cannot open browser: ') + $_.Exception.Message) }
})
$snowLumaLight.Add_MouseLeftButtonDown({
    try { Start-Process 'http://127.0.0.1:5099' } catch { Write-UiError 'open SnowLuma WebUI' $_; Show-Message ((T '无法打开浏览器：' 'Cannot open browser: ') + $_.Exception.Message) }
})
$brokerLight.Add_MouseLeftButtonDown({
    Show-Message (T 'TOTP Broker 为后台无头服务，无 Web 管理界面。' 'The TOTP Broker is a headless background service and has no web UI.')
})

function Show-PersonaList {
    try {
        $personas = @(Get-AstrBotPersonaList)
        $active = [string](Get-AstrBotActivePersona)
        $view = New-Object System.Collections.ArrayList
        foreach ($persona in $personas) {
            $id = [string]$persona.persona_id
            if (-not $id) { continue }
            $display = $id
            if ($id -eq $active) {
                $display += '  ' + (T '（当前）' '(active)')
            }
            [void]$view.Add([pscustomobject]@{
                Display = $display
                Id      = $id
                Prompt  = [string]$persona.system_prompt
            })
        }
        $personaListBox.ItemsSource = @($view)
        $personaStatusText.Text = ((T '{0} 个人格' '{0} personas') -f @($view).Count)
        $personaActiveText.Text = ((T '当前人格：' 'Active persona: ') + $active)
        $selected = @($view | Where-Object { $_.Id -eq $active }) | Select-Object -First 1
        if ($selected) {
            $personaListBox.SelectedItem = $selected
            $promptBox.Text = $selected.Prompt
        }
    } catch {
        Write-UiError 'persona list' $_
        $personaStatusText.Text = T '人格列表读取失败' 'Failed to load personas'
    }
}

$personaListBox.Add_SelectionChanged({
    $item = $personaListBox.SelectedItem
    if (-not $item) { return }
    $promptBox.Text = [string]$item.Prompt
})

$personaRefreshButton.Add_Click({ Show-PersonaList })

$personaSwitchButton.Add_Click({
    $item = $personaListBox.SelectedItem
    if (-not $item) { Show-Message (T '请先选择一个人格。' 'Select a persona first.'); return }
    try {
        $null = Set-AstrBotActivePersona $item.Id
        Show-PersonaList
        Refresh-DashboardData
        Show-Message ((T '已切换人格并重载配置：' 'Persona switched and config reloaded: ') + $item.Id)
    } catch {
        Write-UiError 'persona switch' $_
        Show-Message ((T '切换失败：' 'Switch failed: ') + $_.Exception.Message)
    }
})

$personaNewButton.Add_Click({
    $id = Read-InputDialog (T '新建空白人格' 'New blank persona') (T '输入新人格的唯一名称：' 'Enter a unique name for the new persona:') $window
    if (-not $id) { return }
    $id = $id.Trim()
    if (-not $id) { return }
    $blank = if ($script:CurrentLanguage -ne 'zh') {
        'You are a new persona. Describe the character, tone and boundaries here.'
    } else {
        '你是一个新的人格。请在这里写人格设定、语气和边界。'
    }
    try {
        $null = New-AstrBotPersona -PersonaId $id -SystemPrompt $blank
        Show-PersonaList
        Show-Message ((T '已新建空白人格：' 'Blank persona created: ') + $id)
    } catch {
        Write-UiError 'persona create' $_
        Show-Message ((T '新建失败：' 'Create failed: ') + $_.Exception.Message)
    }
})

$personaCopyButton.Add_Click({
    $item = $personaListBox.SelectedItem
    if (-not $item) { Show-Message (T '请先选择一个人格。' 'Select a persona first.'); return }
    $id = Read-InputDialog (T '复制当前人格' 'Copy current persona') ((T '把 ' 'Copy ') + $item.Id + (T ' 复制为新人格，输入新名称：' ' into a new persona. Enter the new name:')) $window
    if (-not $id) { return }
    $id = $id.Trim()
    if (-not $id) { return }
    try {
        $null = Copy-AstrBotPersona -SourceId $item.Id -PersonaId $id
        Show-PersonaList
        Show-Message ((T '已复制人格：' 'Persona copied: ') + $id)
    } catch {
        Write-UiError 'persona copy' $_
        Show-Message ((T '复制失败：' 'Copy failed: ') + $_.Exception.Message)
    }
})

$personaDeleteButton.Add_Click({
    $item = $personaListBox.SelectedItem
    if (-not $item) { Show-Message (T '请先选择一个人格。' 'Select a persona first.'); return }
    if ($item.Id -eq 'default') { Show-Message (T '默认人格不能删除。' 'The default persona cannot be deleted.'); return }
    $answer = Read-InputDialog (T '删除人格' 'Delete persona') ((T '将把 ' 'The persona ') + $item.Id + (T ' 备份到 backups\personas 后删除。' ' will be backed up to backups\personas and then deleted.') + [Environment]::NewLine + [Environment]::NewLine + (T '输入 DELETE PERSONA 继续：' 'Type DELETE PERSONA to continue:')) $window
    if ($answer -cne 'DELETE PERSONA') { Show-Message (T '确认文本不正确，已取消。' 'Confirmation text did not match; cancelled.'); return }
    try {
        $removed = Remove-AstrBotPersona -PersonaId $item.Id -ProjectRoot $script:ProjectRoot
        Show-PersonaList
        Show-Message ((T '已删除人格。备份：' 'Persona deleted. Backup: ') + $removed.Backup)
    } catch {
        Write-UiError 'persona delete' $_
        Show-Message ((T '删除失败：' 'Delete failed: ') + $_.Exception.Message)
    }
})

$errorCopyButton.Add_Click({
    if (Copy-UiErrorLog) {
        $errorStatusText.Text = T '已复制到剪贴板' 'Copied to clipboard'
    } else {
        Show-Message (T '没有可复制的错误信息，或剪贴板被占用。' 'No error text to copy, or the clipboard is busy.')
    }
})
$errorClearButton.Add_Click({ Clear-UiErrorLog })
$errorRefreshButton.Add_Click({ Register-UiErrorBox $errorLogBox $errorStatusText })

$settingsButton.Add_Click({ Show-SettingsDialog })
$startupSettings = Read-DashboardSettings
Set-UiTheme $startupSettings.theme
Set-UiBackground $startupSettings.background $startupSettings | Out-Null
Apply-Language $startupSettings.language

if ($SmokeBackground) {
    $report = Invoke-BgSmokeTest $SmokeAssetDir
    $report | ConvertTo-Json -Depth 5
    exit 0
}

$script:checkProcess = $null
$script:updateProcess = $null
$script:checkStatusFile = ''
$script:updateStatusFile = ''
$script:manualCheck = $false

$checkTimer = New-Object Windows.Threading.DispatcherTimer
$checkTimer.Interval = [TimeSpan]::FromMilliseconds(600)
$checkTimer.Add_Tick({
    if (-not $script:checkProcess -or -not $script:checkProcess.HasExited) { return }
    $checkTimer.Stop()
    $info = $null
    if ($script:checkStatusFile -and (Test-Path -LiteralPath $script:checkStatusFile)) {
        try { $info = Get-Content -LiteralPath $script:checkStatusFile -Raw -Encoding UTF8 | ConvertFrom-Json } catch { $info = $null }
    }
    if ($info -and $info.update_available -and -not $info.skipped) {
        Show-UpdateDialog $info
    } elseif ($script:manualCheck) {
        if ($info -and $info.skipped) {
            Show-Message ("已跳过 v" + $info.latest + "。删除 tools\skip_version.json 后可重新提示。")
        } elseif ($info) {
            Show-Message ("当前已是最新版本 v" + $info.current + "。")
        } else {
            Show-Message '检查更新失败，请查看 check_update.ps1 输出。'
        }
    }
    Remove-Item -LiteralPath $script:checkStatusFile -Force -ErrorAction SilentlyContinue
})

$updateTimer = New-Object Windows.Threading.DispatcherTimer
$updateTimer.Interval = [TimeSpan]::FromSeconds(1)
$updateTimer.Add_Tick({
    if ($script:updateStatusFile -and (Test-Path -LiteralPath $script:updateStatusFile)) {
        try {
            $state = Get-Content -LiteralPath $script:updateStatusFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($state.progress) { $updateProgressBar.Value = [int]$state.progress }
            if ($state.message) { $updateStatusText.Text = [string]$state.message }
        } catch { }
    }
    if (-not $script:updateProcess -or -not $script:updateProcess.HasExited) { return }
    $updateTimer.Stop()
    $code = $script:updateProcess.ExitCode
    Remove-Item -LiteralPath $script:updateStatusFile -Force -ErrorAction SilentlyContinue
    if ($code -eq 0) {
        $updateProgressBar.Value = 100
        $updateStatusText.Text = '更新完成，苏瑾言已重启。'
        Show-Message '更新完成，苏瑾言已重启。'
    } else {
        $updateStatusText.Text = '更新失败，已尝试回滚。'
        Show-Message '更新失败，已尝试回滚。请查看 backups 下的 update.log。'
    }
})

$script:scanProcess = $null
$script:scanStatusFile = ''
$script:scanOutFile = ''
$script:scanErrFile = ''
$script:scanStartedAt = Get-Date
$scanTimer = New-Object Windows.Threading.DispatcherTimer
$scanTimer.Interval = [TimeSpan]::FromSeconds(1)
$scanTimer.Add_Tick({
    if ($script:scanStatusFile -and (Test-Path -LiteralPath $script:scanStatusFile)) {
        try {
            $state = Get-Content -LiteralPath $script:scanStatusFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($state -and $state.message) { $scanStatusText.Text = [string]$state.message }
        } catch { }
    }
    if (-not $script:scanProcess) { Reset-ScanUi; return }
    $elapsed = ((Get-Date) - $script:scanStartedAt).TotalSeconds
    if (-not $script:scanProcess.HasExited -and $elapsed -gt 60) {
        try { Stop-Process -Id $script:scanProcess.Id -Force -ErrorAction SilentlyContinue } catch { }
        $tail = @()
        if ($script:scanErrFile -and (Test-Path -LiteralPath $script:scanErrFile)) { $tail = @(Get-Content -LiteralPath $script:scanErrFile -Tail 10 -ErrorAction SilentlyContinue) }
        Reset-ScanUi
        Show-Message ("扫描超时（60 秒），已终止后台进程。`n`n" + (($tail -join "`n")))
        return
    }
    if (-not $script:scanProcess.HasExited) { return }
    $proc = $script:scanProcess
    $rawCode = $null
    try { if ($proc) { $rawCode = $proc.ExitCode } } catch { $rawCode = $null }
    $code = if ($null -eq $rawCode) { -1 } else { [int]$rawCode }
    $result = $null
    if ($script:scanStatusFile -and (Test-Path -LiteralPath $script:scanStatusFile)) {
        try { $result = Get-Content -LiteralPath $script:scanStatusFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction SilentlyContinue } catch { $result = $null }
    }
    $tail = @()
    if ($script:scanErrFile -and (Test-Path -LiteralPath $script:scanErrFile)) { $tail = @(Get-Content -LiteralPath $script:scanErrFile -Tail 10 -ErrorAction SilentlyContinue) }
    Reset-ScanUi
    try { Refresh-DashboardData } catch { }
    if ($null -eq $result) {
        Show-Message '扫描结果为空，可能是脚本崩溃或输出了非 JSON 格式。'
        Remove-Item -LiteralPath $script:scanStatusFile,$script:scanOutFile,$script:scanErrFile -Force -ErrorAction SilentlyContinue
        return
    }
    if (($code -ne 0 -and $code -ne -1) -or ($result.status -eq 'failed')) {
        $detail = if ($result -and $result.error) { [string]$result.error } else { ($tail -join "`n") }
        $exitText = if ($null -eq $rawCode) { 'null' } else { [string]$rawCode }
        Show-Message ("扫描失败（exit=$exitText）。`n`n" + $detail)
    } elseif ($result) {
        $extra = if ($result.auto_written -eq $false) { "`n`n提示：白名单文件写入被拒绝，本次仅显示扫描结果。" } else { '' }
        Show-Message ("扫描完成：Steam $($result.steam) 个、Epic $($result.epic) 个、WeGame $($result.wegame) 个。$extra")
    } else {
        Show-Message ('扫描失败：没有生成结果文件。`n`n' + ($tail -join "`n"))
    }
    Remove-Item -LiteralPath $script:scanStatusFile,$script:scanOutFile,$script:scanErrFile -Force -ErrorAction SilentlyContinue
})

if ($SmokeSettingsDialog) {
    if ($SmokeTheme) { Set-UiTheme $SmokeTheme }
    Show-SettingsDialog -SmokeOnly -ShotPath $SmokeSettingsShot
    exit 0
}

if ($SmokeThemes) {
    Set-UiTheme 'dark'
    $md = $window.Resources.MergedDictionaries
    $theme = $md[0]
    $darkPage = [string]$theme['PageBrush'].Color
    Set-UiTheme 'light'
    $md = $window.Resources.MergedDictionaries
    $theme = $md[0]
    $lightPage = [string]$theme['PageBrush'].Color
    Write-Output ('MERGED=' + $md.Count + ' DARK_PAGE=' + $darkPage + ' LIGHT_PAGE=' + $lightPage + ' CONTAINS=' + $theme.Contains('PageBrush'))
    exit 0
}

if ($SmokeUi) {
    Register-DashboardModuleExceptionHook $window
    $null = Initialize-DashboardModules -Tabs $mainTabs -ToolsRoot $script:ToolsRoot
    Show-AstrBotPluginList
    Show-DashboardModuleList
    Show-PersonaList
    $window.WindowStyle = 'None'
    $window.ShowInTaskbar = $false
    $window.WindowStartupLocation = 'Manual'
    $window.Left = -6000
    $window.Top = -6000
    $window.Show()
    Wait-BgDispatcher 900
    $shots = New-Object System.Collections.ArrayList
    foreach ($page in @(@{ Index = 2; Name = 'persona' }, @{ Index = 4; Name = 'plugins' }, @{ Index = 5; Name = 'modules' }, @{ Index = 6; Name = 'market' }, @{ Index = 7; Name = 'logs' }, @{ Index = 9; Name = 'quick' }, @{ Index = 10; Name = 'sysmon' })) {
        $mainTabs.SelectedIndex = [int]$page.Index
        Wait-BgDispatcher 450
        $shot = Save-BgScreenshot (Join-Path $env:TEMP ('cb-ui-' + $page.Name + '.png'))
        if ($shot) { [void]$shots.Add($shot) }
    }
    $moduleTab = @($mainTabs.Items | Where-Object { $_.Tag -eq 'hello_world' }) | Select-Object -First 1
    if ($moduleTab) {
        $mainTabs.SelectedItem = $moduleTab
        Wait-BgDispatcher 450
        $shot = Save-BgScreenshot (Join-Path $env:TEMP 'cb-ui-module.png')
        if ($shot) { [void]$shots.Add($shot) }
    }
    Write-Output ('UI_SHOTS=' + ($shots -join ';'))
    $window.Close()
    exit 0
}

Register-DashboardModuleExceptionHook $window
$moduleInit = Initialize-DashboardModules -Tabs $mainTabs -ToolsRoot $script:ToolsRoot
$window.Add_ContentRendered({
    Show-AstrBotPluginList
    Show-DashboardModuleList
    Show-PersonaList
    if (@($moduleInit.Failed).Count -gt 0) {
        foreach ($failedModule in @($moduleInit.Failed)) {
            Write-UiError ('module load: ' + $failedModule.Id) $failedModule.Error
        }
        $names = @($moduleInit.Failed | ForEach-Object { $_.Name + '：' + $_.Error })
        $moduleStatusText.Text = '模块加载失败：' + $names.Count
        Show-Message ('以下模块加载失败，已跳过（主控台不受影响）：' + [Environment]::NewLine + [Environment]::NewLine + ($names -join [Environment]::NewLine))
    }
})

$versionLabel.Text = Get-VersionLabel
$versionLabel.Add_MouseLeftButtonDown({ Invoke-ManualUpdateCheck })

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ Update-Dashboard })
Update-Dashboard
$timer.Start()
Start-UpdateCheck $false
$window.ShowDialog() | Out-Null
