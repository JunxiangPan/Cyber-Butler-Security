# A1 Q17: CBS Broker task interrupt/recovery (owner-approved redefinition)
# Exit 0 only for a real PASS; exit 3 for blocked or failed prerequisites.
param(
    [string]$ArtifactZip = '',
    [string]$Nonce = '',
    [int]$TimeoutMinutes = 20
)
$ErrorActionPreference = 'Stop'
$InstallRoot = 'C:\CyberButler'
function Blocked([string]$reason) { Write-Output ('BLOCKED:' + $reason); exit 3 }
function Pass([string]$reason) { Write-Output ('PASS:' + $reason); exit 0 }
if (-not (Test-Path $InstallRoot)) { Blocked 'QA_VM_NOT_PROVISIONED' }
$taskName = 'Cyber-Butler Broker'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if (-not $task) { Blocked 'BROKER_TASK_MISSING' }
$health = { try { $r = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:18090/health' -TimeoutSec 5; return [int]$r.StatusCode } catch { return 0 } }
$before = & $health
if ($before -ne 200) { Blocked ('BROKER_HEALTH_BEFORE=' + $before) }
$auditDir = Join-Path $InstallRoot 'tools\logs'
if (-not (Test-Path $auditDir)) { Blocked 'AUDIT_DIR_MISSING' }
Stop-ScheduledTask -TaskName $taskName -ErrorAction Stop
Start-Sleep -Seconds 3
$owners = @(Get-NetTCPConnection -State Listen -LocalPort 18090 -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique)
foreach ($ownerPid in $owners) {
    if ($ownerPid -gt 0) { Stop-Process -Id $ownerPid -Force -ErrorAction SilentlyContinue }
}
Start-Sleep -Seconds 2
$during = & $health
Start-ScheduledTask -TaskName $taskName -ErrorAction Stop
$after = 0
for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Seconds 2
    $after = & $health
    if ($after -eq 200) { break }
}
if ($after -ne 200) { Blocked ('BROKER_HEALTH_AFTER=' + $after) }
$tasks = @(Get-ScheduledTask | Where-Object { $_.TaskName -eq $taskName })
if ($tasks.Count -ne 1) { Blocked ('BROKER_TASK_COUNT=' + $tasks.Count) }
$agentService = Get-Service -Name 'CyberButlerAgentRuntime' -ErrorAction SilentlyContinue
if ($agentService) { Blocked 'CBS_HOLDS_AGENTRUNTIME_SERVICE' }
$latest = Get-ChildItem $auditDir -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $latest) { Blocked 'AUDIT_LOG_EMPTY' }
Pass ('BEFORE=' + $before + ';DURING=' + $during + ';AFTER=' + $after + ';TASK_COUNT=' + $tasks.Count + ';AUDIT=' + $latest.Name)
