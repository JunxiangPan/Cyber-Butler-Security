#requires -Version 5.1
<#
AST-level parameter binding test. It deliberately does not use a single-line
regex: PowerShell's parser handles continuation lines and nested commands.
#>
$ErrorActionPreference = 'Stop'
$root = Join-Path (Split-Path -Parent $PSScriptRoot) '..'
$libPath = Join-Path $root 'installer/lib'
$files = @(Get-ChildItem -LiteralPath $libPath -Filter '*.ps1' -File)

Describe 'Installer parameter binding' {
    It 'uses only declared parameter names on custom CyberButler calls' {
        $errors = New-Object System.Collections.Generic.List[string]
        foreach ($file in $files) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$parseErrors)
            foreach ($parseError in @($parseErrors)) {
                $errors.Add(($file.Name + ':' + $parseError.Extent.StartLineNumber + ': ' + $parseError.Message))
            }
            $functions = @{}
            foreach ($fn in @($ast.FindAll({ param($node) $node.GetType().Name -eq 'FunctionDefinitionAst' }, $true))) {
                $parameters = @()
                if ($fn.Body.ParamBlock) {
                    $parameters = @($fn.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
                }
                $hasCmdletBinding = @($fn.Body.ParamBlock.Attributes | Where-Object { $_.TypeName.Name -eq 'CmdletBinding' }).Count -gt 0
                if ($hasCmdletBinding) {
                    $parameters += @('ErrorAction', 'WarningAction', 'InformationAction', 'Verbose', 'Debug', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable', 'ProgressAction')
                }
                $functions[$fn.Name] = $parameters
            }
            foreach ($command in @($ast.FindAll({ param($node) $node.GetType().Name -eq 'CommandAst' }, $true))) {
                $name = $command.GetCommandName()
                if (-not $name -or -not $functions.ContainsKey($name)) { continue }
                $allowed = $functions[$name]
                foreach ($element in @($command.CommandElements)) {
                    if ($element.GetType().Name -ne 'CommandParameterAst') { continue }
                    $parameterName = $element.ParameterName
                    if ($parameterName -notin $allowed) {
                        $errors.Add(($file.Name + ':' + $element.Extent.StartLineNumber + ': ' + $name + ' does not accept -' + $parameterName))
                    }
                }
            }
        }
        if ($errors.Count -gt 0) { throw ($errors -join [Environment]::NewLine) }
        $errors.Count | Should Be 0
    }

    It 'keeps four corrected custom calls on -FirewallProfile' {
        $text = Get-Content -LiteralPath (Join-Path $libPath 'Installer.Firewall.ps1') -Raw
        ([regex]::Matches($text, '-FirewallProfile \$FirewallProfile')).Count | Should Be 4
    }

    It 'keeps the three Windows cmdlet -Profile calls' {
        $text = Get-Content -LiteralPath (Join-Path $libPath 'Installer.Firewall.ps1') -Raw
        ([regex]::Matches($text, 'Set-NetFirewallRule[^\r\n]*?-Profile|New-NetFirewallRule[^\r\n]*?-Profile|Set-NetFirewallRule[^\r\n]*?Profile \(\[string\]\$state\.profile\)')).Count | Should BeGreaterThan 0
    }

    It 'has a top-level catch that writes a failure report' {
        $main = Get-Content -LiteralPath (Join-Path $root 'installer/Install-CyberButler.ps1') -Raw
        $main | Should Match 'catch \{'
        $main | Should Match 'install-report.json'
        $main | Should Match 'unhandled'
    }
}
