#Requires -Version 5.1
<#
Cyber-Butler Dashboard - pure security status panel.
Only security audit, network whitelist and system settings remain.
#>
param([string]$ProjectRoot = '', [switch]$SmokeTest)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$toolsRoot = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $toolsRoot }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
. (Join-Path $toolsRoot 'dashboard_core.ps1')

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
 Title="Cyber-Butler" Width="980" Height="680" WindowStartupLocation="CenterScreen"
 Background="#0B0E14" Foreground="#E6EDF7" FontFamily="Segoe UI">
 <Grid Margin="24">
  <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
  <StackPanel Orientation="Horizontal"><TextBlock Text="CYBER-BUTLER" FontSize="12" Foreground="#58E1C1" FontWeight="SemiBold"/><TextBlock Text="  SECURITY CONSOLE" FontSize="12" Foreground="#6B7A90"/></StackPanel>
  <Grid Grid.Row="1" Margin="0,18,0,18">
   <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
   <StackPanel><TextBlock Text="安全状态" FontSize="30" FontWeight="SemiBold"/><TextBlock x:Name="Subtitle" Text="Broker 状态读取中" Margin="0,6,0,0" Foreground="#8B9AB0" FontSize="13"/></StackPanel>
   <Border Grid.Column="1" Background="#121824" BorderBrush="#243044" BorderThickness="1" CornerRadius="12" Padding="16,10"><StackPanel Orientation="Horizontal"><Ellipse x:Name="BrokerDot" Width="9" Height="9" Fill="#6B7A90" Margin="0,0,8,0"/><TextBlock x:Name="BrokerState" Text="检测中" FontSize="13"/></StackPanel></Border>
  </Grid>
  <TabControl Grid.Row="2" Background="Transparent" BorderThickness="0">
   <TabItem Header="安全风控"><Border Background="#121824" BorderBrush="#243044" BorderThickness="1" CornerRadius="14" Padding="16" Margin="0,8,0,0"><DockPanel>
    <StackPanel DockPanel.Dock="Top" Orientation="Horizontal" Margin="0,0,0,10"><TextBlock Text="最近的 TOTP 审批与拦截" FontSize="15" FontWeight="SemiBold" VerticalAlignment="Center"/><Button x:Name="RefreshAudit" Content="刷新" Width="72" Height="30" Margin="14,0,0,0"/></StackPanel>
    <DataGrid x:Name="AuditGrid" IsReadOnly="True" AutoGenerateColumns="True" CanUserAddRows="False" HeadersVisibility="Column" Background="#0E141E" Foreground="#DCE7F5" BorderBrush="#243044" RowBackground="#0E141E"/>
   </DockPanel></Border></TabItem>
   <TabItem Header="网络白名单"><Border Background="#121824" BorderBrush="#243044" BorderThickness="1" CornerRadius="14" Padding="18" Margin="0,8,0,0"><StackPanel>
    <TextBlock Text="受保护目录" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="ProtectedRoot" Margin="0,8,0,16" Foreground="#9FB0C6"/>
    <TextBlock Text="出站白名单" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="WhitelistText" Margin="0,8,0,0" Foreground="#9FB0C6" TextWrapping="Wrap"/>
   </StackPanel></Border></TabItem>
   <TabItem Header="系统设置"><Border Background="#121824" BorderBrush="#243044" BorderThickness="1" CornerRadius="14" Padding="18" Margin="0,8,0,0"><StackPanel>
    <TextBlock Text="运行信息" FontSize="15" FontWeight="SemiBold"/><TextBlock x:Name="VersionText" Margin="0,8,0,4" Foreground="#9FB0C6"/><TextBlock x:Name="RootText" Margin="0,0,0,4" Foreground="#9FB0C6"/>
    <TextBlock Text="所有高风险操作仍由 Broker 的 TOTP 审批控制；此面板不持有密钥。" Margin="0,12,0,0" Foreground="#6B7A90" TextWrapping="Wrap"/>
   </StackPanel></Border></TabItem>
  </TabControl>
  <TextBlock Grid.Row="3" x:Name="Footer" Text="只读状态面板" Margin="0,14,0,0" Foreground="#5E6C80" FontSize="11"/>
 </Grid>
</Window>
'@

$window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$xaml)))
if ($SmokeTest) { Write-Output 'DASHBOARD_XAML_OK'; exit 0 }
$auditGrid = $window.FindName('AuditGrid')
$brokerDot = $window.FindName('BrokerDot')
$brokerState = $window.FindName('BrokerState')
$subtitle = $window.FindName('Subtitle')
$protectedRoot = $window.FindName('ProtectedRoot')
$whitelistText = $window.FindName('WhitelistText')
$versionText = $window.FindName('VersionText')
$rootText = $window.FindName('RootText')
$refreshAudit = $window.FindName('RefreshAudit')
$protectedRoot.Text = $ProjectRoot
$versionText.Text = '版本：' + ((Get-Content -LiteralPath (Join-Path $ProjectRoot 'VERSION') -Raw -ErrorAction SilentlyContinue).Trim())
$rootText.Text = '安装根目录：' + $ProjectRoot
$brokerOnline = Test-Port -Port 18090
$brokerDot.Fill = if ($brokerOnline) { '#58E1C1' } else { '#FF6B81' }
$brokerState.Text = if ($brokerOnline) { 'Broker 在线' } else { 'Broker 离线' }
$subtitle.Text = if ($brokerOnline) { '网关运行正常' } else { '网关未启动，请检查服务' }
$configPath = Join-Path $ProjectRoot 'tools\broker_config.json'
$whitelistText.Text = if (Test-Path -LiteralPath $configPath) { (Get-Content -LiteralPath $configPath -Raw) } else { '未找到 broker_config.json' }
$refreshAudit.Add_Click({ $auditGrid.ItemsSource = @(Get-AuditTail -ProjectRoot $ProjectRoot -Count 40) })
$auditGrid.ItemsSource = @(Get-AuditTail -ProjectRoot $ProjectRoot -Count 40)
[void]$window.ShowDialog()
