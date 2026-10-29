# Hello World dashboard module.
# Runs in its own scope; $moduleContext is provided by dashboard_modules.ps1.
#
# Important: PowerShell event handlers do not keep the locals of the loading
# scope after the module finishes loading. Capture everything the handler needs
# with .GetNewClosure(), otherwise $moduleContext is $null when the button is
# clicked and State.Clicks assignment fails.

$badge = $moduleContext.Root.FindName('HelloBadge')
$meta = $moduleContext.Root.FindName('HelloMeta')
$counter = $moduleContext.Root.FindName('HelloCounter')
$status = $moduleContext.Root.FindName('HelloStatus')
$button = $moduleContext.Root.FindName('HelloButton')

$moduleContext.State.Clicks = 0
$badge.Text = 'v' + $moduleContext.Version
$meta.Text = ('作者 {0} · 宿主 v{1} · 加载于 {2}' -f $moduleContext.Author, $script:DashboardVersion, (Get-Date -Format 'HH:mm:ss'))
$status.Text = '模块已就绪。点击按钮验证事件与状态是否保持。'
& $moduleContext.Log 'hello_world initialized'

$button.Add_Click({
    $moduleContext.State.Clicks = 1 + [int]$moduleContext.State.Clicks
    $counter.Text = '点击次数：' + $moduleContext.State.Clicks
    $status.Text = '最近一次点击：' + (Get-Date -Format 'HH:mm:ss')
    & $moduleContext.Log ('hello_world click ' + $moduleContext.State.Clicks)
}.GetNewClosure())

function Initialize-DashboardModule($context) {
    $context.State.Clicks = 0
    $context.Root.FindName('HelloCounter').Text = '点击次数：0'
    & $context.Log 'Initialize-DashboardModule called'
}
