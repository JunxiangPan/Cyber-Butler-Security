<#
.SYNOPSIS
Deploy Windows 11 Enterprise Evaluation from install.wim directly to a Gen2 VHDX.
This is an A1 test-only elevated helper. It does not create a product release.
#>
[CmdletBinding()]
param(
    [string]$IsoPath = 'D:\CB-Media\Windows11\26300.9457.260913-1737.26h2_ge_release_svc_refresh_CLIENTENTERPRISEEVAL_OEMRET_x64FRE_zh-cn.iso',
    [string]$VhdPath = 'D:\CB-Media\Windows11\cbs-a1-base.vhdx',
    [string]$VMName = 'cbs-a1-clean',
    [string]$SwitchName = 'CBS-NAT',
    [int]$Index = 1,
    [int]$TimeoutMinutes = 30
)
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$artifact = Join-Path $PSScriptRoot 'artifacts\wim-deploy'
New-Item -ItemType Directory -Force -Path $artifact | Out-Null
$resultPath = Join-Path $artifact 'result.json'
$logPath = Join-Path $artifact 'deploy.log'
function Log([string]$text) { $line = "[{0}] {1}" -f (Get-Date).ToUniversalTime().ToString('o'), $text; Add-Content -Path $logPath -Value $line; Write-Host $line }
function Done([string]$status, [string]$reason) {
    [ordered]@{ status=$status; reason=$reason; vm=$VMName; vhd=$VhdPath; iso=$IsoPath; index=$Index; timestamp=(Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $resultPath -Encoding UTF8
    exit ($(if ($status -eq 'passed') { 0 } else { 1 }))
}
try {
    if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Done 'blocked' 'ELEVATION_REQUIRED' }
    if (-not (Test-Path $IsoPath)) { Done 'blocked' 'ISO_NOT_FOUND' }
    if ($VMName -notmatch '^cbs-a1-') { Done 'blocked' 'VM_NAME_NOT_ALLOWED' }
    Log 'mounting ISO'
    $iso = Mount-DiskImage -ImagePath $IsoPath -PassThru
    Start-Sleep 2
    $isoDrive = (Get-Volume -DiskImage $iso).DriveLetter
    $wim = "$isoDrive`:\sources\install.wim"
    if (-not (Test-Path $wim)) { Dismount-DiskImage -ImagePath $IsoPath | Out-Null; Done 'blocked' 'INSTALL_WIM_MISSING' }
    Log "install.wim=$wim"
    Log 'creating 64GB dynamic VHDX'
    New-Item -ItemType Directory -Force -Path (Split-Path $VhdPath) | Out-Null
    if (Test-Path $VhdPath) { Remove-Item -Force $VhdPath }
    New-VHD -Path $VhdPath -SizeBytes 64GB -Dynamic | Out-Null
    $disk = Mount-VHD -Path $VhdPath -Passthru | Get-Disk
    Initialize-Disk -Number $disk.Number -PartitionStyle GPT -Confirm:$false
    $efi = New-Partition -DiskNumber $disk.Number -Size 100MB -GptType '{c12a7328-f81f-11d2-ba4b-00a0c93ec93b}' -AssignDriveLetter
    $msr = New-Partition -DiskNumber $disk.Number -Size 16MB -GptType '{e3c9e316-0b5c-4db8-817d-f92df00215ae}'
    $win = New-Partition -DiskNumber $disk.Number -UseMaximumSize -AssignDriveLetter
    Format-Volume -Partition $efi -FileSystem FAT32 -NewFileSystemLabel EFI -Confirm:$false | Out-Null
    Format-Volume -Partition $win -FileSystem NTFS -NewFileSystemLabel Windows -Confirm:$false | Out-Null
    $s = "$($efi.DriveLetter):"
    $w = "$($win.DriveLetter):"
    Log "partitions EFI=$s Windows=$w"
    Log 'applying install.wim index 1'
    $dism = Start-Process -FilePath 'dism.exe' -ArgumentList @('/Apply-Image',"/ImageFile:$wim","/Index:$Index","/ApplyDir:$w\") -Wait -PassThru -NoNewWindow
    if ($dism.ExitCode -ne 0) { Dismount-VHD -Path $VhdPath; Dismount-DiskImage -ImagePath $IsoPath | Out-Null; Done 'failed' "DISM_EXIT_$($dism.ExitCode)" }
    Log 'writing UEFI boot files'
    $bcd = Start-Process -FilePath 'bcdboot.exe' -ArgumentList @("$w\Windows",'/s',$s,'/f','UEFI','/l','zh-CN') -Wait -PassThru -NoNewWindow
    if ($bcd.ExitCode -ne 0) { Dismount-VHD -Path $VhdPath; Dismount-DiskImage -ImagePath $IsoPath | Out-Null; Done 'failed' "BCDBOOT_EXIT_$($bcd.ExitCode)" }
    $password = 'CbsA1!' + [Guid]::NewGuid().ToString('N').Substring(0,18) + '!'
    $answer = Get-Content -Raw (Join-Path $PSScriptRoot 'autounattend.xml')
    $answer = $answer.Replace('{{COMPUTER_NAME}}', $VMName).Replace('{{ADMIN_USER}}', 'cbsadmin').Replace('{{ADMIN_PASSWORD}}', $password)
    $panther = Join-Path $w 'Windows\Panther'
    New-Item -ItemType Directory -Force -Path $panther | Out-Null
    $answer | Set-Content -Path (Join-Path $panther 'unattend.xml') -Encoding UTF8
    $passwordPath = Join-Path (Split-Path $VhdPath) ($VMName + '-admin.txt')
    $password | Set-Content -Path $passwordPath -Encoding UTF8
    Log "unattend written; password stored outside repo at $passwordPath"
    Dismount-VHD -Path $VhdPath
    Dismount-DiskImage -ImagePath $IsoPath | Out-Null
    Log 'removing old VM if present'
    if (Get-VM -Name $VMName -ErrorAction SilentlyContinue) { Stop-VM -Name $VMName -TurnOff -Force -ErrorAction SilentlyContinue; Remove-VM -Name $VMName -Force }
    Log 'creating Gen2 VM (no ISO)'
    New-VM -Name $VMName -Generation 2 -MemoryStartupBytes 4GB -VHDPath $VhdPath -SwitchName $SwitchName | Out-Null
    Set-VMProcessor -VMName $VMName -Count 2
    Set-VMMemory -VMName $VMName -StartupBytes 4GB -DynamicMemoryEnabled $false
    Set-VMFirmware -VMName $VMName -EnableSecureBoot On -SecureBootTemplate MicrosoftWindows
    Enable-VMTPM -VMName $VMName
    Set-VM -Name $VMName -AutomaticCheckpointsEnabled $false
    Start-VM -Name $VMName
    Log 'VM started; waiting for heartbeat'
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    do {
        Start-Sleep -Seconds 15
        $vm = Get-VM -Name $VMName
        Log "heartbeat=$($vm.Heartbeat) state=$($vm.State)"
        if ($vm.Heartbeat -eq 'Ok') {
            Checkpoint-VM -Name $VMName -SnapshotName 'a1-clean-base'
            Done 'passed' 'INSTALL_AND_CHECKPOINT_OK'
        }
        if ($vm.State -eq 'Off') { Done 'failed' 'VM_POWERED_OFF' }
    } while ((Get-Date) -lt $deadline)
    Done 'failed' 'HEARTBEAT_TIMEOUT'
} catch {
    try { Dismount-VHD -Path $VhdPath -ErrorAction SilentlyContinue | Out-Null } catch {}
    try { Dismount-DiskImage -ImagePath $IsoPath -ErrorAction SilentlyContinue | Out-Null } catch {}
    Done 'failed' $_.Exception.Message
}
