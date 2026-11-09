#Requires -RunAsAdministrator
<#
.SYNOPSIS
Register the narrow A1 elevated task. Run this once from an elevated host PS.
.DESCRIPTION
Creates a manual-only task that runs a fixed script. It is not a generic
administrator shell.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$TaskName = 'CBS-A1-Elevated',
    [string]$RunAsUser = 'PCVP\pjx20'
)

$ErrorActionPreference = 'Stop'
$artifactRoot = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $artifactRoot | Out-Null
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$script = Join-Path $repo 'quality\a1\Run-A1Elevated.ps1'
if (-not (Test-Path $script)) { throw "fixed A1 script missing: $script" }
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    throw 'ELEVATION_REQUIRED: register from an elevated host PowerShell'
}
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
if ($identity.Name -ne $RunAsUser) {
    throw "TASK_USER_MISMATCH: current identity is $($identity.Name), expected $RunAsUser"
}

$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -File "' + $script + '"')
$principal = New-ScheduledTaskPrincipal -UserId $RunAsUser -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 4) -MultipleInstances IgnoreNew -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries

function Restrict-TaskToCurrentUser([string]$name, [string]$user) {
    $sid = (New-Object System.Security.Principal.NTAccount($user)).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $sddl = 'D:(A;;GA;;;SY)(A;;GA;;;' + $sid + ')'
    $service = New-Object -ComObject Schedule.Service
    $service.Connect()
    $folder = $service.GetFolder('\')
    $task = $folder.GetTask($name)
    $task.SetSecurityDescriptor($sddl, 0)
}

if ($PSCmdlet.ShouldProcess($TaskName, 'register fixed A1 task')) {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Principal $principal -Settings $settings -Description 'CBS A1 fixed clean-VM automation; manual only' -Force | Out-Null
    Restrict-TaskToCurrentUser -name $TaskName -user $RunAsUser
    $task = Get-ScheduledTask -TaskName $TaskName
    [ordered]@{
        task = $TaskName
        user = $RunAsUser
        run_level = 'Highest'
        action = $script
        trigger = 'manual-only'
        execution_time_limit_hours = 4
        multiple_instances = 'IgnoreNew'
        state = $task.State
    } | ConvertTo-Json | Set-Content -Path (Join-Path $PSScriptRoot 'artifacts\register-result.json') -Encoding UTF8
    Write-Output 'A1_TASK_REGISTERED'
}
