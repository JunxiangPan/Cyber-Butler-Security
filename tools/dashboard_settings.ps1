#Requires -Version 5.1
# Cyber-Butler dashboard settings, theme, background and i18n helpers.
# Dot-source after the main WPF window and named controls exist.

. (Join-Path $PSScriptRoot 'dashboard_background.ps1')

function Write-SettingsLog([string]$Message) {
    try {
        $dir = Join-Path $env:LOCALAPPDATA 'CyberButler'
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Add-Content -LiteralPath (Join-Path $dir 'settings.log') -Value ('[{0:yyyy-MM-dd HH:mm:ss}] {1}' -f (Get-Date), $Message) -Encoding UTF8
    } catch { }
}

function Read-DashboardSettings {
    $defaults = [pscustomobject]@{ theme = 'light'; language = 'zh'; background = ''; enable_animated_bg = $true }
    if (-not (Test-Path -LiteralPath $script:SettingsFile)) { return $defaults }
    try {
        $saved = Get-Content -LiteralPath $script:SettingsFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($saved.theme) { $defaults.theme = [string]$saved.theme }
        if ($saved.language) { $defaults.language = [string]$saved.language }
        if ($saved.background) { $defaults.background = [string]$saved.background }
        if ($saved.PSObject.Properties.Name -contains 'enable_animated_bg') {
            $defaults.enable_animated_bg = [bool]$saved.enable_animated_bg
        }
    } catch { }
    return $defaults
}

function Save-DashboardSettings($settings) {
    try {
        $dir = Split-Path -Parent $script:SettingsFile
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $settings | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $script:SettingsFile -Encoding UTF8
    } catch { }
}

function Get-Descendants($node) {
    $out = @()
    if (-not $node) { return $out }
    try {
        foreach ($child in @([Windows.LogicalTreeHelper]::GetChildren($node))) {
            if ($child -is [Windows.DependencyObject]) {
                $out += $child
                $out += Get-Descendants $child
            }
        }
    } catch { }
    return $out
}

function Apply-Language([string]$language, $root = $null) {
    if (-not $root) { $root = $window }
    if (-not (Test-Path -LiteralPath $script:I18nFile)) { return }
    try {
        $data = Get-Content -LiteralPath $script:I18nFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $forward = @{}
        $backward = @{}
        foreach ($entry in @($data.entries)) {
            $zh = [string]$entry.zh
            $en = [string]$entry.en
            if ($zh) { $forward[$zh] = $en; $backward[$en] = $zh }
        }
        $map = if ($language -eq 'en') { $forward } else { $backward }
        foreach ($el in @(Get-Descendants $root)) {
            if ($el -is [Windows.Controls.TextBlock] -and $map.ContainsKey([string]$el.Text)) {
                $el.Text = $map[[string]$el.Text]
            } elseif ($el -is [Windows.Controls.Button] -and $el.Content -is [string] -and $map.ContainsKey([string]$el.Content)) {
                $el.Content = $map[[string]$el.Content]
            } elseif ($el -is [Windows.Controls.TabItem] -and $el.Header -is [string] -and $map.ContainsKey([string]$el.Header)) {
                $el.Header = $map[[string]$el.Header]
            } elseif ($el -is [Windows.Controls.GroupBox] -and $el.Header -is [string] -and $map.ContainsKey([string]$el.Header)) {
                $el.Header = $map[[string]$el.Header]
            } elseif ($el -is [Windows.Controls.ComboBoxItem] -and $el.Content -is [string] -and $map.ContainsKey([string]$el.Content)) {
                $el.Content = $map[[string]$el.Content]
            } elseif ($el -is [Windows.Controls.CheckBox] -and $el.Content -is [string] -and $map.ContainsKey([string]$el.Content)) {
                $el.Content = $map[[string]$el.Content]
            } elseif ($el -is [Windows.Controls.DataGrid]) {
                foreach ($column in @($el.Columns)) {
                    if ($column.Header -is [string] -and $map.ContainsKey([string]$column.Header)) {
                        $column.Header = $map[[string]$column.Header]
                    }
                }
            } elseif ($el -is [Windows.FrameworkElement] -and $el.ToolTip -is [string] -and $map.ContainsKey([string]$el.ToolTip)) {
                $el.ToolTip = $map[[string]$el.ToolTip]
            }
        }
        if ($root -is [Windows.Window] -and $map.ContainsKey([string]$root.Title)) { $root.Title = $map[[string]$root.Title] }
        $script:CurrentLanguage = $language
        if (Get-Command Update-Dashboard -ErrorAction SilentlyContinue) { Update-Dashboard }
        if (Get-Command Update-UiErrorBox -ErrorAction SilentlyContinue) { Update-UiErrorBox }
        try { if (Get-Command Show-AstrBotPluginList -ErrorAction SilentlyContinue) { Show-AstrBotPluginList } } catch { }
        try { if (Get-Command Show-DashboardModuleList -ErrorAction SilentlyContinue) { Show-DashboardModuleList } } catch { }
        try { if (Get-Command Show-PersonaList -ErrorAction SilentlyContinue) { Show-PersonaList } } catch { }
        if (Get-Command Refresh-DashboardData -ErrorAction SilentlyContinue) { Refresh-DashboardData }
        if (Get-Command Get-VersionLabel -ErrorAction SilentlyContinue) { $versionLabel.Text = Get-VersionLabel }
    } catch { }
}

function Get-SystemTheme {
    try {
        $v = (Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -ErrorAction Stop).AppsUseLightTheme
        if ($v -eq 0) { return 'dark' }
    } catch { }
    return 'light'
}

function Set-UiTheme([string]$mode) {
    $effective = $mode
    if ($mode -eq 'system') { $effective = Get-SystemTheme }
    $themeFile = Join-Path $script:ToolsRoot ('dashboard_theme_' + $effective + '.xaml')
    $styleFile = Join-Path $script:ToolsRoot 'dashboard_styles.xaml'
    if (-not (Test-Path -LiteralPath $themeFile)) { $themeFile = Join-Path $script:ToolsRoot 'dashboard_theme_light.xaml' }
    try {
        $newTheme = Load-XamlDictionary $themeFile
        $newStyles = Load-XamlDictionary $styleFile
        $merged = $window.Resources.MergedDictionaries
        $merged.Clear()
        $merged.Add($newTheme)
        $merged.Add($newStyles)
    } catch { }
    $script:CurrentTheme = $mode
    if (Get-Command Restart-UiBackground -ErrorAction SilentlyContinue) { Restart-UiBackground }
}

function Remove-OldDashboardBackups([string]$BackupDir, [int]$Keep = 5) {
    $removed = @()
    try {
        $files = @(Get-ChildItem -LiteralPath $BackupDir -Filter 'dashboard-backup-*.zip' -File -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)
        if ($files.Count -gt $Keep) {
            foreach ($file in @($files | Select-Object -Skip $Keep)) {
                try {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $removed += $file.Name
                } catch { }
            }
        }
    } catch { }
    return @($removed)
}

function Invoke-DashboardBackup {
    $dataDir = Join-Path $script:ProjectRoot 'AstrBot\data'
    if (-not (Test-Path -LiteralPath $dataDir)) { throw ('数据目录不存在：' + $dataDir) }
    $backupDir = Join-Path $script:ProjectRoot 'backups'
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $zipPath = Join-Path $backupDir ('dashboard-backup-' + $stamp + '.zip')
    $tempDir = Join-Path $env:TEMP ('cbs-backup-' + [guid]::NewGuid().ToString('N'))
    $logPath = Join-Path $backupDir 'dashboard-backup.log'
    try {
        New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        $excludeDirs = @(
            (Join-Path $dataDir 'temp'),
            (Join-Path $dataDir 'logs'),
            (Join-Path $dataDir 'cache'),
            (Join-Path $dataDir '__pycache__'),
            (Join-Path $dataDir 'dist'),
            (Join-Path $dataDir 'plugins'),
            (Join-Path $dataDir 'plugin_data\meme_manager\packs'),
            (Join-Path $dataDir 'workspaces')
        )
        $robocopy = Get-Command 'robocopy.exe' -ErrorAction SilentlyContinue
        if ($robocopy) {
            $robocopyArgs = @($dataDir, $tempDir, '/E', '/R:2', '/W:1', '/NFL', '/NDL', '/NJH', '/NJS', '/NP', '/XD') + $excludeDirs + @('/XF', '*.log', '*.tmp', '*.lock')
            & robocopy.exe @robocopyArgs | Out-Null
            $rc = $LASTEXITCODE
            if ($rc -gt 7) { throw ('robocopy 复制失败，退出码 ' + $rc) }
        } else {
            Copy-Item -LiteralPath $dataDir -Destination $tempDir -Recurse -Force -ErrorAction Stop
        }
        $files = @(Get-ChildItem -LiteralPath $tempDir -Recurse -File -ErrorAction SilentlyContinue)
        if ($files.Count -eq 0) { throw '临时备份目录为空' }
        Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $zipPath -CompressionLevel Fastest -Force -ErrorAction Stop
        $zip = Get-Item -LiteralPath $zipPath -ErrorAction Stop
        $sizeMb = [math]::Round($zip.Length / 1MB, 2)
        $removed = @(Remove-OldDashboardBackups $backupDir 5)
        Add-Content -LiteralPath $logPath -Value ('[{0:yyyy-MM-dd HH:mm:ss}] OK {1} files={2} sizeMB={3} rotated={4}' -f (Get-Date), $zip.FullName, $files.Count, $sizeMb, $removed.Count) -Encoding UTF8
        return [pscustomobject]@{ Path = $zip.FullName; SizeMB = $sizeMb; Files = $files.Count; Removed = $removed; Kept = 5 }
    } catch {
        try { Add-Content -LiteralPath $logPath -Value ('[{0:yyyy-MM-dd HH:mm:ss}] FAIL {1}' -f (Get-Date), $_.Exception.Message) -Encoding UTF8 } catch { }
        throw
    } finally {
        Remove-Item -LiteralPath $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-RestoreBackups {
    $dir = Join-Path $script:ProjectRoot 'backups'
    if (-not (Test-Path -LiteralPath $dir)) { return @() }
    return @(Get-ChildItem -LiteralPath $dir -Filter 'dashboard-backup-*.zip' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 5 | ForEach-Object {
            [pscustomobject]@{
                Display = ('{0}  ({1} MB)' -f $_.Name, [math]::Round($_.Length / 1MB, 1))
                Path = $_.FullName
                Name = $_.Name
                SizeMB = [math]::Round($_.Length / 1MB, 1)
            }
        })
}

function Get-VersionChoices {
    $choices = @()
    $current = ''
    $versionFile = Join-Path $script:ProjectRoot 'VERSION'
    if (Test-Path -LiteralPath $versionFile) { $current = (Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8).Trim() }
    $repo = 'JunxiangPan/Cyber-Butler-Security'
    try {
        $headers = @{ 'User-Agent' = 'Cyber-Butler-Dashboard'; 'Accept' = 'application/vnd.github+json' }
        $response = Invoke-RestMethod -Uri ("https://api.github.com/repos/$repo/releases?per_page=30") -Headers $headers -TimeoutSec 15
        foreach ($release in @($response | ForEach-Object { $_ })) {
            $asset = @($release.assets | Where-Object { $_.name -match '^public-release-v[0-9].*\.zip$' }) | Select-Object -First 1
            if (-not $asset) { continue }
            $tag = [string]$release.tag_name
            $choices += [pscustomobject]@{
                Display = ($tag + '  ' + [string]$release.name)
                Tag = $tag
                Name = [string]$release.name
                Url = [string]$asset.browser_download_url
                Published = [string]$release.published_at
            }
        }
    } catch { }
    if (-not ($choices | Where-Object { $_.Tag -eq ('v' + $current) })) {
        $choices = @([pscustomobject]@{ Display = ('当前版本 v' + $current); Tag = ('v' + $current); Name = 'Current'; Url = ''; Published = '' }) + @($choices)
    }
    return @($choices)
}

function Start-SettingsOperation([string]$Mode, [string]$BackupPath, $VersionChoice) {
    $restoreScript = Join-Path $script:ToolsRoot 'dashboard_restore.ps1'
    if (-not (Test-Path -LiteralPath $restoreScript)) { throw ('恢复脚本不存在：' + $restoreScript) }
    $script:settingsStatusFile = Join-Path $env:TEMP ('cbs-time-' + [guid]::NewGuid().ToString('N') + '.json')
    Remove-Item -LiteralPath $script:settingsStatusFile -Force -ErrorAction SilentlyContinue
    $log = Join-Path $script:ProjectRoot 'backups\restore_history.log'
    $args = @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-WindowStyle', 'Hidden',
        '-File', ('"' + $restoreScript + '"'),
        '-Mode', $Mode,
        '-TargetRoot', ('"' + $script:ProjectRoot + '"'),
        '-StatusFile', ('"' + $script:settingsStatusFile + '"'),
        '-LogFile', ('"' + $log + '"')
    )
    if ($Mode -eq 'Restore') {
        $args += @('-BackupPath', ('"' + $BackupPath + '"'))
    } else {
        if (-not $VersionChoice -or -not $VersionChoice.Url) { throw '该版本没有可下载的发布资产' }
        $args += @('-AssetUrl', ('"' + $VersionChoice.Url + '"'), '-Version', ('"' + $VersionChoice.Tag + '"'))
    }
    $argString = $args -join ' '
    $choiceTag = if ($VersionChoice) { [string]$VersionChoice.Tag } else { '' }
    $choiceUrl = if ($VersionChoice) { [string]$VersionChoice.Url } else { '' }
    Write-SettingsLog ('operation start mode=' + $Mode + ' target=' + $script:ProjectRoot + ' backup=' + [string]$BackupPath + ' version=' + $choiceTag + ' asset=' + $choiceUrl)
    $script:settingsOperationProcess = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argString -PassThru
    Write-SettingsLog ('elevated process started pid=' + $script:settingsOperationProcess.Id)
    $script:settingsOperationStarted = Get-Date
    $script:settingsOperationMode = $Mode
    return $script:settingsOperationProcess
}

function Format-BgResult($Result) {
    if (-not $Result) { return '' }
    if (-not $Result.Ok) { return ((T '应用失败' 'Apply failed') + '：' + $Result.Reason) }
    switch ($Result.Kind) {
        'image' {
            return ((T '静态图片' 'Static image') + ' · ' + $Result.Width + '×' + $Result.Height)
        }
        'gif' {
            if ($Result.Animated) {
                return ((T '动图' 'Animated GIF') + ' · ' + $Result.Frames + (T ' 帧' ' frames') + ' · ' + $Result.Width + '×' + $Result.Height)
            }
            return ((T '动图（静态首帧）' 'GIF (static frame)') + ' · ' + $Result.Width + '×' + $Result.Height)
        }
        'video' {
            if ($Result.Animated) {
                return ((T '视频（静音循环）' 'Video (muted loop)') + ' · ' + $Result.Width + '×' + $Result.Height)
            }
            return (T '视频静态首帧' 'Video poster frame')
        }
        default { return (T '纯色背景' 'Solid colour') }
    }
}

function Apply-BgPreview {
    $preview = $script:BgPreview
    if (-not $preview) { return }
    $result = Set-UiBackground $preview.background $preview
    if ($script:BgStatusText) {
        if ($result.Ok) {
            $script:BgStatusText.Text = Format-BgResult $result
        } else {
            $script:BgStatusText.Text = (T '应用失败' 'Apply failed') + '：' + $result.Reason
        }
    }
    if (-not $result.Ok) {
        $message = (T '文件过大或格式不支持' 'File too large or unsupported format')
        if ($result.Reason) { $message += [Environment]::NewLine + [Environment]::NewLine + $result.Reason }
        [Windows.MessageBox]::Show($message, (T '背景' 'Background'), 'OK', 'Warning') | Out-Null
        return
    }
    if ($result.Warning) {
        if ($script:BgStatusText) { $script:BgStatusText.Text = [string]$result.Warning }
        Show-BgWarning $result.Warning
    }
}

function Revert-BgPreview {
    if ($script:BgCommitted) { return }
    $original = $script:BgOriginal
    $preview = $script:BgPreview
    if (-not $original -or -not $preview) { return }
    $samePath = ([string]$preview.background -eq [string]$original.background)
    $sameAnim = ([bool]$preview.enable_animated_bg -eq [bool]$original.anim)
    if ($samePath -and $sameAnim) { return }
    $preview.background = [string]$original.background
    $preview.enable_animated_bg = [bool]$original.anim
    if ($script:BgPathText) {
        if ($preview.background) { $script:BgPathText.Text = $preview.background }
        else { $script:BgPathText.Text = (T '未选择背景' 'No background selected') }
    }
    Set-UiBackground $preview.background $preview | Out-Null
}

function Show-SettingsDialog([switch]$SmokeOnly, [string]$ShotPath = '') {
    $settings = Read-DashboardSettings
    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="设置" Width="700" Height="700" WindowStartupLocation="CenterOwner" ResizeMode="CanResize"
        Background="{DynamicResource PageBrush}" Foreground="{DynamicResource TextBrush}">
  <ScrollViewer VerticalScrollBarVisibility="Auto">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="设置" FontSize="22" FontWeight="SemiBold"/>
    <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,18,0,0">
      <TextBlock Text="主题" Width="130" VerticalAlignment="Center"/>
      <ComboBox x:Name="ThemeCombo" Width="220">
        <ComboBoxItem Content="浅色"/><ComboBoxItem Content="深色"/><ComboBoxItem Content="跟随系统"/>
      </ComboBox>
    </StackPanel>
    <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,12,0,0">
      <TextBlock Text="语言" Width="130" VerticalAlignment="Center"/>
      <ComboBox x:Name="LanguageCombo" Width="220">
        <ComboBoxItem Content="中文"/><ComboBoxItem Content="英文"/>
      </ComboBox>
    </StackPanel>
    <StackPanel Grid.Row="3" Orientation="Horizontal" Margin="0,12,0,0">
      <TextBlock Text="自定义背景" Width="130" VerticalAlignment="Center"/>
      <Button x:Name="PickBackground" Content="选择背景" Width="140" Height="30"/>
      <Button x:Name="ClearBackground" Content="清除动态背景（恢复纯色）" Width="210" Height="30" Margin="8,0,0,0"/>
    </StackPanel>
    <TextBlock Grid.Row="4" x:Name="BackgroundPath" Text="未选择背景" Margin="130,6,0,0" Foreground="{DynamicResource MutedBrush}" TextTrimming="CharacterEllipsis"/>
    <StackPanel Grid.Row="5" Orientation="Horizontal" Margin="130,10,0,0">
      <CheckBox x:Name="AnimToggle" Content="启用动态背景（GIF/视频）" VerticalAlignment="Center"/>
    </StackPanel>
    <TextBlock Grid.Row="6" x:Name="BackgroundHint" Text="⚠️ 提示：使用动态背景或视频可能会轻微增加 CPU/GPU 占用" Margin="130,8,0,0" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap"/>
    <TextBlock Grid.Row="7" x:Name="BackgroundStatus" Text="" Margin="130,4,0,0" Foreground="{DynamicResource MutedBrush}" TextWrapping="Wrap"/>
    <StackPanel Grid.Row="8" Orientation="Horizontal" Margin="0,18,0,0">
      <Button x:Name="BackupButton" Content="一键备份当前记忆与配置" Width="240" Height="34"/>
      <TextBlock x:Name="SettingsStatus" Text="" Margin="12,0,0,0" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/>
    </StackPanel>
    <StackPanel Grid.Row="9" Orientation="Horizontal" Margin="0,18,0,0">
      <TextBlock Text="恢复备份" Width="130" VerticalAlignment="Center"/>
      <ComboBox x:Name="RestoreCombo" Width="360" DisplayMemberPath="Display"/>
      <Button x:Name="RestoreButton" Content="恢复" Width="90" Height="30" Margin="8,0,0,0"/>
    </StackPanel>
    <StackPanel Grid.Row="10" Orientation="Horizontal" Margin="0,12,0,0">
      <TextBlock Text="版本管理" Width="130" VerticalAlignment="Center"/>
      <ComboBox x:Name="VersionCombo" Width="180" DisplayMemberPath="Display"/>
      <Button x:Name="ReinstallButton" Content="重装当前版本" Width="150" Height="30" Margin="8,0,0,0"/>
      <Button x:Name="DowngradeButton" Content="回退到选定版本" Width="160" Height="30" Margin="8,0,0,0"/>
    </StackPanel>
    <StackPanel Grid.Row="11" Margin="0,10,0,0">
      <ProgressBar x:Name="SettingsProgress" Height="8" IsIndeterminate="True" Visibility="Collapsed"/>
      <TextBlock x:Name="SettingsOperationStatus" Text="" Foreground="{DynamicResource MutedBrush}" Margin="0,5,0,0" TextWrapping="Wrap"/>
    </StackPanel>
    <StackPanel Grid.Row="12" Orientation="Horizontal" HorizontalAlignment="Right" Margin="0,18,0,0">
      <Button x:Name="SaveSettings" Content="保存设置" Width="110" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="CloseSettings" Content="关闭" Width="90" Height="34"/>
    </StackPanel>
  </Grid>
  </ScrollViewer>
</Window>
'@
    $r = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dlg = [Windows.Markup.XamlReader]::Load($r)
    if (-not $SmokeOnly) { $dlg.Owner = $window }
    foreach ($dict in @($window.Resources.MergedDictionaries)) { $copy = New-Object Windows.ResourceDictionary; foreach ($key in @($dict.Keys)) { $copy[$key] = $dict[$key] }; $dlg.Resources.MergedDictionaries.Add($copy) }

    if ($SmokeOnly) {
        if ($ShotPath) {
            try {
                $width = 700
                $height = 700
                $dlg.FindName('ThemeCombo').SelectedIndex = switch ($settings.theme) { 'dark' { 1 } 'system' { 2 } default { 0 } }
                $dlg.FindName('LanguageCombo').SelectedIndex = if ($settings.language -eq 'en') { 1 } else { 0 }
                $dlg.FindName('AnimToggle').IsChecked = [bool]$settings.enable_animated_bg
                if ($settings.background) { $dlg.FindName('BackgroundPath').Text = $settings.background }
                Apply-Language $settings.language $dlg
                $dlg.WindowStyle = 'None'
                $dlg.ShowInTaskbar = $false
                $dlg.WindowStartupLocation = 'Manual'
                $dlg.Left = -6000
                $dlg.Top = -6000
                $dlg.Width = $width
                $dlg.Height = $height
                $dlg.Show()
                try {
                    $dlg.UpdateLayout()
                    $dispatcher = [Windows.Threading.Dispatcher]::CurrentDispatcher
                    for ($i = 0; $i -lt 10; $i++) {
                        $dispatcher.Invoke([Windows.Threading.DispatcherPriority]::Background, [Action]{}) | Out-Null
                        Start-Sleep -Milliseconds 40
                    }
                    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ($width, $height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
                    $bitmap.Render($dlg)
                    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
                    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                    $stream = [IO.File]::Create($ShotPath)
                    try { $encoder.Save($stream) } finally { $stream.Dispose() }
                } finally {
                    $dlg.Close()
                }
            } catch {
                Write-Output ('SETTINGS_SHOT_FAILED ' + $_.Exception.Message)
            }
        }
        Write-Output 'SETTINGS_DIALOG_OK'
        return
    }

    $themeCombo = $dlg.FindName('ThemeCombo')
    $languageCombo = $dlg.FindName('LanguageCombo')
    $pathText = $dlg.FindName('BackgroundPath')
    $backgroundStatus = $dlg.FindName('BackgroundStatus')
    $animToggle = $dlg.FindName('AnimToggle')
    $status = $dlg.FindName('SettingsStatus')
    $restoreCombo = $dlg.FindName('RestoreCombo')
    $versionCombo = $dlg.FindName('VersionCombo')
    $restoreButton = $dlg.FindName('RestoreButton')
    $reinstallButton = $dlg.FindName('ReinstallButton')
    $downgradeButton = $dlg.FindName('DowngradeButton')
    $settingsProgress = $dlg.FindName('SettingsProgress')
    $operationStatus = $dlg.FindName('SettingsOperationStatus')

    $restoreChoices = @(Get-RestoreBackups)
    $restoreCombo.ItemsSource = $restoreChoices
    if ($restoreChoices.Count -gt 0) { $restoreCombo.SelectedIndex = 0 }
    $versionChoices = @(Get-VersionChoices)
    $versionCombo.ItemsSource = $versionChoices
    if ($versionChoices.Count -gt 0) { $versionCombo.SelectedIndex = 0 }

    $script:settingsOperationProcess = $null
    $script:settingsOperationStarted = Get-Date
    $script:settingsStatusFile = ''
    $script:settingsOperationMode = ''

    $settingsTimer = New-Object Windows.Threading.DispatcherTimer
    $settingsTimer.Interval = [TimeSpan]::FromSeconds(1)
    $settingsTimer.Add_Tick({
        if ($script:settingsStatusFile -and (Test-Path -LiteralPath $script:settingsStatusFile)) {
            try {
                $state = Get-Content -LiteralPath $script:settingsStatusFile -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($state.message) { $operationStatus.Text = [string]$state.message }
                if ($state.progress) { $settingsProgress.Value = [int]$state.progress }
            } catch { }
        }
        if (-not $script:settingsOperationProcess) { return }
        $elapsed = ((Get-Date) - $script:settingsOperationStarted).TotalSeconds
        if (-not $script:settingsOperationProcess.HasExited -and $elapsed -gt 60) {
            try { Stop-Process -Id $script:settingsOperationProcess.Id -Force -ErrorAction SilentlyContinue } catch { }
            $settingsTimer.Stop()
            $settingsProgress.Visibility = 'Collapsed'
            $restoreButton.IsEnabled = $true
            $reinstallButton.IsEnabled = $true
            $downgradeButton.IsEnabled = $true
            $script:settingsOperationProcess = $null
            $operationStatus.Text = '操作超时（60 秒），已终止。请查看 backups\restore_history.log'
            if (Get-Command Write-UiError -ErrorAction SilentlyContinue) { Write-UiError 'time machine timeout' $operationStatus.Text }
            [Windows.MessageBox]::Show('操作超时（60 秒），已终止。请查看 backups\restore_history.log', '超时', 'OK', 'Warning') | Out-Null
            return
        }
        if (-not $script:settingsOperationProcess.HasExited) { return }
        $proc = $script:settingsOperationProcess
        $rawCode = $null
        try { if ($proc) { $rawCode = $proc.ExitCode } } catch { }
        $code = if ($null -eq $rawCode) { -1 } else { [int]$rawCode }
        $settingsTimer.Stop()
        $settingsProgress.Visibility = 'Collapsed'
        $restoreButton.IsEnabled = $true
        $reinstallButton.IsEnabled = $true
        $downgradeButton.IsEnabled = $true
        $script:settingsOperationProcess = $null
        if ($code -eq 0) {
            $operationStatus.Text = '操作完成。'
            [Windows.MessageBox]::Show('操作完成。请检查主界面状态，必要时重新打开主控台。', '完成') | Out-Null
        } else {
            $operationStatus.Text = '操作失败，请查看 backups\restore_history.log'
            if (Get-Command Write-UiError -ErrorAction SilentlyContinue) { Write-UiError 'time machine' ('exit=' + $code) }
            [Windows.MessageBox]::Show(('操作失败（exit=' + $code + '）。' + [Environment]::NewLine + '请查看 backups\restore_history.log'), '失败', 'OK', 'Error') | Out-Null
        }
        if (Get-Command Refresh-DashboardData -ErrorAction SilentlyContinue) { Refresh-DashboardData }
        if (Get-Command Update-Dashboard -ErrorAction SilentlyContinue) { Update-Dashboard }
        if (Get-Command Get-VersionLabel -ErrorAction SilentlyContinue) { $versionLabel.Text = Get-VersionLabel }
        Remove-Item -LiteralPath $script:settingsStatusFile -Force -ErrorAction SilentlyContinue
    })

    $restoreButton.Add_Click({
        $choice = $restoreCombo.SelectedItem
        if (-not $choice) { [Windows.MessageBox]::Show('请先选择一个备份。', '恢复备份'); return }
        $answer = Read-InputDialog '恢复备份' ("⚠️ 警告：恢复备份将完全覆盖当前的聊天记录和配置！`n请在操作前确保当前系统已关闭。`n`n输入 RESTORE DATA 继续：")
        if ($answer -cne 'RESTORE DATA') { $operationStatus.Text = '已取消恢复。'; return }
        try {
            $restoreButton.IsEnabled = $false; $reinstallButton.IsEnabled = $false; $downgradeButton.IsEnabled = $false
            $settingsProgress.Visibility = 'Visible'; $settingsProgress.IsIndeterminate = $true
            $operationStatus.Text = '正在请求管理员权限并恢复数据...'
            Start-SettingsOperation 'Restore' $choice.Path $null | Out-Null
            $settingsTimer.Start()
        } catch {
            $restoreButton.IsEnabled = $true; $reinstallButton.IsEnabled = $true; $downgradeButton.IsEnabled = $true
            $settingsProgress.Visibility = 'Collapsed'
            $operationStatus.Text = '恢复失败：' + $_.Exception.Message
            [Windows.MessageBox]::Show($operationStatus.Text, '恢复失败', 'OK', 'Error') | Out-Null
        }
    })

    $reinstallButton.Add_Click({
        try {
            $choice = $versionCombo.SelectedItem
            $choiceLabel = if ($choice) { [string]$choice.Tag } else { '<none>' }
            $choiceUrl = if ($choice) { [string]$choice.Url } else { '' }
            Write-SettingsLog ('reinstall click; tag=' + $choiceLabel + ' url=' + $choiceUrl)
            if (-not $choice -or -not $choice.Url) {
                $operationStatus.Text = '当前版本没有可用的 GitHub 发布资产。'
                [Windows.MessageBox]::Show($dlg, '当前版本没有可用的 GitHub 发布资产。', '重装', 'OK', 'Warning') | Out-Null
                return
            }
            $answer = Read-InputDialog '重装当前版本' ("⚠️ 将用所选发布版本覆盖目标目录的代码（包括本地改动）。`n聊天数据和配置会先做安全备份。`n`n输入 DOWNGRADE VERSION 继续：") $dlg
            Write-SettingsLog ('reinstall confirmation=' + $answer)
            if ($answer -cne 'DOWNGRADE VERSION') { $operationStatus.Text = '已取消。'; return }
            $restoreButton.IsEnabled = $false; $reinstallButton.IsEnabled = $false; $downgradeButton.IsEnabled = $false
            $settingsProgress.Visibility = 'Visible'; $settingsProgress.IsIndeterminate = $true
            $operationStatus.Text = '正在请求管理员权限并重装...'
            Start-SettingsOperation 'Downgrade' $null $choice | Out-Null
            $settingsTimer.Start()
        } catch {
            Write-SettingsLog ('reinstall error: ' + $_.Exception.ToString())
            $restoreButton.IsEnabled = $true; $reinstallButton.IsEnabled = $true; $downgradeButton.IsEnabled = $true
            $settingsProgress.Visibility = 'Collapsed'
            $operationStatus.Text = '重装失败：' + $_.Exception.Message
            [Windows.MessageBox]::Show($dlg, $operationStatus.Text, '重装失败', 'OK', 'Error') | Out-Null
        }
    })

    $downgradeButton.Add_Click({
        try {
            $choice = $versionCombo.SelectedItem
            $choiceLabel = if ($choice) { [string]$choice.Tag } else { '<none>' }
            $choiceUrl = if ($choice) { [string]$choice.Url } else { '' }
            Write-SettingsLog ('downgrade click; tag=' + $choiceLabel + ' url=' + $choiceUrl)
            if (-not $choice -or -not $choice.Url) {
                $operationStatus.Text = '请选择一个带发布资产的历史版本。'
                [Windows.MessageBox]::Show($dlg, '请选择一个带发布资产的历史版本。', '版本回退', 'OK', 'Warning') | Out-Null
                return
            }
            $warning = "⚠️ 版本回退风险：`n`n- 将用所选版本覆盖目标目录的代码（包括本地改动）。`n- v1.1.0 之前的版本可能没有自动更新、Dashboard、备份轮转等能力。`n- 旧版本可能缺少 update-manifest.json，缺失时本工具会安全中止，不覆盖代码。`n- 回退后配置格式可能不兼容，建议先备份。`n`n输入 DOWNGRADE VERSION 继续："
            $answer = Read-InputDialog '回退到历史版本' $warning $dlg
            Write-SettingsLog ('downgrade confirmation=' + $answer)
            if ($answer -cne 'DOWNGRADE VERSION') { $operationStatus.Text = '已取消版本回退。'; return }
            $restoreButton.IsEnabled = $false; $reinstallButton.IsEnabled = $false; $downgradeButton.IsEnabled = $false
            $settingsProgress.Visibility = 'Visible'; $settingsProgress.IsIndeterminate = $true
            $operationStatus.Text = '正在请求管理员权限并回退...'
            Start-SettingsOperation 'Downgrade' $null $choice | Out-Null
            $settingsTimer.Start()
        } catch {
            Write-SettingsLog ('downgrade error: ' + $_.Exception.ToString())
            $restoreButton.IsEnabled = $true; $reinstallButton.IsEnabled = $true; $downgradeButton.IsEnabled = $true
            $settingsProgress.Visibility = 'Collapsed'
            $operationStatus.Text = '回退失败：' + $_.Exception.Message
            [Windows.MessageBox]::Show($dlg, $operationStatus.Text, '回退失败', 'OK', 'Error') | Out-Null
        }
    })

    $themeCombo.SelectedIndex = switch ($settings.theme) { 'dark' { 1 } 'system' { 2 } default { 0 } }
    $languageCombo.SelectedIndex = if ($settings.language -eq 'en') { 1 } else { 0 }
    $animToggle.IsChecked = [bool]$settings.enable_animated_bg
    if ($settings.background) { $pathText.Text = $settings.background }

    $script:BgDialog = $dlg
    $script:BgPreview = [pscustomobject]@{
        theme = [string]$settings.theme
        language = [string]$settings.language
        background = [string]$settings.background
        enable_animated_bg = [bool]$settings.enable_animated_bg
    }
    $script:BgOriginal = @{
        background = [string]$settings.background
        anim = [bool]$settings.enable_animated_bg
    }
    $script:BgCommitted = $false
    $script:BgInteractive = $true
    $script:BgStatusText = $backgroundStatus
    $script:BgPathText = $pathText

    $dlg.FindName('PickBackground').Add_Click({
        $ofd = New-Object Microsoft.Win32.OpenFileDialog
        $ofd.Title = (T '选择背景文件' 'Choose a background file')
        $ofd.Filter = '背景文件|*.png;*.jpg;*.jpeg;*.bmp;*.gif;*.mp4;*.webm|图片|*.png;*.jpg;*.jpeg;*.bmp|动图 GIF|*.gif|视频|*.mp4;*.webm|所有文件|*.*'
        $ofd.CheckFileExists = $true
        if (-not $ofd.ShowDialog()) { return }
        $check = Test-BgFile $ofd.FileName
        if (-not $check.Ok) {
            $message = (T '文件过大或格式不支持' 'File too large or unsupported format') + [Environment]::NewLine + [Environment]::NewLine + $check.Reason
            [Windows.MessageBox]::Show($message, (T '背景' 'Background'), 'OK', 'Warning') | Out-Null
            return
        }
        $script:BgPreview.background = $ofd.FileName
        $pathText.Text = $ofd.FileName
        Apply-BgPreview
    })

    $dlg.FindName('ClearBackground').Add_Click({
        $script:BgPreview.background = ''
        $pathText.Text = (T '未选择背景' 'No background selected')
        Apply-BgPreview
    })

    $animToggle.Add_Click({
        $script:BgPreview.enable_animated_bg = [bool]$animToggle.IsChecked
        if ($script:BgPreview.background) {
            Apply-BgPreview
        } elseif ($script:BgStatusText) {
            $script:BgStatusText.Text = if ($script:BgPreview.enable_animated_bg) { '' } else { (T '动态背景已关闭' 'Animated background disabled') }
        }
    })

    $dlg.FindName('BackupButton').Add_Click({
        $status.Text = '正在影子拷贝并打包...'
        try {
            $backup = Invoke-DashboardBackup
            $status.Text = '备份完成：' + $backup.Path
            [Windows.MessageBox]::Show(('备份完成。' + [Environment]::NewLine + [Environment]::NewLine + '文件：' + $backup.Path + [Environment]::NewLine + '大小：' + $backup.SizeMB + ' MB' + [Environment]::NewLine + '文件数：' + $backup.Files + [Environment]::NewLine + [Environment]::NewLine + '（系统已自动保留最近 5 次备份，旧备份已清理）'), '备份成功') | Out-Null
        } catch {
            $status.Text = '备份失败：' + $_.Exception.Message
            [Windows.MessageBox]::Show(('备份失败：' + [Environment]::NewLine + [Environment]::NewLine + $_.Exception.Message), '备份失败', 'OK', 'Error') | Out-Null
        }
    })

    $dlg.FindName('SaveSettings').Add_Click({
        $settings.theme = [string](@('light', 'dark', 'system'))[[int]$themeCombo.SelectedIndex]
        $settings.language = if ($languageCombo.SelectedIndex -eq 1) { 'en' } else { 'zh' }
        $settings.background = [string]$script:BgPreview.background
        $settings.enable_animated_bg = [bool]$script:BgPreview.enable_animated_bg
        $script:BgSuppressRestart = $true
        Set-UiTheme $settings.theme
        $script:BgSuppressRestart = $false
        Set-UiBackground $settings.background $settings | Out-Null
        Apply-Language $settings.language
        Save-DashboardSettings $settings
        $script:BgCommitted = $true
        $dlg.Close()
    })

    $dlg.FindName('CloseSettings').Add_Click({ $dlg.Close() })
    $dlg.Add_Closing({
        Revert-BgPreview
        $script:BgInteractive = $false
    })

    Apply-Language $script:CurrentLanguage $dlg
    $dlg.ShowDialog() | Out-Null
    $script:BgInteractive = $false
}
