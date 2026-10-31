# Shared constants and helpers for the Cyber-Butler installer.
# Dot-source this file before the other installer modules.

$script:InstallerExitCodes = [ordered]@{
    Success           = 0
    ManualFollowUp    = 2
    NeedsApproval     = 10
    ValidationFailed  = 20
    NotImplemented    = 21
    RollbackFailed    = 30
    UnexpectedError   = 1
}

function Get-InstallerExitCode {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if (-not $script:InstallerExitCodes.Contains($Name)) {
        throw "Unknown installer exit code: $Name"
    }
    return [int]$script:InstallerExitCodes[$Name]
}

function Write-InstallerLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'BLOCKING')]
        [string]$Level = 'INFO'
    )

    $prefix = switch ($Level) {
        'WARN'     { '[WARN]' }
        'ERROR'    { '[ERROR]' }
        'BLOCKING' { '[BLOCKING]' }
        default    { '[INFO]' }
    }
    Write-Host ("{0} {1}" -f $prefix, $Text)
}

function Test-InstallerAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function ConvertTo-InstallerBool {
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )

    if ($Value -is [bool]) { return $Value }
    if ($Value -is [string]) {
        if ($Value -ieq 'true') { return $true }
        if ($Value -ieq 'false') { return $false }
    }
    throw "Cannot convert value to bool: $Value"
}

function Test-CyberButlerPathExists {
    param(
        [string]$Path,
        [switch]$AssumeExistsOnError,
        [scriptblock]$Probe = $null
    )
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        if ($null -ne $Probe) { return [bool](& $Probe $Path) }
        return [bool](Test-Path -LiteralPath $Path -ErrorAction Stop)
    } catch {
        return [bool]$AssumeExistsOnError
    }
}

function ConvertTo-CyberButlerSecureString {
    param($Value = $null)
    if ($null -eq $Value) { return $null }
    if ($Value -is [Security.SecureString]) { return $Value }
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        return (ConvertTo-SecureString $Value -AsPlainText -Force)
    }
    throw ('Expected a plain string or SecureString, got ' + $Value.GetType().FullName)
}

function Test-CyberButlerSecureStringEmpty {
    param($Value = $null)
    if ($null -eq $Value) { return $true }
    if ($Value -is [string]) { return [string]::IsNullOrWhiteSpace($Value) }
    if ($Value -is [Security.SecureString]) {
        try { return ($Value.Length -eq 0) } catch { return $true }
    }
    return $false
}

function Read-CyberButlerSecureSecret {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [scriptblock]$Reader = $null
    )
    Write-Host $Prompt
    if ($null -ne $Reader) { return (& $Reader) }
    return (Read-Host -AsSecureString)
}

function Get-CyberButlerInstallStatePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )
    return (Join-Path ([IO.Path]::GetFullPath($InstallPath)) 'installer\install-state.json')
}

function Test-CyberButlerInstalledMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )
    $path = Get-CyberButlerInstallStatePath -InstallPath $InstallPath
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    try {
        $state = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        return ([bool]$state.installed -eq $true)
    } catch {
        return $false
    }
}

function Get-CyberButlerExistingState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath
    )

    if ([string]::IsNullOrWhiteSpace($InstallPath)) { return 'None' }
    if (-not (Test-Path -LiteralPath $InstallPath)) { return 'None' }
    $version = Join-Path ([IO.Path]::GetFullPath($InstallPath)) 'VERSION'
    if (-not (Test-Path -LiteralPath $version -PathType Leaf)) { return 'None' }
    if (Test-CyberButlerInstalledMarker -InstallPath $InstallPath) { return 'Installed' }
    return 'Legacy'
}

function Write-CyberButlerInstallStateMarker {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InstallPath,
        [Parameter(Mandatory = $true)]
        [string]$Version,
        [string]$Tier = '',
        [bool]$Isolation = $false,
        [string]$Source = 'installer'
    )

    $path = Get-CyberButlerInstallStatePath -InstallPath $InstallPath
    $versionPath = Join-Path ([IO.Path]::GetFullPath($InstallPath)) 'VERSION'
    [IO.File]::WriteAllText($versionPath, $Version + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    $state = [ordered]@{
        schema = 1
        installed = $true
        version = $Version
        tier = $Tier
        isolation = [bool]$Isolation
        source = $Source
        installed_at = Get-InstallerUtcTimestamp
    }
    Write-InstallerJson -Path $path -Value $state
    return $path
}

function Get-InstallerUtcTimestamp {
    return [DateTime]::UtcNow.ToString('o')
}

function New-InstallerRunId {
    $suffix = [guid]::NewGuid().ToString('N').Substring(0, 6)
    return ('{0}-{1}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $suffix)
}

function Write-InstallerJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $Value
    )

    $full = [IO.Path]::GetFullPath($Path)
    $parent = Split-Path -Parent $full
    if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $json = $Value | ConvertTo-Json -Depth 12
    $temporary = $full + '.tmp'
    [IO.File]::WriteAllText($temporary, $json + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $temporary -Destination $full -Force
}

function Read-InstallerJson {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json)
}

function Test-InstallerPathWithin {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
    if ($fullPath -ieq $fullRoot) { return $false }
    return $fullPath.StartsWith($fullRoot + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Get-InstallerFileSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-CyberButlerApprovalState {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Required,
        [string]$Approval = '',
        [switch]$NonInteractive,
        [switch]$PlanOnly
    )

    if ($PlanOnly) { return 'plan' }
    if ($Approval -ceq $Required) { return 'approved' }
    return 'needs_approval'
}

function Test-CyberButlerHandler {
    param(
        $Handlers,
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($null -eq $Handlers) { return $false }
    if ($Handlers -isnot [System.Collections.IDictionary]) { return $false }
    return $Handlers.Contains($Name)
}

function Invoke-CyberButlerHandler {
    param(
        $Handlers,
        [Parameter(Mandatory = $true)]
        [string]$Name,
        $Context
    )

    if (-not (Test-CyberButlerHandler -Handlers $Handlers -Name $Name)) {
        throw "Handler not found: $Name"
    }
    return (& $Handlers[$Name] $Context)
}


