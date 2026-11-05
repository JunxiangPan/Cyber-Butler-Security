# Helpers for the Cyber-Butler WPF installer front-end.

function ConvertTo-CyberButlerPowerShellLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + ($Value -replace "'", "''") + "'"
}

<#
.SYNOPSIS
    New-CyberButlerInteractiveInstallCommand performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function New-CyberButlerInteractiveInstallCommand {
    param(
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)][ValidateSet('High', 'Medium', 'Light')][string]$Tier,
        [Parameter(Mandatory = $true)][string]$InstallPath,
        [string]$OwnerQQ = '',
        [ValidateSet('Loopback', 'Tailscale', 'LAN')][string]$WebUIBind = 'Loopback',
        [string]$PersonalPluginsPath = '',
        [string]$ApiKeyFile = '',
        [int]$StartupTimeoutSeconds = 180
    )

    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add('& ' + (ConvertTo-CyberButlerPowerShellLiteral $InstallerPath))
    $parts.Add('-Tier ' + (ConvertTo-CyberButlerPowerShellLiteral $Tier))
    $parts.Add('-InstallPath ' + (ConvertTo-CyberButlerPowerShellLiteral $InstallPath))
    if (-not [string]::IsNullOrWhiteSpace($OwnerQQ)) {
        $parts.Add('-OwnerQQ ' + (ConvertTo-CyberButlerPowerShellLiteral $OwnerQQ))
    }
    if (-not [string]::IsNullOrWhiteSpace($WebUIBind)) {
        $parts.Add('-WebUIBind ' + (ConvertTo-CyberButlerPowerShellLiteral $WebUIBind))
    }
    if (-not [string]::IsNullOrWhiteSpace($PersonalPluginsPath)) {
        $parts.Add('-PersonalPluginsPath ' + (ConvertTo-CyberButlerPowerShellLiteral $PersonalPluginsPath))
    }
    if (-not [string]::IsNullOrWhiteSpace($ApiKeyFile)) {
        $parts.Add('-ApiKeyFile ' + (ConvertTo-CyberButlerPowerShellLiteral $ApiKeyFile))
    }
    $parts.Add('-StartupTimeoutSeconds ' + [int]$StartupTimeoutSeconds)
    return ($parts -join ' ')
}
