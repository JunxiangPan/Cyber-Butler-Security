#requires -Version 5.1
<#
Offline PSScriptAnalyzer gate. It uses the real module and reports every
Error/Warning finding; style-only rules that are not correctness related are
still included, deliberately: the project asked for the highest level.
#>
[CmdletBinding()]
param(
    [string]$Root = '',
    [string]$ModulePath = 'C:\PSSA\PSScriptAnalyzer.psd1',
    [string]$SettingsPath = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
if ([string]::IsNullOrWhiteSpace($SettingsPath)) { $SettingsPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'PSScriptAnalyzerSettings.psd1' }
if (-not (Test-Path -LiteralPath $SettingsPath)) {
    Write-Error ('PSScriptAnalyzer settings missing: ' + $SettingsPath)
    exit 1
}
if (-not (Test-Path -LiteralPath $ModulePath)) {
    Write-Error ('PSScriptAnalyzer module missing: ' + $ModulePath)
    exit 1
}
Import-Module $ModulePath -Force
$files = @(
    @('installer','tools','webui') | ForEach-Object {
        Get-ChildItem -LiteralPath (Join-Path $Root $_) -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    } |
        Where-Object {
            $_.FullName -notlike '*tmp*' -and
            $_.FullName -notlike '*.venv*' -and
            $_.FullName -notlike '*__pycache__*' -and
            $_.FullName -notlike '*tests*' -and
            $_.FullName -notlike '*held-*'
        }
)
$findings = @()
foreach ($file in $files) {
    $findings += Invoke-ScriptAnalyzer -Path $file.FullName -Settings $SettingsPath
}
Write-Output ('PSSA_FILES=' + $files.Count)
Write-Output ('PSSA_FINDINGS=' + @($findings).Count)
$findings | Group-Object RuleName | Sort-Object Count -Descending |
    Select-Object -First 20 Count, Name | Format-Table -AutoSize | Out-String | Write-Output
if (@($findings).Count -gt 0) { exit 1 }
exit 0
