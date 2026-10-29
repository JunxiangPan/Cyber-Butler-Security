# Quick command dashboard module: sends a message to Su Jinyan's QQ session
# through the local AstrBot Open API. It never runs a shell command.
$box = $moduleContext.Root.FindName('CmdBox')
$sendButton = $moduleContext.Root.FindName('CmdSendButton')
$morningButton = $moduleContext.Root.FindName('CmdMorningButton')
$localButton = $moduleContext.Root.FindName('CmdLocalButton')
$tempButton = $moduleContext.Root.FindName('CmdTempButton')
$status = $moduleContext.Root.FindName('CmdStatus')
$title = $moduleContext.Root.FindName('CmdTitle')
$subtitle = $moduleContext.Root.FindName('CmdSubtitle')
$hint = $moduleContext.Root.FindName('CmdHint')

$title.Text = & $moduleContext.T '一键指令发送器' 'Quick Command Sender'
$subtitle.Text = & $moduleContext.T '通过 AstrBot Open API 发送到苏瑾言的 QQ 私聊' "Sends to Su Jinyan's QQ chat through the AstrBot Open API"
$sendButton.Content = & $moduleContext.T '发送' 'Send'
$morningButton.Content = & $moduleContext.T '发早安' 'Send Morning'
$localButton.Content = & $moduleContext.T '切本地模型' 'Local Model'
$tempButton.Content = & $moduleContext.T '查看温度' 'Check Temps'
$hint.Text = & $moduleContext.T '提示：发送走 AstrBot Open API，消息会出现在苏瑾言的 QQ 私聊里；不会在本机执行任何 shell 命令。' "Note: messages go through the AstrBot Open API into Su Jinyan's QQ chat. No shell command is executed locally."

$umo = ''
try {
    $overlay = Get-Content -LiteralPath (Join-Path $moduleContext.ProjectRoot 'local-overlay.json') -Raw -Encoding UTF8 | ConvertFrom-Json
    $umo = [string]$overlay.values.YOUR_PLATFORM_ID + ':FriendMessage:' + [string]$overlay.values.YOUR_QQ_ID
} catch {
    & $moduleContext.Log ('quick_cmd umo read failed: ' + $_.Exception.Message)
}
if (-not $umo) { $status.Text = & $moduleContext.T '未找到 QQ 会话配置。' 'QQ session configuration not found.' }

$sendAction = {
    param([string]$text)
    if (-not $text -or -not $text.Trim()) {
        $status.Text = & $moduleContext.T '内容为空，没有发送。' 'Nothing to send.'
        return
    }
    if (-not $umo) { return }
    try {
        $response = Invoke-AstrBotApi -Method POST -ApiPath '/api/v1/im/messages' -Body @{ umo = $umo; message = $text.Trim() }
        if (-not $response -or $response.status -eq 'error') { throw [string]$response.message }
        $status.Text = & $moduleContext.T '已发送：' 'Sent: ' + $text.Trim() + ' · ' + (Get-Date -Format 'HH:mm:ss')
        $box.Text = ''
    } catch {
        $status.Text = & $moduleContext.T '发送失败：' 'Send failed: ' + $_.Exception.Message
        if (Get-Command Write-UiError -ErrorAction SilentlyContinue) { Write-UiError 'quick_cmd' $_ }
    }
}.GetNewClosure()

$sendButton.Add_Click({ & $sendAction $box.Text }.GetNewClosure())
$morningButton.Add_Click({ & $sendAction '早安' }.GetNewClosure())
$localButton.Add_Click({ & $sendAction '切本地模型' }.GetNewClosure())
$tempButton.Add_Click({ & $sendAction '查看电脑温度' }.GetNewClosure())
$status.Text = & $moduleContext.T '就绪。' 'Ready.'
& $moduleContext.Log 'quick_cmd ready'

function Initialize-DashboardModule($context) {
    & $context.Log 'quick_cmd initialized'
}
