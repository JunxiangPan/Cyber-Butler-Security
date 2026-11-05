#Requires -Version 5.1
<#
Build the native Cyber-Butler launcher.

This intentionally uses the in-box .NET Framework C# compiler instead of
PyInstaller. The launcher is a tiny signed PE and does not bundle Python.
#>
param(
    [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$source = Join-Path $PSScriptRoot 'CyberButlerLauncher.cs'
$manifest = Join-Path $PSScriptRoot 'app.manifest'
$output = Join-Path $root 'tools\CyberButlerLauncher.exe'
$rootLauncher = Join-Path $root 'START-INSTALLER.exe'
$installerSource = Join-Path $PSScriptRoot 'StartInstaller.cs'
$installerOutput = Join-Path $root 'START-INSTALLER.exe'

$cscCandidates = @(
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'),
    (Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v2.0.50727\csc.exe')
)
$csc = $cscCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $csc) { throw 'No in-box C# compiler (csc.exe) was found.' }
$psAssembly = Join-Path $env:WINDIR 'Microsoft.NET/assembly/GAC_MSIL/System.Management.Automation/v4.0_3.0.0.0__31bf3856ad364e35/System.Management.Automation.dll'
if (-not (Test-Path -LiteralPath $psAssembly)) { throw 'System.Management.Automation.dll was not found.' }

& $csc /nologo /target:winexe /platform:anycpu `
    ("/win32manifest:" + $manifest) `
    ("/out:" + $output) `
    ("/reference:" + $psAssembly) `
    $source
if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }

& $csc /nologo /target:winexe /platform:anycpu `
    ("/win32manifest:" + $manifest) `
    ("/out:" + $installerOutput) `
    ("/reference:" + $psAssembly) `
    $installerSource
if ($LASTEXITCODE -ne 0) { throw "installer csc failed with exit code $LASTEXITCODE" }
Write-Output ("LAUNCHER=" + $output)
Write-Output ("ROOT_LAUNCHER=" + $rootLauncher)
