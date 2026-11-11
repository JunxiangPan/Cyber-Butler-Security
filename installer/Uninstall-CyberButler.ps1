#Requires -RunAsAdministrator
<#
.SYNOPSIS
  Cyber-Butler uninstaller for CBS A1 validation.
.DESCRIPTION
  Stops CBS scheduled tasks and processes under the install root, removes the
  install tree, and removes installer state. It does not touch external
  AgentRuntime/AuxRuntime installations.
#>
[CmdletBinding()]
param(
    [Alias('InstallRoot')]
    [string]$InstallPath = 'C:\CyberButler',
    [switch]$Silent,
    [switch]$KeepProgramData
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($InstallPath)
if ($root -notmatch '^[A-Za-z]:\\') { throw 'InstallPath must be absolute.' }
if (-not (Test-Path -LiteralPath $root)) { Write-Output 'UNINSTALL_ALREADY_ABSENT'; exit 0 }
$taskNames = @('Cyber-Butler Broker','Cyber-Butler Web UI Services','Cyber-Butler OTP Mailer','Cyber-Butler WFP Guard','Cyber-Butler Broker Watchdog','Game Mode Startup')
foreach ($name in $taskNames) {
    $task = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
    if ($task) {
        Stop-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
}
$escaped = [regex]::Escape($root)
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
    if ([int]$_.ProcessId -eq $PID) { return }
    $cmd = [string]$_.CommandLine
    if ($cmd -and $cmd -notmatch 'Uninstall-CyberButler' -and $cmd -match $escaped) {
        Stop-Process -Id ([int]$_.ProcessId) -Force -ErrorAction SilentlyContinue
    }
}
Start-Sleep -Seconds 2
Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
if (-not $KeepProgramData) {
    Remove-Item -LiteralPath (Join-Path $env:ProgramData 'CyberButler') -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Output 'UNINSTALL_OK'
exit 0
