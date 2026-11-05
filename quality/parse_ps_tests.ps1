#requires -Version 5.1
<#
Parse-only gate for test/support PowerShell files. It does not run PSSA rules;
it only rejects parser errors.
#>
[CmdletBinding()]
param([string]$Root = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$files = @(
    Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -match '[\\/](tests|quality)[\\/]' -and
            $_.FullName -notlike '*artifacts*' -and
            $_.FullName -notlike '*.venv*'
        }
)
$errors = @()
foreach ($file in $files) {
    $tokens = $null
    $parseErrors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
    foreach ($err in @($parseErrors)) {
        $errors += ($file.FullName + ':' + $err.Extent.StartLineNumber + ': ' + $err.Message)
    }
}
Write-Output ('PS_TESTS_PARSED=' + $files.Count)
Write-Output ('PS_TESTS_ERRORS=' + $errors.Count)
foreach ($item in $errors) { Write-Output $item }
if ($errors.Count -gt 0) { exit 1 }
exit 0
