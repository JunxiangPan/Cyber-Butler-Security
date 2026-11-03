param(
    [string]$InstallPath = ''
)

$ErrorActionPreference = 'Continue'
$result = [ordered]@{
    host = $env:COMPUTERNAME
    checked_at = (Get-Date).ToString('o')
    install_path = $null
    version = $null
    service = $null
    ports = @()
    tasks = @()
    logs = [ordered]@{}
    wfp = $null
    installer_report = $null
    ok = $false
    problems = @()
}

$svc = Get-CimInstance Win32_Service -Filter "Name='CyberButlerAstrBot'" -ErrorAction SilentlyContinue
if ($svc) {
    $result.service = [ordered]@{
        name = $svc.Name
        state = $svc.State
        start_name = $svc.StartName
        process_id = $svc.ProcessId
        path = $svc.PathName
    }
    if (-not $InstallPath -and $svc.PathName) {
        $InstallPath = Split-Path (Split-Path (Split-Path $svc.PathName -Parent) -Parent) -Parent
    }
} else {
    $result.problems += 'CyberButlerAstrBot service missing'
}
if ($InstallPath) {
    $result.install_path = $InstallPath
    $versionFile = Join-Path $InstallPath 'VERSION'
    if (Test-Path -LiteralPath $versionFile) { $result.version = (Get-Content -LiteralPath $versionFile -Raw).Trim() } else { $result.problems += 'VERSION missing' }
}

foreach ($port in @(6185, 18090, 8765, 8766, 5099, 6199)) {
    $listen = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    $result.ports += [ordered]@{ port = $port; listening = ($listen.Count -gt 0); pid = if ($listen.Count) { $listen[0].OwningProcess } else { $null } }
    if ($port -ne 6199 -and $listen.Count -eq 0) { $result.problems += "port $port not listening" }
}

foreach ($name in @('AstrBot TOTP Broker','Cyber-Butler WFP Guard','Cyber-Butler Web UI Services','Cyber-Butler OTP Mailer','SnowLuma Startup')) {
    $t = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    $info = if ($t) { Get-ScheduledTaskInfo -TaskName $name -ErrorAction SilentlyContinue } else { $null }
    $result.tasks += [ordered]@{
        name = $name
        exists = [bool]$t
        state = if ($t) { [string]$t.State } else { $null }
        last_result = if ($info) { ('0x{0:X8}' -f [uint32]$info.LastTaskResult) } else { $null }
    }
}

if ($InstallPath) {
    $serviceLog = Join-Path $InstallPath 'AstrBot\data\logs\service-astrbot.log'
    if (Test-Path -LiteralPath $serviceLog) {
        $head = Get-Content -LiteralPath $serviceLog -Head 8 -Encoding UTF8 -ErrorAction SilentlyContinue
        $result.logs.service_head = $head
        foreach ($needle in @('SERVICE_START','SERVICE_DATA_WRITE_OK','job=assigned')) {
            if (-not ($head -match [regex]::Escape($needle))) { $result.problems += "service log missing: $needle" }
        }
    } else {
        $result.problems += 'service-astrbot.log missing'
    }
    $wfpPolicy = Join-Path $InstallPath 'webui\data
etwork-policy.json'
    if (Test-Path -LiteralPath $wfpPolicy) {
        $result.wfp_policy = Get-Content -LiteralPath $wfpPolicy -Raw -Encoding UTF8 | ConvertFrom-Json
    } else {
        $result.problems += 'network-policy.json missing (WFP Guard cannot start)'
    }
    $wfpLog = Join-Path $InstallPath 'tools\logs\wfp-startup.log'
    if (Test-Path -LiteralPath $wfpLog) {
        $result.logs.wfp_tail = Get-Content -LiteralPath $wfpLog -Tail 20 -Encoding UTF8 -ErrorAction SilentlyContinue
    }
    $wfpTask = Get-ScheduledTask -TaskName 'Cyber-Butler WFP Guard' -ErrorAction SilentlyContinue
    if (-not $wfpTask) { $result.problems += 'Cyber-Butler WFP Guard task missing' }

    $wfpStatus = Join-Path $InstallPath 'webui\data\wfp-guard-status.json'
    if (Test-Path -LiteralPath $wfpStatus) {
        $result.wfp = Get-Content -LiteralPath $wfpStatus -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $result.wfp.ok) { $result.problems += 'WFP status not ok' }
        if ($result.wfp.mode -ne 'audit') { $result.problems += 'WFP mode is not audit; expected audit for this release' }
    } else {
        $result.problems += 'wfp-guard-status.json missing'
    }
}

$reportPath = 'C:\ProgramData\CyberButler\installer-report\install-report.json'
if (Test-Path -LiteralPath $reportPath) {
    try {
        $r = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $result.installer_report = [ordered]@{ status = $r.status; tier = $r.tier; message = $r.message }
        if ($r.status -ne 'success') { $result.problems += ('installer report status: ' + $r.status) }
    } catch {
        $result.problems += ('installer report parse failed: ' + $_.Exception.Message)
    }
} else {
    $result.problems += 'installer report missing'
}

$result.ok = ($result.problems.Count -eq 0)
$result | ConvertTo-Json -Depth 8
