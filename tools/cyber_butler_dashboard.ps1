#Requires -Version 5.1
<#
Cyber-Butler Dashboard - Phase 1 read-only shell.

This is a local WPF desktop application. It is not an AstrBot plugin and is not
registered as an LLM tool. Phase 1 only reads ports, GPU, provider configuration,
audit log, persona prompt, and game-list files; write buttons are disabled.
#>
param(
    [string]$ProjectRoot = ''
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName PresentationFramework
$toolsRoot = $PSScriptRoot
if (-not $ProjectRoot) { $ProjectRoot = Split-Path -Parent $toolsRoot }
$ProjectRoot = (Resolve-Path -LiteralPath $ProjectRoot).Path
. (Join-Path $toolsRoot 'dashboard_core.ps1')

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Cyber-Butler 主控台" Width="1120" Height="760"
        WindowStartupLocation="CenterScreen">
  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <Border Grid.Row="0" Background="#F4F6F8" CornerRadius="6" Padding="14">
      <StackPanel Orientation="Horizontal">
        <TextBlock Text="Cyber-Butler 主控台" FontSize="22" FontWeight="SemiBold" VerticalAlignment="Center"/>
        <TextBlock Text="   Phase 1 · 只读" Foreground="#777777" FontSize="13" VerticalAlignment="Center"/>
        <TextBlock x:Name="AstrBotLight" Text="● AstrBot" Margin="28,0,0,0" FontSize="15" VerticalAlignment="Center"/>
        <TextBlock x:Name="BrokerLight" Text="● Broker" Margin="18,0,0,0" FontSize="15" VerticalAlignment="Center"/>
        <TextBlock x:Name="SnowLumaLight" Text="● SnowLuma" Margin="18,0,0,0" FontSize="15" VerticalAlignment="Center"/>
      </StackPanel>
    </Border>

    <TabControl Grid.Row="2" Margin="0,14,0,0">
      <TabItem Header="状态大盘">
        <Grid Margin="18">
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <UniformGrid Grid.Row="0" Columns="3">
            <Border Background="#FFFFFF" BorderBrush="#DDE3E8" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,10,0">
              <StackPanel>
                <TextBlock Text="AstrBot" FontSize="16" FontWeight="SemiBold"/>
                <TextBlock x:Name="AstrBotCardStatus" Text="检测中..." Margin="0,8,0,0" FontSize="24"/>
                <TextBlock Text="端口 6185" Foreground="#777777"/>
              </StackPanel>
            </Border>
            <Border Background="#FFFFFF" BorderBrush="#DDE3E8" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,0,10,0">
              <StackPanel>
                <TextBlock Text="TOTP Broker" FontSize="16" FontWeight="SemiBold"/>
                <TextBlock x:Name="BrokerCardStatus" Text="检测中..." Margin="0,8,0,0" FontSize="24"/>
                <TextBlock Text="端口 18090" Foreground="#777777"/>
              </StackPanel>
            </Border>
            <Border Background="#FFFFFF" BorderBrush="#DDE3E8" BorderThickness="1" CornerRadius="6" Padding="16">
              <StackPanel>
                <TextBlock Text="SnowLuma" FontSize="16" FontWeight="SemiBold"/>
                <TextBlock x:Name="SnowLumaCardStatus" Text="检测中..." Margin="0,8,0,0" FontSize="24"/>
                <TextBlock Text="端口 5099" Foreground="#777777"/>
              </StackPanel>
            </Border>
          </UniformGrid>

          <Border Grid.Row="1" Background="#FFFFFF" BorderBrush="#DDE3E8" BorderThickness="1" CornerRadius="6" Padding="16" Margin="0,14,0,0">
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

          <TextBlock Grid.Row="3" Text="Phase 1：按钮暂不执行写操作。" Foreground="#888888" Margin="0,18,0,0"/>
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
            <TextBlock Text="   紧急熔断功能将在第二阶段接入，需要二次确认和 UAC。" VerticalAlignment="Center" Foreground="#888888"/>
          </StackPanel>
          <Border Grid.Row="3" Background="#FFFFFF" BorderBrush="#DDE3E8" BorderThickness="1" CornerRadius="6" Padding="14" Margin="0,14,0,0">
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
          </Grid.RowDefinitions>
          <TextBlock Text="当前 System Prompt（只读）" FontSize="17" FontWeight="SemiBold"/>
          <TextBox Grid.Row="1" x:Name="PromptBox" Margin="0,10,0,12"
                   AcceptsReturn="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"/>
          <StackPanel Grid.Row="2" Orientation="Horizontal">
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
            <TextBlock x:Name="GameCountText" Text="当前白名单：0 个" Margin="18,0,0,0" VerticalAlignment="Center" FontSize="15"/>
          </StackPanel>
          <ListBox Grid.Row="1" x:Name="GameListBox" Margin="0,12,0,12"/>
          <StackPanel Grid.Row="2" Orientation="Horizontal">
            <TextBlock Text="进程名：" VerticalAlignment="Center"/>
            <TextBox x:Name="GameInput" Width="240" Height="28"/>
            <Button x:Name="AddGameButton" Content="手动添加" Width="95" Height="30" Margin="8,0,0,0"/>
            <Button x:Name="RemoveGameButton" Content="移除选中" Width="95" Height="30" Margin="8,0,0,0"/>
          </StackPanel>
          <Border Grid.Row="3" Background="#FFFFFF" BorderBrush="#DDE3E8" BorderThickness="1" CornerRadius="6" Padding="12" Margin="0,12,0,0">
            <StackPanel>
              <TextBlock Text="内置忽略名单（不会触发模型卸载）" FontWeight="SemiBold"/>
              <TextBlock x:Name="IgnoreText" Text="读取中..." TextWrapping="Wrap" Foreground="#666666" Margin="0,6,0,0"/>
            </StackPanel>
          </Border>
        </Grid>
      </TabItem>
    </TabControl>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
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

function Set-Light($light, $card, [string]$name, [bool]$online) {
    $color = if ($online) { '#1B8A3A' } else { '#C62828' }
    $text = if ($online) { '● 在线' } else { '● 离线' }
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
        $gpuText.Text = 'GPU 读取失败'
        $gpuBar.Value = 0
    }
    $provider = Get-ProviderInfo $ProjectRoot
    $providerText.Text = "$($provider.Mode) / $($provider.Name) / $($provider.Model)"
}

$auditGrid.ItemsSource = @(Get-AuditTail $ProjectRoot 10)
$promptBox.Text = Get-PersonaPrompt $ProjectRoot
$games = @(Get-GameWhitelist $ProjectRoot)
$gameCountText.Text = "当前白名单：$($games.Count) 个"
$gameListBox.ItemsSource = @($games | ForEach-Object { "$($_.Name)  [$($_.Source)]" })
$ignoreText.Text = (@(Get-GameIgnoreList $ProjectRoot) -join ', ')


$actionScript = Join-Path $toolsRoot 'dashboard_actions.ps1'
$gameModeScript = Join-Path $ProjectRoot 'tools\game-mode.ps1'
if (-not (Test-Path -LiteralPath $gameModeScript)) { $gameModeScript = Join-Path $toolsRoot 'game-mode.ps1' }
$manualGameFile = Join-Path $ProjectRoot 'tools\game-list.txt'

function Show-Message([string]$text, [string]$title = 'Cyber-Butler 主控台') {
    [Windows.MessageBox]::Show($text, $title) | Out-Null
}

function Read-InputDialog([string]$title, [string]$prompt) {
    $w = New-Object Windows.Window
    $w.Title = $title
    $w.Width = 430
    $w.Height = 190
    $w.WindowStartupLocation = 'CenterScreen'
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
    $ok.Content = '确认'
    $ok.Width = 80
    $ok.HorizontalAlignment = 'Right'
    $ok.Add_Click({ $w.DialogResult = $true })
    $panel.Children.Add($ok) | Out-Null
    $w.Content = $panel
    $w.ShowDialog() | Out-Null
    return $box.Text
}

function Invoke-ElevatedAction([string]$Action, [hashtable]$Extra = @{}) {
    $argParts = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', ('"' + $actionScript + '"'),
        '-Action', $Action,
        '-ProjectRoot', ('"' + $ProjectRoot + '"')
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
    $auditGrid.ItemsSource = @(Get-AuditTail $ProjectRoot 10)
    $promptBox.Text = Get-PersonaPrompt $ProjectRoot
    $games = @(Get-GameWhitelist $ProjectRoot)
    $gameCountText.Text = "当前白名单：$($games.Count) 个"
    $gameListBox.ItemsSource = @($games | ForEach-Object { "$($_.Name)  [$($_.Source)]" })
    $ignoreText.Text = (@(Get-GameIgnoreList $ProjectRoot) -join ', ')
}

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
    $tokenFile = Join-Path $ProjectRoot '.astrbot_token'
    if (-not (Test-Path -LiteralPath $tokenFile)) { return $false }
    $token = (Get-Content -LiteralPath $tokenFile -Raw).Trim()
    if (-not $token) { return $false }
    $overlay = Get-Content -LiteralPath (Join-Path $ProjectRoot 'local-overlay.json') -Raw -Encoding UTF8 | ConvertFrom-Json
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

$overlayFile = Join-Path $ProjectRoot 'local-overlay.json'
if (Test-Path -LiteralPath $overlayFile) {
    try {
        $overlay = Get-Content -LiteralPath $overlayFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $qqBox.Text = [string]$overlay.values.YOUR_QQ_ID
        if (Test-Path (Join-Path $ProjectRoot 'tools\deepseek.key.dpapi')) {
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
    try { Start-Process explorer.exe (Join-Path $ProjectRoot 'AstrBot\data') } catch { Show-Message '无法打开日志目录。' }
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
    try {
        $personaFile = Join-Path $ProjectRoot '.persona_sujinyan.json'
        Copy-Item -LiteralPath $personaFile -Destination ($personaFile + '.bak-dashboard') -Force
        $persona = Get-Content -LiteralPath $personaFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $persona.system_prompt = $promptBox.Text
        [IO.File]::WriteAllText($personaFile, ($persona | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        $code = Invoke-ElevatedAction 'RestartAstrBot'
        if ($code -eq 0) { Show-Message '人格提示词已保存，AstrBot 已重载。' } else { Show-Message '提示词已保存，但 AstrBot 重载失败。' }
        Refresh-DashboardData
    } catch { Show-Message ('保存失败：' + $_.Exception.Message) }
})

$clearConversationButton.Add_Click({
    if (Try-ClearConversationViaApi) {
        Show-Message '当前对话历史已通过 AstrBot API 清空。'
        return
    }
    $choice = [Windows.MessageBox]::Show('API 清空失败。是否使用停服兜底？这会短暂停止 AstrBot，并先备份数据库。', '清空对话', 'YesNo', 'Warning')
    if ($choice -ne 'Yes') { return }
    try {
        $overlay = Get-Content -LiteralPath (Join-Path $ProjectRoot 'local-overlay.json') -Raw -Encoding UTF8 | ConvertFrom-Json
        $umo = [string]$overlay.values.YOUR_PLATFORM_ID + ':FriendMessage:' + [string]$overlay.values.YOUR_QQ_ID
        $code = Invoke-ElevatedAction 'ClearConversation' @{ Umo = $umo }
        if ($code -eq 0) { Show-Message '当前对话历史已清空，AstrBot 已重启。' } else { Show-Message '清空失败，请查看日志。' }
    } catch { Show-Message ('清空失败：' + $_.Exception.Message) }
})

$scanGamesButton.Add_Click({
    try {
        $proc = Start-Process -FilePath 'powershell.exe' -ArgumentList @(
            '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"' + $gameModeScript + '"'), '-ScanLibraries'
        ) -WindowStyle Hidden -PassThru
        $proc.WaitForExit()
        Refresh-DashboardData
        Show-Message '游戏库扫描完成，已刷新白名单。'
    } catch { Show-Message ('扫描失败：' + $_.Exception.Message) }
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
        $overlayPath = Join-Path $ProjectRoot 'local-overlay.json'
        $overlay = Get-Content -LiteralPath $overlayPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $overlay.values.YOUR_QQ_ID = $qq
        Copy-Item -LiteralPath $overlayPath -Destination ($overlayPath + '.bak-dashboard') -Force
        [IO.File]::WriteAllText($overlayPath, ($overlay | ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
        $gate = Join-Path $ProjectRoot 'AstrBot\data\config\astrbot_plugin_at_gate_config.json'
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

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({ Update-Dashboard })
Update-Dashboard
$timer.Start()
$window.ShowDialog() | Out-Null
