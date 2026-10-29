# DEPRECATED: use cyber_butler_dashboard.ps1; this file has no desktop shortcut.
#Requires -Version 5.1
Add-Type -AssemblyName PresentationFramework

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$checkScript = Join-Path $PSScriptRoot 'check_update.ps1'
$mergeScript = Join-Path $PSScriptRoot 'update_merge.ps1'
$skipFile = Join-Path $PSScriptRoot 'skip_version.json'
$statusFile = Join-Path $env:TEMP 'cyber-butler-gui-status.json'

function Show-Message([string]$text, [string]$title = '苏瑾言更新') {
    [Windows.MessageBox]::Show($text, $title) | Out-Null
}

function Read-ProductionPhrase {
    $w = New-Object Windows.Window
    $w.Title = '生产更新确认'
    $w.Width = 480
    $w.Height = 210
    $w.WindowStartupLocation = 'CenterScreen'
    $w.ResizeMode = 'NoResize'
    $panel = New-Object Windows.Controls.StackPanel
    $panel.Margin = '22'
    $label = New-Object Windows.Controls.TextBlock
    $label.Text = '这是生产环境更新。请输入 UPDATE PRODUCTION 后继续：'
    $label.TextWrapping = 'Wrap'
    $panel.Children.Add($label) | Out-Null
    $box = New-Object Windows.Controls.TextBox
    $box.Margin = '0,12,0,12'
    $panel.Children.Add($box) | Out-Null
    $ok = New-Object Windows.Controls.Button
    $ok.Content = '确认'
    $ok.Width = 82
    $ok.HorizontalAlignment = 'Right'
    $ok.Add_Click({ $w.DialogResult = $true })
    $panel.Children.Add($ok) | Out-Null
    $w.Content = $panel
    $w.ShowDialog() | Out-Null
    return $box.Text
}

function Get-UpdateInfo {
    if (Test-Path -LiteralPath $statusFile) {
        Remove-Item -LiteralPath $statusFile -Force -ErrorAction SilentlyContinue
    }
    & $checkScript -StatusFile $statusFile | Out-Null
    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $statusFile)) {
        throw '检查更新失败，请查看 check_update.ps1 输出。'
    }
    return Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
}

$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="检查苏瑾言更新" Width="620" Height="480"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize">
  <Grid Margin="24">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="苏瑾言更新检查" FontSize="22" FontWeight="SemiBold"/>
    <TextBlock Grid.Row="1" x:Name="VersionText" Margin="0,12,0,8" FontSize="14"/>
    <TextBox Grid.Row="2" x:Name="Notes" IsReadOnly="True" TextWrapping="Wrap"
             VerticalScrollBarVisibility="Auto" Margin="0,8,0,12"/>
    <ProgressBar Grid.Row="3" x:Name="Progress" Height="14" Minimum="0" Maximum="100" Value="0"/>
    <TextBlock Grid.Row="4" x:Name="StatusText" Margin="0,8,0,12" Foreground="#555555"/>
    <StackPanel Grid.Row="5" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button x:Name="UpdateButton" Content="立即更新" Width="110" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="SkipButton" Content="跳过此版本" Width="110" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="CancelButton" Content="取消" Width="80" Height="34"/>
    </StackPanel>
  </Grid>
</Window>
'@

try {
    $info = Get-UpdateInfo
    if ($info.skipped) {
        Show-Message ("已跳过 v" + $info.latest + "。删除 tools\skip_version.json 后可重新提示。")
        exit 0
    }
    if (-not $info.update_available) {
        Show-Message ("当前已是最新版本 v" + $info.current + "。")
        exit 0
    }
} catch {
    Show-Message ('更新检查失败：' + $_.Exception.Message)
    exit 1
}

$reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$versionText = $window.FindName('VersionText')
$notes = $window.FindName('Notes')
$progress = $window.FindName('Progress')
$statusText = $window.FindName('StatusText')
$updateButton = $window.FindName('UpdateButton')
$skipButton = $window.FindName('SkipButton')
$cancelButton = $window.FindName('CancelButton')

$versionText.Text = "当前版本：$($info.current)    最新版本：$($info.latest)"
$notes.Text = [string]$info.body
$statusText.Text = '发现新版本，请选择操作。'

$script:child = $null
$script:currentProgress = 0
$script:lastStatusAt = Get-Date
$script:cap = 10
$stageCaps = @{
    starting = 10; downloading = 20; verifying = 35; extracting = 45;
    rendering = 55; syntax = 65; backing_up = 72; stopping = 76;
    applying = 84; data_check = 90; restarting = 95; done = 100; failed = 100
}
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(800)

$timer.Add_Tick({
    if (Test-Path -LiteralPath $statusFile) {
        try {
            $state = Get-Content -LiteralPath $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($stageCaps.ContainsKey([string]$state.stage)) {
                $script:cap = [int]$stageCaps[[string]$state.stage]
            }
            if ([int]$state.progress -gt $script:currentProgress) {
                $script:currentProgress = [int]$state.progress
            }
            $script:lastStatusAt = Get-Date
            $statusText.Text = [string]$state.message
        } catch { }
    }
    if ($script:currentProgress -lt $script:cap -and ((Get-Date) - $script:lastStatusAt).TotalSeconds -ge 2) {
        $script:currentProgress += 1
        $script:lastStatusAt = Get-Date
    }
    $progress.Value = [Math]::Min(100, $script:currentProgress)
    if ($script:child -and $script:child.HasExited) {
        $timer.Stop()
        if ($script:child.ExitCode -eq 0) {
            $progress.Value = 100
            Show-Message '更新完成，苏瑾言已重启。'
        } else {
            Show-Message '更新失败，已尝试回滚。请查看 backups 下的 update.log。'
        }
        $window.Close()
    }
})

$skipButton.Add_Click({
    @{
        schema = 1
        version = [string]$info.latest
        skipped_at = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content -LiteralPath $skipFile -Encoding UTF8
    Show-Message ("已跳过 v" + $info.latest + "。")
    $window.Close()
})

$cancelButton.Add_Click({ $window.Close() })

$updateButton.Add_Click({
    $phrase = Read-ProductionPhrase
    if ($phrase -cne 'UPDATE PRODUCTION') {
        Show-Message '确认文本不正确，已取消。'
        return
    }
    $updateButton.IsEnabled = $false
    $skipButton.IsEnabled = $false
    $cancelButton.IsEnabled = $false
    $statusText.Text = '正在请求管理员权限...'
    try {
        $argString = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + $mergeScript + '" -TargetRoot "' + $root + '" -ConfirmationText "' + $phrase + '" -StatusFile "' + $statusFile + '"'
        $script:child = Start-Process -FilePath 'powershell.exe' -Verb RunAs -ArgumentList $argString -PassThru
        $script:lastStatusAt = Get-Date
        $timer.Start()
    } catch {
        Show-Message ('无法启动管理员更新：' + $_.Exception.Message)
        $updateButton.IsEnabled = $true
        $skipButton.IsEnabled = $true
        $cancelButton.IsEnabled = $true
    }
})

$window.ShowDialog() | Out-Null
