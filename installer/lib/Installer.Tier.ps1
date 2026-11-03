# Tier profile loading, validation, and plan rendering.
# Dot-source Installer.Common.ps1 before this file.

function Import-CyberButlerProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tier,
        [Parameter(Mandatory = $true)]
        [string]$ProfileRoot
    )

    $path = Join-Path $ProfileRoot ("{0}.json" -f $Tier.ToLowerInvariant())
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Installer profile not found: $path"
    }

    $profile = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    if ([int]$profile.schema -ne 1) {
        throw "Unsupported installer profile schema: $($profile.schema)"
    }
    if ([string]$profile.tier -ne $Tier) {
        throw "Profile tier mismatch: expected $Tier, got $($profile.tier)"
    }
    return $profile
}

function Format-CyberButlerPlan {
    param(
        [Parameter(Mandatory = $true)]
        $Resolution
    )

    $p = $Resolution.Profile
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('Cyber-Butler installer plan (v1.6.3)')
    $lines.Add('Mode: PlanOnly - no files will be changed.')
    $lines.Add(('Tier: {0}' -f $Resolution.Tier))
    $lines.Add(('Effective: {0}' -f $Resolution.EffectiveLabel))
    $lines.Add(('Isolation: {0}' -f $Resolution.Isolation))
    $lines.Add(('Install path: {0}' -f $Resolution.InstallPath))
    $lines.Add(('Existing install: {0}' -f $Resolution.ExistingState))
    $lines.Add(('Web UI bind: {0}' -f $Resolution.WebUIBind))

    $mode = switch ($Resolution.ExistingState) {
        'Installed' { 'upgrade / repair / migration plan' }
        'Legacy'    { 'upgrade / repair / migration plan (legacy install, no installer state marker)' }
        default     { 'fresh install plan' }
    }
    $lines.Add(('Plan path: {0}' -f $mode))
    $lines.Add('')
    $lines.Add('Security controls:')
    $lines.Add(('  Code ACL: {0}' -f $p.codeAcl))
    $lines.Add(('  TOTP vault: {0}' -f $p.totpVault))
    $lines.Add(('  TOTP destructive: {0}' -f $p.totpDestructive))
    $lines.Add(('  TOTP egress: {0}' -f $p.totpEgress))
    $lines.Add(('  Router fail-closed: {0}' -f $p.routerFailClosed))
    $lines.Add(('  Automatic cloud fallback: {0}' -f $p.autoCloudFallback))
    $lines.Add(('  Shell / Python tools: {0}' -f $p.shellTools))
    $lines.Add(('  Firewall: {0}' -f $p.firewall))
    $lines.Add(('  Audit: {0}' -f $p.audit))
    $lines.Add(('  Broker account: {0}' -f $p.brokerAccount))
    $lines.Add(('  ExternalAgent account: {0}' -f $p.astrbotAccount))
    $lines.Add(('  ExternalApplication account: {0}' -f $p.snowLumaAccount))

    $lines.Add('')
    $lines.Add('BLOCKING approvals:')
    foreach ($item in $Resolution.BlockingApprovals) {
        $lines.Add(('  {0}' -f $item))
    }

    if ($Resolution.ManualSteps.Count -gt 0) {
        $lines.Add('')
        $lines.Add('Manual / follow-up:')
        foreach ($item in $Resolution.ManualSteps) {
            $lines.Add(('  {0}' -f $item))
        }
    }

    if ($Resolution.Warnings.Count -gt 0) {
        $lines.Add('')
        $lines.Add('Warnings:')
        foreach ($item in $Resolution.Warnings) {
            $lines.Add(('  {0}' -f $item))
        }
    }

    if ($Resolution.Errors.Count -gt 0) {
        $lines.Add('')
        $lines.Add('Errors:')
        foreach ($item in $Resolution.Errors) {
            $lines.Add(('  {0}' -f $item))
        }
    }

    return ($lines -join [Environment]::NewLine)
}

function Resolve-CyberButlerTier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('High', 'Medium', 'Light')]
        [string]$Tier,

        [Nullable[bool]]$EnableIsolation = $null,

        [switch]$AcceptLowerSecurity,
        [switch]$AllowSecurityDowngrade,

        [Parameter(Mandatory = $true)]
        [string]$ProfileRoot,

        [string]$InstallPath = 'C:\CyberButler',
        [string]$WebUIBind = '',
        [switch]$EnableTailscaleServe,
        [string]$OwnerQQ = '',

        [int]$ExternalAgentPort = 6185,
        [int]$BrokerPort = 18090,
        [int]$WebUIPort = 8765,
        [int]$OtpMailerPort = 8766
    )

    $errors = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $blocking = New-Object System.Collections.Generic.List[string]
    $manual = New-Object System.Collections.Generic.List[string]

    $profile = $null
    try {
        $profile = Import-CyberButlerProfile -Tier $Tier -ProfileRoot $ProfileRoot
    } catch {
        $errors.Add($_.Exception.Message)
        return [pscustomobject]@{
            Tier = $Tier; EffectiveLabel = $Tier; Isolation = $false
            Profile = $null; ExistingState = 'Unknown'; HasExistingInstall = $false; WebUIBind = $WebUIBind
            InstallPath = $InstallPath; BlockingApprovals = $blocking
            ManualSteps = $manual; Warnings = $warnings; Errors = $errors
            ExitCode = (Get-InstallerExitCode -Name ValidationFailed)
            PlanText = ''
        }
    }

    $isolation = if ($null -ne $EnableIsolation) {
        [bool]$EnableIsolation
    } else {
        [bool]$profile.enableIsolation
    }

    if ($Tier -eq 'High' -and -not $isolation) {
        $errors.Add('High requires -EnableIsolation:$true; isolation cannot be disabled.')
    }
    if ($Tier -eq 'Light' -and -not $AcceptLowerSecurity) {
        $errors.Add('Light requires -AcceptLowerSecurity because it is an explicit security downgrade.')
    }
    if ([string]::IsNullOrWhiteSpace($InstallPath)) {
        $errors.Add('InstallPath is required.')
    }

    if ([string]::IsNullOrWhiteSpace($WebUIBind)) {
        $WebUIBind = [string]$profile.webUIBind
    }
    if ($WebUIBind -notin @('Loopback', 'Tailscale', 'LAN')) {
        $errors.Add("WebUIBind must be Loopback, Tailscale, or LAN; got: $WebUIBind")
    }
    if ($WebUIBind -eq 'LAN' -and -not [bool]$profile.allowLan) {
        $errors.Add("$Tier does not allow LAN binding.")
    }
    if ($WebUIBind -eq 'Tailscale' -and -not $EnableTailscaleServe) {
        $manual.Add('Enable Tailscale Serve before relying on the Web UI URL.')
    }

    $ports = @($ExternalAgentPort, $BrokerPort, $WebUIPort, $OtpMailerPort)
    foreach ($port in $ports) {
        if ($port -lt 1 -or $port -gt 65535) {
            $errors.Add("Port out of range: $port")
        }
    }
    if (($ports | Select-Object -Unique).Count -ne $ports.Count) {
        $errors.Add('ExternalAgentPort, BrokerPort, WebUIPort and OtpMailerPort must be distinct.')
    }

    $blocking.Add('APPROVE PLAN')
    if ($isolation) {
        $blocking.Add('APPROVE ACCOUNT')
    }
    $blocking.Add('APPROVE ACL')
    $blocking.Add('APPROVE TOTP')
    $blocking.Add('APPROVE FIREWALL')
    $blocking.Add('APPROVE SECRETS')
    $blocking.Add('APPROVE SERVICES')
    if ($WebUIBind -eq 'LAN') {
        $blocking.Add('APPROVE LAN')
    }
    if ($Tier -eq 'Light') {
        $blocking.Add('APPROVE LIGHT')
    }

    if (-not $isolation) {
        $warnings.Add('Single-account mode: ExternalAgent and the desktop user share an identity; TOTP guards model actions, not account compromise.')
    }
    if ($Tier -eq 'Light') {
        $warnings.Add('Light is an explicit lower-security profile; code ACL, TOTP egress, and daily audit are reduced.')
    }
    if ($Tier -eq 'Medium' -and $isolation) {
        $warnings.Add('Medium + Isolation adds account isolation and code ACL, but is not equivalent to High.')
    }
    if ($Tier -eq 'Light' -and $isolation) {
        $warnings.Add('Light + Isolation adds account isolation and code ACL, but is not equivalent to High.')
    }
    if ([string]::IsNullOrWhiteSpace($OwnerQQ)) {
        $manual.Add('Supply -OwnerQQ before a real installation.')
    }
    $manual.Add('You will be prompted for API Key and SMTP Secret during install, or pass -ApiKey / -SmtpSecret.')

    if (-not (Test-InstallerAdministrator)) {
        $manual.Add('Run the installer from an elevated PowerShell session.')
    }
    $manual.Add('Scan the TOTP QR code and store the recovery codes offline.')
    $manual.Add('If `where python` shows WindowsApps before real Python, disable App Execution Aliases for python.exe and python3.exe or move real Python to the front of PATH.')
    $manual.Add('Log in to QQ / ExternalApplication on the desktop account.')

    $effective = if ($isolation -and $Tier -ne 'High') { "$Tier + Isolation" } else { $Tier }
    $existing = Get-CyberButlerExistingState -InstallPath $InstallPath
    $exitCode = if ($errors.Count -gt 0) {
        Get-InstallerExitCode -Name ValidationFailed
    } else {
        Get-InstallerExitCode -Name Success
    }

    $resolution = [pscustomobject]@{
        Tier = $Tier
        EffectiveLabel = $effective
        Isolation = $isolation
        Profile = $profile
        ExistingState = $existing
        HasExistingInstall = ($existing -ne 'None')
        WebUIBind = $WebUIBind
        InstallPath = $InstallPath
        BlockingApprovals = $blocking
        ManualSteps = $manual
        Warnings = $warnings
        Errors = $errors
        ExitCode = $exitCode
        PlanText = ''
    }
    $resolution.PlanText = Format-CyberButlerPlan -Resolution $resolution
    return $resolution
}
