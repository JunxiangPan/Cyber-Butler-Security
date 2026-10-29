#Requires -RunAsAdministrator
<#
Write the DeepSeek API key into machine-scoped DPAPI.

The plaintext is read from a short-lived file created by the dashboard, never
from the command line and never written to logs. The output file is the existing
tools\deepseek.key.dpapi consumed by run-astrbot-service.ps1.
#>
param(
    [Parameter(Mandatory = $true)][string]$InputFile,
    [Parameter(Mandatory = $true)][string]$OutputFile
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
try {
    $plain = [IO.File]::ReadAllBytes($InputFile)
    if ($plain.Length -eq 0) { throw 'empty API key input' }
    $encrypted = [Security.Cryptography.ProtectedData]::Protect(
        $plain, $null, [Security.Cryptography.DataProtectionScope]::LocalMachine
    )
    $parent = Split-Path -Parent $OutputFile
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if (Test-Path -LiteralPath $OutputFile) {
        Copy-Item -LiteralPath $OutputFile -Destination ($OutputFile + '.bak') -Force
    }
    $temp = $OutputFile + '.tmp'
    [IO.File]::WriteAllBytes($temp, $encrypted)
    $temp | Move-Item -Destination $OutputFile -Force
    & icacls $OutputFile /inheritance:r /grant:r 'SYSTEM:(F)' '*S-1-5-32-544:(F)' 'AstrBot_User:(R)' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw 'icacls failed on API key file' }
    Write-Output 'API_KEY_SAVED'
} finally {
    if (Test-Path -LiteralPath $InputFile) { Remove-Item -LiteralPath $InputFile -Force -ErrorAction SilentlyContinue }
}
