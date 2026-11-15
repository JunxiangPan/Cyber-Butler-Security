param(
    [Parameter(Mandatory=$true)][string]$Evidence,
    [Parameter(Mandatory=$true)][string]$ChildLog
)
$ErrorActionPreference = 'Stop'
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CbsJobOwner {
  [StructLayout(LayoutKind.Sequential)] public struct IO_COUNTERS { public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount, ReadTransferCount, WriteTransferCount, OtherTransferCount; }
  [StructLayout(LayoutKind.Sequential)] public struct JOBOBJECT_BASIC_LIMIT_INFORMATION { public long PerProcessUserTimeLimit, PerJobUserTimeLimit; public uint LimitFlags; public UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize; public uint ActiveProcessLimit; public UIntPtr Affinity; public uint PriorityClass, SchedulingClass; }
  [StructLayout(LayoutKind.Sequential)] public struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION { public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation; public IO_COUNTERS IoInfo; public UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed; }
  [DllImport("kernel32.dll", SetLastError=true, CharSet=CharSet.Unicode)] public static extern IntPtr CreateJobObject(IntPtr a, string name);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetInformationJobObject(IntPtr job, int infoClass, ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, uint length);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
  [DllImport("kernel32.dll", SetLastError=true)] public static extern bool SetHandleInformation(IntPtr handle, uint mask, uint flags);
  [DllImport("kernel32.dll")] public static extern IntPtr GetCurrentProcess();
}
'@
$job = [CbsJobOwner]::CreateJobObject([IntPtr]::Zero, $null)
if ($job -eq [IntPtr]::Zero) { throw 'CreateJobObject failed' }
$info = New-Object CbsJobOwner+JOBOBJECT_EXTENDED_LIMIT_INFORMATION
$info.BasicLimitInformation.LimitFlags = 0x00002000
$len = [Runtime.InteropServices.Marshal]::SizeOf($info)
if (-not [CbsJobOwner]::SetInformationJobObject($job, 9, [ref]$info, [uint32]$len)) { throw 'SetInformationJobObject failed' }
# The job handle must not be inherited by the child; otherwise KILL_ON_JOB_CLOSE
# would wait for the child's inherited handle and leave an orphan.
if (-not [CbsJobOwner]::SetHandleInformation($job, 1, 0)) { throw 'SetHandleInformation failed' }
# Assign the owner itself; the child inherits job membership from this process.
if (-not [CbsJobOwner]::AssignProcessToJobObject($job, [CbsJobOwner]::GetCurrentProcess())) { throw 'AssignProcessToJobObject(owner) failed' }
$ownerInJob = $false
[void][CbsJobOwner]::IsProcessInJob([CbsJobOwner]::GetCurrentProcess(), $job, [ref]$ownerInJob)
$child = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-Command','Start-Sleep -Seconds 300') -PassThru -WindowStyle Hidden
$proc = Get-Process -Id $child.Id
$childInJob = $false
[void][CbsJobOwner]::IsProcessInJob($proc.Handle, $job, [ref]$childInJob)
[ordered]@{ owner_pid = $PID; child_pid = $child.Id; job_handle = $job.ToString(); kill_on_job_close = $true; owner_assigned = $ownerInJob; child_in_job = $childInJob; handle_inheritable = $false; timestamp = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $Evidence -Encoding UTF8
if (-not $childInJob) { throw 'child is not in job' }
Start-Sleep -Seconds 120
