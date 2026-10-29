# Hello World dashboard module.
# Runs in its own scope; $moduleContext is provided by dashboard_modules.ps1.

$badge = $moduleContext.Root.FindName('HelloBadge')
$meta = $moduleContext.Root.FindName('HelloMeta')
$counter = $moduleContext.Root.FindName('HelloCounter')
$status = $moduleContext.Root.FindName('HelloStatus')
$button = $moduleContext.Root.FindName('HelloButton')

$badge.Text = 'v' + $moduleContext.Version
$meta.Text = ('作者 {0} · 宿主 v{1} · 加载于 {2}' -f $moduleContext.Author, $script:DashboardVersion, (Get-Date -Format 'HH:mm:ss'))
$moduleContext.State.Clicks = 0
$status.Text = '模块已就绪。点击按钮验证事件与状态是否保持。'
& $moduleContext.Log 'hello_world initialized'

$button.Add_Click({
    $moduleContext.State.Clicks = 1 + [int]$moduleContext.State.Clicks
    $counter.Text = '点击次数：' + $moduleContext.State.Clicks
    $status.Text = '最近一次点击：' + (Get-Date -Format 'HH:mm:ss')
    & $moduleContext.Log ('hello_world click ' + $moduleContext.State.Clicks)
})

function Initialize-DashboardModule($context) {
    & $context.Log 'Initialize-DashboardModule called'
}
