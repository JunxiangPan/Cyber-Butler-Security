#requires -Version 5.1
<#
AST-based PowerShell comment audit. No regex is used to decide whether a
comment exists: tokens come from the PowerShell parser, and functions come
from the AST.
#>
[CmdletBinding()]
param([string]$Root = '')

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}
$rootPath = [IO.Path]::GetFullPath($Root)
$syntaxErrors = New-Object System.Collections.Generic.List[object]
$missing = New-Object System.Collections.Generic.List[object]
$functionCount = 0

$files = @(
    Get-ChildItem -LiteralPath $rootPath -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.FullName -notmatch '\\\.venv\\|\\__pycache__\\|\\wheelhouse\\|\\tmp-' -and
            $_.FullName -notmatch '\\quality\\'
        }
)
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $file.FullName, [ref]$tokens, [ref]$errors
    )
    foreach ($err in @($errors)) {
        $syntaxErrors.Add([pscustomobject]@{
            file = $file.FullName.Substring($rootPath.Length).TrimStart('\')
            line = $err.Extent.StartLineNumber
            message = $err.Message
        })
    }
    foreach ($fn in @($ast.FindAll({ param($n) $n.GetType().Name -eq "FunctionDefinitionAst" }, $true))) {
        $functionCount++
        $start = $fn.Extent.StartLineNumber
        $end = $fn.Extent.EndLineNumber
        if (($end - $start + 1) -le 20) { continue }
        $hasBlock = $false
        foreach ($token in @($tokens)) {
            if ([string]$token.Kind -ne 'Comment') { continue }
            if ($token.Extent.StartLineNumber -ge $start -or $token.Extent.StartLineNumber -lt ($start - 8)) { continue }
            if ([string]$token.Text -match '^\s*<#') {
                $hasBlock = $true
                break
            }
        }
        if (-not $hasBlock) {
            $missing.Add([pscustomobject]@{
                file = $file.FullName.Substring($rootPath.Length).TrimStart('\')
                line = $start
                name = $fn.Name
            })
        }
    }
}

[pscustomobject]@{
    functions = $functionCount
    syntax_errors = $syntaxErrors.ToArray()
    missing_comments = $missing.ToArray()
} | ConvertTo-Json -Depth 5
