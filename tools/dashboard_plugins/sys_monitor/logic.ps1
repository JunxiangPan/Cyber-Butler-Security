# Sys Monitor dashboard module: reads LibreHardwareMonitor every 3 seconds.
# The timer is created on the UI thread so all ProgressBar updates stay safe.
$cpuBar = $moduleContext.Root.FindName('CpuBar')
$gpuBar = $moduleContext.Root.FindName('GpuBar')
$vramBar = $moduleContext.Root.FindName('VramBar')
$cpuValue = $moduleContext.Root.FindName('CpuValue')
$gpuValue = $moduleContext.Root.FindName('GpuValue')
$vramValue = $moduleContext.Root.FindName('VramValue')
$status = $moduleContext.Root.FindName('SysStatus')
$title = $moduleContext.Root.FindName('SysTitle')
$subtitle = $moduleContext.Root.FindName('SysSubtitle')

$title.Text = & $moduleContext.T '实时监控' 'Live Monitor'
$subtitle.Text = & $moduleContext.T '每 3 秒读取 LibreHardwareMonitor' 'Reads LibreHardwareMonitor every 3 seconds'
$moduleContext.Root.FindName('CpuLabel').Text = & $moduleContext.T 'CPU 温度' 'CPU Temp'
$moduleContext.Root.FindName('GpuLabel').Text = & $moduleContext.T 'GPU 温度' 'GPU Temp'
$moduleContext.Root.FindName('VramLabel').Text = & $moduleContext.T '显存占用' 'VRAM Usage'
$status.Text = & $moduleContext.T '正在连接传感器…' 'Connecting to sensors...'

$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(3)
$timer.Add_Tick({
    try {
        $data = Invoke-RestMethod -Uri 'http://127.0.0.1:18085/data.json' -TimeoutSec 4
        $stack = New-Object System.Collections.Stack
        $stack.Push([pscustomobject]@{ Node = $data; Path = '' })
        $cpu = @()
        $gpu = @()
        $memUsed = $null
        $memTotal = $null
        while ($stack.Count -gt 0) {
            $item = $stack.Pop()
            $node = $item.Node
            if (-not $node) { continue }
            $text = [string]$node.Text
            $value = [string]$node.Value
            $cur = if ($text) { $item.Path + '/' + $text } else { $item.Path }
            $low = $cur.ToLowerInvariant()
            if ($value -match '^\s*(-?\d+(?:\.\d+)?)') {
                $number = [double]$Matches[1]
                $isTemp = $value -match '°C'
                if ($isTemp -and $low -match 'gpu core' -and $low -match 'nvidia|radeon|gpu') { $gpu += $number }
                elseif ($isTemp -and $low -match 'cpu package|core \(tctl|tdie|cpu core') { $cpu += $number }
                elseif ($low -match 'gpu memory used') { $memUsed = $number }
                elseif ($low -match 'gpu memory total') { $memTotal = $number }
            }
            foreach ($child in @($node.Children)) {
                if ($child) { $stack.Push([pscustomobject]@{ Node = $child; Path = $cur }) }
            }
        }
        if (@($cpu).Count -gt 0) {
            $cpuMax = ($cpu | Measure-Object -Maximum).Maximum
            $cpuBar.Value = [Math]::Min(100, [double]$cpuMax)
            $cpuValue.Text = ('{0:N1} °C' -f $cpuMax)
        } else {
            $cpuValue.Text = '--'
        }
        if (@($gpu).Count -gt 0) {
            $gpuMax = ($gpu | Measure-Object -Maximum).Maximum
            $gpuBar.Value = [Math]::Min(100, [double]$gpuMax)
            $gpuValue.Text = ('{0:N1} °C' -f $gpuMax)
        } else {
            $gpuValue.Text = '--'
        }
        if ($memUsed -ne $null -and $memTotal -ne $null -and $memTotal -gt 0) {
            $vramBar.Maximum = [double]$memTotal
            $vramBar.Value = [double]$memUsed
            $vramValue.Text = ('{0:N0} / {1:N0} MB' -f $memUsed, $memTotal)
        } else {
            $vramValue.Text = '--'
        }
        $status.Text = & $moduleContext.T '传感器已连接' 'Sensors connected' + ' · ' + (Get-Date -Format 'HH:mm:ss')
    } catch {
        $status.Text = & $moduleContext.T 'LHM 未运行，等待重连…' 'LHM is not running; waiting to reconnect...'
        if (Get-Command Write-UiError -ErrorAction SilentlyContinue) { Write-UiError 'sys_monitor' $_ }
    }
}.GetNewClosure())
$timer.Start()
& $moduleContext.Log 'sys_monitor started (3s interval)'

function Initialize-DashboardModule($context) {
    & $context.Log 'sys_monitor initialized'
}
