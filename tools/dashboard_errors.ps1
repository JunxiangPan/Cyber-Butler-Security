#Requires -Version 5.1
<#
Dashboard error collector.

Every caught exception is appended to an in-memory ring buffer, a log file and
the System Log tab. The tab offers one-click copy so the user can paste the
full stack trace into a chat without digging through backups/.
#>

$script:UiErrorEntries = New-Object System.Collections.ArrayList
$script:UiErrorLogPath = Join-Path $env:LOCALAPPDATA 'CyberButler\ui-errors.log'
$script:UiErrorBox = $null
$script:UiErrorStatus = $null
$script:UiErrorMaxEntries = 200

function Format-UiError([string]$Source, $ErrorObject) {
    $time = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $detail = ''
    if ($ErrorObject -is [string]) {
        $detail = $ErrorObject
    } elseif ($ErrorObject) {
        try { $detail = $ErrorObject.Exception.ToString() } catch { $detail = [string]$ErrorObject }
    }
    if (-not $detail) { $detail = 'unknown error' }
    return ('[{0}] {1}' -f $time, $Source) + [Environment]::NewLine + $detail
}

function Get-UiErrorText {
    if ($script:UiErrorEntries.Count -eq 0) { return '' }
    return (($script:UiErrorEntries | ForEach-Object { $_.Text }) -join ([Environment]::NewLine + [Environment]::NewLine))
}

function Update-UiErrorBox {
    if ($script:UiErrorBox) {
        try { $script:UiErrorBox.Text = Get-UiErrorText } catch { }
    }
    if ($script:UiErrorStatus) {
        try {
            $script:UiErrorStatus.Text = if ($script:CurrentLanguage -ne 'zh') {
                '{0} entries' -f $script:UiErrorEntries.Count
            } else {
                '{0} 条记录' -f $script:UiErrorEntries.Count
            }
        } catch { }
    }
}

function Write-UiError {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        $ErrorObject
    )
    try {
        $text = Format-UiError $Source $ErrorObject
        [void]$script:UiErrorEntries.Add([pscustomobject]@{ Time = (Get-Date); Source = $Source; Text = $text })
        while ($script:UiErrorEntries.Count -gt $script:UiErrorMaxEntries) {
            $script:UiErrorEntries.RemoveAt(0)
        }
        try {
            $dir = Split-Path -Parent $script:UiErrorLogPath
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            if ((Test-Path -LiteralPath $script:UiErrorLogPath) -and
                ((Get-Item -LiteralPath $script:UiErrorLogPath).Length -gt 512KB)) {
                Move-Item -LiteralPath $script:UiErrorLogPath -Destination ($script:UiErrorLogPath + '.1') -Force -ErrorAction SilentlyContinue
            }
            Add-Content -LiteralPath $script:UiErrorLogPath -Value ($text + [Environment]::NewLine) -Encoding UTF8
        } catch { }
        Update-UiErrorBox
    } catch { }
}

function Register-UiErrorBox {
    param($Box, $StatusText)
    $script:UiErrorBox = $Box
    $script:UiErrorStatus = $StatusText
    try {
        if ($script:UiErrorBox) { $script:UiErrorBox.Text = Get-UiErrorText }
    } catch { }
    Update-UiErrorBox
}

function Protect-UiErrorText([string]$Text) {
    $out = [string]$Text
    $out = [regex]::Replace($out, 'sk-[A-Za-z0-9_-]{6,}', '[REDACTED_API_KEY]')
    $out = [regex]::Replace($out, '(?i)(api[_-]?key|token|secret)\s*[:=]\s*[^\s,;]+', '$1=[REDACTED]')
    $out = [regex]::Replace($out, '(?i)Authorization\s*:\s*Bearer\s+\S+', 'Authorization: Bearer [REDACTED]')
    $out = [regex]::Replace($out, '(?i)Bearer\s+[A-Za-z0-9._~+/=-]{8,}', 'Bearer [REDACTED]')
    $bs = [regex]::Escape([string][char]92)
    $pathPattern = '(?<![A-Za-z])[A-Za-z]:[' + $bs + '/][^ ' + [char]34 + [char]39 + '<>|]*'
    $out = [regex]::Replace($out, $pathPattern, '[LOCAL_PATH]')
    return $out
}

function Copy-UiErrorLog {
    $text = Protect-UiErrorText (Get-UiErrorText)
    if (-not $text) { return $false }
    for ($attempt = 0; $attempt -lt 5; $attempt++) {
        try {
            Set-Clipboard -Value $text -ErrorAction Stop
            return $true
        } catch { }
        try {
            [Windows.Clipboard]::SetText($text)
            return $true
        } catch { }
        Start-Sleep -Milliseconds 200
    }
    return $false
}

function Clear-UiErrorLog {
    $script:UiErrorEntries.Clear()
    try {
        if (Test-Path -LiteralPath $script:UiErrorLogPath) {
            Clear-Content -LiteralPath $script:UiErrorLogPath -ErrorAction SilentlyContinue
        }
    } catch { }
    if ($script:UiErrorBox) { try { $script:UiErrorBox.Text = '' } catch { } }
    Update-UiErrorBox
}
