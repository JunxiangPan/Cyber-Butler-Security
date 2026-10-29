#Requires -Version 5.1
<#
Installation review dialog for the plugin market.

Shows the security scan verdict, the AstrBot compatibility result and every
finding with file/line context. High-risk findings turn the banner red and
require the user to type INSTALL ANYWAY; a version mismatch requires the same
explicit override.
#>

function Show-PluginReviewDialog {
    param(
        [Parameter(Mandatory = $true)]$Review,
        [Parameter(Mandatory = $true)][string]$SourceLabel,
        [string]$TempPath = '',
        [switch]$SmokeOnly,
        [string]$ShotPath = ''
    )

    $xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="插件安全审查" Width="760" Height="640"
        WindowStartupLocation="CenterOwner" ResizeMode="CanResize"
        Background="{DynamicResource PageBrush}" Foreground="{DynamicResource TextBrush}">
  <Grid Margin="20">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/><RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <StackPanel Grid.Row="0" Orientation="Horizontal">
      <TextBlock Text="插件安全审查" FontSize="21" FontWeight="SemiBold"/>
      <TextBlock x:Name="ReviewSource" Margin="12,4,0,0" Foreground="{DynamicResource MutedBrush}"/>
    </StackPanel>

    <Border Grid.Row="1" x:Name="VerdictBorder" BorderThickness="1" CornerRadius="6" Padding="14" Margin="0,14,0,0">
      <StackPanel>
        <TextBlock x:Name="VerdictText" FontSize="15" FontWeight="SemiBold" TextWrapping="Wrap"/>
        <TextBlock x:Name="CompatText" Margin="0,6,0,0" TextWrapping="Wrap" FontSize="13"/>
      </StackPanel>
    </Border>

    <TextBox Grid.Row="2" x:Name="ReviewBody" IsReadOnly="True" TextWrapping="Wrap"
             VerticalScrollBarVisibility="Auto" Margin="0,12,0,12" FontFamily="Consolas" FontSize="12"/>

    <StackPanel Grid.Row="3" x:Name="OverridePanel" Visibility="Collapsed" Margin="0,0,0,10">
      <TextBlock x:Name="OverrideHint" TextWrapping="Wrap" FontWeight="SemiBold"/>
      <TextBox x:Name="OverrideBox" Width="280" Height="30" HorizontalAlignment="Left" Margin="0,6,0,0"/>
    </StackPanel>

    <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right">
      <TextBlock x:Name="ReviewStatus" Margin="0,0,14,0" VerticalAlignment="Center" Foreground="{DynamicResource MutedBrush}"/>
      <Button x:Name="CancelInstall" Content="取消" Width="100" Height="34" Margin="0,0,8,0"/>
      <Button x:Name="ConfirmInstall" Content="确认安装" Width="120" Height="34"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader ([xml]$xaml)
    $dialog = [Windows.Markup.XamlReader]::Load($reader)
    if ($window) {
        $dialog.Owner = $window
        foreach ($dictionary in @($window.Resources.MergedDictionaries)) {
            $copy = New-Object Windows.ResourceDictionary
            foreach ($key in @($dictionary.Keys)) { $copy[$key] = $dictionary[$key] }
            $dialog.Resources.MergedDictionaries.Add($copy)
        }
    }

    $metadata = $Review.Metadata
    $scan = $Review.Scan
    $compat = $Review.Compat

    $dialog.FindName('ReviewSource').Text = $SourceLabel
    $danger = ($scan.High -gt 0) -or (-not $compat.Ok)

    $verdictSuffix = if ($scan.Verdict -eq 'unsafe') { '高危' } elseif ($scan.Verdict -eq 'review') { '需复核' } elseif ($scan.Verdict -eq 'safe') { '未命中高危规则' } else { '扫描失败' }
    $dialog.FindName('VerdictText').Text = ('扫描结论：{0}（high {1} / medium {2} / low {3}，{4} 个 .py 文件）' -f $verdictSuffix, $scan.High, $scan.Medium, $scan.Low, $scan.Files)
    $compatLine = if ($compat.Ok) { '版本兼容：通过' } else { '版本不兼容：' + [string]$compat.Reason }
    $dialog.FindName('CompatText').Text = $compatLine + [Environment]::NewLine + ('插件要求：' + [string]$metadata.astrbot_version)

    if ($danger) {
        $border = $dialog.FindName('VerdictBorder')
        $border.Background = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#33C62828'))
        $border.BorderBrush = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#C62828'))
        $dialog.FindName('VerdictText').Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#D32F2F'))
    }

    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('插件：' + [string]$metadata.display_name)
    [void]$lines.Add('标识：' + [string]$metadata.name + '   版本：' + [string]$metadata.version + '   作者：' + [string]$metadata.author)
    [void]$lines.Add('来源：' + $SourceLabel)
    if ($TempPath) { [void]$lines.Add('临时目录：' + $TempPath) }
    [void]$lines.Add('')
    [void]$lines.Add('=== 安全发现 ===')
    if (@($scan.Findings).Count -eq 0) {
        [void]$lines.Add('没有命中规则。静态扫描不是安全证明，仍需确认来源可信。')
    } else {
        foreach ($finding in $scan.Findings) {
            [void]$lines.Add(('[{0}] {1}  {2}:{3}' -f $finding.Severity.ToUpper(), $finding.RuleId, $finding.File, $finding.Line))
            [void]$lines.Add('    ' + $finding.Message)
            if ($finding.Code) { [void]$lines.Add('    > ' + $finding.Code) }
        }
    }
    [void]$lines.Add('')
    [void]$lines.Add('=== 说明 ===')
    [void]$lines.Add('静态规则只能识别常见危险调用，不能发现混淆、反射或运行时下载的代码。')
    [void]$lines.Add('安装后插件将使用 AstrBot 的权限运行，请只安装可信作者的作品。')
    $dialog.FindName('ReviewBody').Text = ($lines -join [Environment]::NewLine)

    $requiresPhrase = $danger
    if ($requiresPhrase) {
        $dialog.FindName('OverridePanel').Visibility = 'Visible'
        $dialog.FindName('OverrideHint').Text = '检测到高危或不兼容项。确认要继续安装，请输入 INSTALL ANYWAY：'
        $dialog.FindName('OverrideHint').Foreground = New-Object Windows.Media.SolidColorBrush ([Windows.Media.ColorConverter]::ConvertFromString('#D32F2F'))
        $dialog.FindName('ReviewStatus').Text = '需要输入确认短语'
    }

    $result = $false
    $dialog.FindName('CancelInstall').Add_Click({ $dialog.DialogResult = $false })
    $dialog.FindName('ConfirmInstall').Add_Click({
        if ($requiresPhrase) {
            if ($dialog.FindName('OverrideBox').Text -cne 'INSTALL ANYWAY') {
                $dialog.FindName('ReviewStatus').Text = '确认短语不正确，未安装。'
                return
            }
        }
        $dialog.DialogResult = $true
    })

    if ($SmokeOnly) {
        if ($ShotPath) {
            try {
                $dialog.WindowStyle = 'None'
                $dialog.ShowInTaskbar = $false
                $dialog.WindowStartupLocation = 'Manual'
                $dialog.Left = -6000
                $dialog.Top = -6000
                $dialog.Show()
                try {
                    $dialog.UpdateLayout()
                    $dispatcher = [Windows.Threading.Dispatcher]::CurrentDispatcher
                    for ($i = 0; $i -lt 8; $i++) {
                        $dispatcher.Invoke([Windows.Threading.DispatcherPriority]::Background, [Action]{}) | Out-Null
                        Start-Sleep -Milliseconds 40
                    }
                    $width = 760
                    $height = 640
                    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap ($width, $height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
                    $bitmap.Render($dialog)
                    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
                    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
                    $stream = [IO.File]::Create($ShotPath)
                    try { $encoder.Save($stream) } finally { $stream.Dispose() }
                } finally {
                    $dialog.Close()
                }
            } catch {
                Write-Output ('REVIEW_SHOT_FAILED ' + $_.Exception.Message)
            }
        }
        Write-Output 'REVIEW_DIALOG_OK'
        return $false
    }

    $result = [bool]$dialog.ShowDialog()
    $dialog.Close()
    return $result
}
