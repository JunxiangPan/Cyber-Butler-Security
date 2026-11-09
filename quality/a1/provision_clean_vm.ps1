<#
.SYNOPSIS
Provision a clean Windows 11 A1 baseline VM from the approved ISO.
.DESCRIPTION
Creates a Generation 2 VM, builds an autounattend ISO, waits for heartbeat,
then creates the a1-clean-base checkpoint. Failure writes BLOCKED evidence.
#>
[CmdletBinding(SupportsShouldProcess = $true)]param(
    [string]$IsoPath = 'D:\iso\Windows11_Client_x64_zh-cn_26300_9457.iso',
    [string]$VMName = 'a1-cbs-clean',
    [string]$VhdDirectory = 'D:\HyperV\qa-clones',
    [string]$SwitchName = '',
    [int]$CpuCount = 4,
    [int64]$MemoryBytes = 8GB,
    [string]$AdminUser = 'cbsadmin',
    [string]$AdminPassword = '',
    [int]$TimeoutMinutes = 45
)

$ErrorActionPreference = 'Stop'
$script:Evidence = Join-Path $PSScriptRoot 'artifacts'
New-Item -ItemType Directory -Force -Path $script:Evidence | Out-Null

function Write-Blocked([string]$reason) {
    $payload = [ordered]@{
        status = 'blocked'
        vm = $VMName
        reason = $reason
        timestamp = (Get-Date).ToUniversalTime().ToString('o')
    }
    $payload | ConvertTo-Json | Set-Content -Path (Join-Path $script:Evidence 'provision-blocked.json') -Encoding UTF8
    Write-Error "A1_PROVISION_BLOCKED: $reason"
}

function New-IsoFile {
    param([string]$SourceDirectory, [string]$Destination)
    if (-not ('CbsIsoStream' -as [type])) {
        Add-Type -Language CSharp -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Runtime.InteropServices.ComTypes;
public static class CbsIsoStream {
  public static void Save(object comStream, string path) {
    IStream stream = (IStream)comStream;
    System.Runtime.InteropServices.ComTypes.STATSTG stat;
    stream.Stat(out stat, 1);
    long remaining = stat.cbSize;
    using (FileStream fs = new FileStream(path, FileMode.Create, FileAccess.Write)) {
      byte[] buffer = new byte[1024 * 1024];
      while (remaining > 0) {
        int want = (int)Math.Min(buffer.Length, remaining);
        IntPtr read = Marshal.AllocHGlobal(sizeof(int));
        int got;
        try { stream.Read(buffer, want, read); got = Marshal.ReadInt32(read); }
        finally { Marshal.FreeHGlobal(read); }
        if (got <= 0) break;
        fs.Write(buffer, 0, got);
        remaining -= got;
      }
    }
  }
}
'@
    }
    $fsi = New-Object -ComObject IMAPI2FS.MsftFileSystemImage
    $fsi.FileSystemsToCreate = 3
    $fsi.VolumeName = 'CBSA1'
    $fsi.Root.AddTree($SourceDirectory, $false)
    $image = $fsi.CreateResultImage()
    [CbsIsoStream]::Save($image.ImageStream, $Destination)
    [Runtime.InteropServices.Marshal]::ReleaseComObject($image) | Out-Null
    [Runtime.InteropServices.Marshal]::ReleaseComObject($fsi) | Out-Null
}

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Blocked 'ELEVATION_REQUIRED: run from an elevated host PowerShell'
    return
}

if (-not (Test-Path $IsoPath)) { Write-Blocked "ISO not found: $IsoPath"; return }
if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) { Write-Blocked "VM already exists: $VMName"; return }
if (-not $SwitchName) {
    $SwitchName = (Get-VMSwitch | Select-Object -First 1 -ExpandProperty Name)
}
if (-not $SwitchName) { Write-Blocked 'No Hyper-V virtual switch'; return }
if (-not $AdminPassword) {
    $AdminPassword = 'CbsA1!' + [Guid]::NewGuid().ToString('N').Substring(0, 18) + '!'
}

$answerDir = Join-Path $env:TEMP ('cbs-a1-answer-' + [Guid]::NewGuid().ToString('N'))
$answerIso = Join-Path $env:TEMP ('cbs-a1-answer-' + [Guid]::NewGuid().ToString('N') + '.iso')
$vhdPath = Join-Path $VhdDirectory ($VMName + '.vhdx')
New-Item -ItemType Directory -Force -Path $VhdDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $answerDir | Out-Null

try {
    $template = Get-Content -Raw (Join-Path $PSScriptRoot 'autounattend.xml')
    $answer = $template.Replace('{{COMPUTER_NAME}}', $VMName).Replace('{{ADMIN_USER}}', $AdminUser).Replace('{{ADMIN_PASSWORD}}', $AdminPassword)
    $answer | Set-Content -Path (Join-Path $answerDir 'autounattend.xml') -Encoding UTF8
    $passwordPath = Join-Path $VhdDirectory ($VMName + '-admin.txt')
    $AdminPassword | Set-Content -Path $passwordPath -Encoding UTF8
    if ($PSCmdlet.ShouldProcess($VMName, 'create clean Windows A1 VM')) {
        New-IsoFile -SourceDirectory $answerDir -Destination $answerIso
        New-VHD -Path $vhdPath -SizeBytes 80GB -Dynamic | Out-Null
        New-VM -Name $VMName -Generation 2 -MemoryStartupBytes $MemoryBytes -VHDPath $vhdPath -SwitchName $SwitchName | Out-Null
        Set-VMProcessor -VMName $VMName -Count $CpuCount
        Set-VMMemory -VMName $VMName -DynamicMemoryEnabled $true -MinimumBytes 4GB -MaximumBytes $MemoryBytes
        Add-VMDvdDrive -VMName $VMName -Path $IsoPath | Out-Null
        Add-VMDvdDrive -VMName $VMName -Path $answerIso | Out-Null
        $winDvd = Get-VMDvdDrive -VMName $VMName | Where-Object { $_.Path -eq $IsoPath }
        if (-not $winDvd) {
            Write-Blocked 'WINDOWS_ISO_DVD_NOT_FOUND'
            return
        }
        $answerDvd = Get-VMDvdDrive -VMName $VMName | Where-Object { $_.Path -eq $answerIso }
        $disk = Get-VMHardDiskDrive -VMName $VMName | Select-Object -First 1
        try {
            if ($answerDvd -and $disk) {
                Set-VMFirmware -VMName $VMName -BootOrder $winDvd, $answerDvd, $disk
            } else {
                Set-VMFirmware -VMName $VMName -FirstBootDevice $winDvd
            }
        } catch {
            Set-VMFirmware -VMName $VMName -FirstBootDevice $winDvd
        }
        $bootConfig = [ordered]@{
            vm = $VMName
            generation = (Get-VM -Name $VMName).Generation
            dvd = @(Get-VMDvdDrive -VMName $VMName | Select-Object Path, ControllerNumber, ControllerLocation)
            boot_order = @((Get-VMFirmware -VMName $VMName).BootOrder | ForEach-Object {
                [ordered]@{ type = $_.BootType; device = $_.Device.Name }
            })
        }
        $bootConfig | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $script:Evidence 'boot-config.json') -Encoding UTF8
        Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false
        Start-VM -Name $VMName
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        do {
            Start-Sleep -Seconds 20
            $vm = Get-VM -Name $VMName
            if ($vm.Heartbeat -eq 'Ok') {
                try { $answerDvd = Get-VMDvdDrive -VMName $VMName | Where-Object Path -eq $answerIso; if ($answerDvd) { Remove-VMDvdDrive -VMName $VMName -ControllerNumber $answerDvd.ControllerNumber -ControllerLocation $answerDvd.ControllerLocation } } catch {}
                Remove-Item -Force $answerIso -ErrorAction SilentlyContinue
                Checkpoint-VM -Name $VMName -SnapshotName 'a1-clean-base'
                [ordered]@{ status = 'pass'; vm = $VMName; snapshot = 'a1-clean-base'; vhd = $vhdPath } |
                    ConvertTo-Json | Set-Content -Path (Join-Path $script:Evidence 'provision-result.json') -Encoding UTF8
                Write-Output 'A1_PROVISION_PASS'
                return
            }
        } while ((Get-Date) -lt $deadline)
        Write-Blocked "heartbeat timeout after $TimeoutMinutes minutes"
    }
} catch {
    Write-Blocked $_.Exception.Message
} finally {
    Remove-Item -Recurse -Force $answerDir -ErrorAction SilentlyContinue
    if (Test-Path $answerIso) { Remove-Item -Force $answerIso -ErrorAction SilentlyContinue }
}
