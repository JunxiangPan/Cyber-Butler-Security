# TOTP material and vault lifecycle for the Cyber-Butler installer.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

function Get-CyberButlerTotpMaterialPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultPath
    )
    return [pscustomobject][ordered]@{
        vault = [IO.Path]::GetFullPath($VaultPath)
        secret = Join-Path ([IO.Path]::GetFullPath($VaultPath)) 'totp_secret.dpapi'
        recovery = Join-Path ([IO.Path]::GetFullPath($VaultPath)) 'recovery_codes.txt'
        qr = Join-Path ([IO.Path]::GetFullPath($VaultPath)) 'totp_qr.png'
    }
}

function Test-CyberButlerTotpVaultAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultPath,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount,
        [Parameter(Mandatory = $true)]
        [string]$AstrBotAccount,
        [bool]$RequireAstrBotDeny = $true
    )

    $result = [ordered]@{
        vault_exists = $false
        reader_ok = $false
        system_ok = $false
        administrators_ok = $false
        astrbot_deny = $false
        satisfied = $false
        reason = ''
    }
    if (-not (Test-CyberButlerPathExists -Path $VaultPath)) {
        $result.reason = 'vault-missing'
        return [pscustomobject]$result
    }
    if ($ReaderAccount -ieq $AstrBotAccount) {
        $result.reason = 'reader-and-astrbot-are-same-account'
        return [pscustomobject]$result
    }
    try {
        $acl = Get-Acl -LiteralPath $VaultPath -ErrorAction Stop
        $readerSid = ([System.Security.Principal.NTAccount]$ReaderAccount).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $astrbotSid = ([System.Security.Principal.NTAccount]$AstrBotAccount).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($currentSid -eq $astrbotSid) { $RequireAstrBotDeny = $false }
        foreach ($rule in @($acl.Access)) {
            $id = [string]$rule.IdentityReference.Value
            $sid = $null
            try { $sid = ([System.Security.Principal.NTAccount]$id).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }
            if ([string]$rule.AccessControlType -eq 'Allow') {
                if ($sid -eq 'S-1-5-18') { $result.system_ok = $true }
                if ($sid -eq 'S-1-5-32-544') { $result.administrators_ok = $true }
                if ($sid -eq $readerSid) { $result.reader_ok = $true }
            } elseif ([string]$rule.AccessControlType -eq 'Deny' -and $sid -eq $astrbotSid) {
                $result.astrbot_deny = $true
            }
        }
        $result.vault_exists = $true
        $result.satisfied = $result.system_ok -and $result.administrators_ok -and $result.reader_ok -and ((-not $RequireAstrBotDeny) -or $result.astrbot_deny)
        if (-not $result.satisfied) { $result.reason = 'vault-acl-incomplete' }
    } catch {
        $result.reason = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Test-CyberButlerTotp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultPath,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount,
        [Parameter(Mandatory = $true)]
        [string]$AstrBotAccount,
        [bool]$RequireAstrBotDeny = $true,
        $Handlers = @{}
    )

    $context = [pscustomobject]@{ VaultPath = $VaultPath; ReaderAccount = $ReaderAccount; AstrBotAccount = $AstrBotAccount }
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'totp.test') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'totp.test' -Context $context)
    }

    $paths = Get-CyberButlerTotpMaterialPaths -VaultPath $VaultPath
    $acl = Test-CyberButlerTotpVaultAcl -VaultPath $paths.vault -ReaderAccount $ReaderAccount -AstrBotAccount $AstrBotAccount -RequireAstrBotDeny $RequireAstrBotDeny
    $result = [ordered]@{
        vault_path = $paths.vault
        secret_path = $paths.secret
        recovery_path = $paths.recovery
        qr_path = $paths.qr
        secret_exists = (Test-CyberButlerPathExists -Path $paths.secret -AssumeExistsOnError)
        recovery_exists = (Test-CyberButlerPathExists -Path $paths.recovery -AssumeExistsOnError)
        qr_exists = (Test-CyberButlerPathExists -Path $paths.qr -AssumeExistsOnError)
        vault_exists = $acl.vault_exists
        vault_acl_satisfied = $acl.satisfied
        reader_account = $ReaderAccount
        astrbot_account = $AstrBotAccount
        supported = $true
        can_manage = [bool](Test-InstallerAdministrator)
        satisfied = $false
        reason = $acl.reason
    }
    $result.satisfied = $result.secret_exists -and $result.recovery_exists -and $result.qr_exists -and $result.vault_acl_satisfied
    if (-not $result.satisfied -and -not $result.reason) { $result.reason = 'totp-material-or-acl-missing' }
    return [pscustomobject]$result
}

function New-CyberButlerTotpMaterial {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$VaultPath,
        [Parameter(Mandatory = $true)]
        [string]$Issuer,
        [Parameter(Mandatory = $true)]
        [string]$Account,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'totp.generate') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'totp.generate' -Context ([pscustomobject]@{
            Root = $Root; VaultPath = $VaultPath; Issuer = $Issuer; Account = $Account
        }))
    }

    $paths = Get-CyberButlerTotpMaterialPaths -VaultPath $VaultPath
    New-Item -ItemType Directory -Path $paths.vault -Force | Out-Null
    $python = Join-Path $Root 'AstrBot\.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $python)) {
        $command = Get-Command python.exe -ErrorAction SilentlyContinue
        if ($command) { $python = [string]$command.Source }
    }
    if (-not (Test-Path -LiteralPath $python)) { throw 'Python is required to generate TOTP QR material.' }
    $helper = Join-Path $PSScriptRoot 'totp_material.py'
    if (-not (Test-Path -LiteralPath $helper)) { throw "TOTP helper missing: $helper" }

    $generationOutput = (& $python $helper --vault $paths.vault --secret $paths.secret --recovery $paths.recovery --qr $paths.qr --issuer $Issuer --account $Account 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0) { throw 'TOTP material generation failed.' }
    $secret = $null
    $uri = $null
    $recoveryCodes = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($generationOutput -split "`r?`n")) {
        if ($line -match '^TOTP_SECRET=(.+)$') { $secret = $Matches[1].Trim() }
        elseif ($line -match '^TOTP_URI=(.+)$') { $uri = $Matches[1].Trim() }
        elseif ($line -match '^TOTP_RECOVERY_[0-9]+=(.+)$') { $recoveryCodes.Add($Matches[1].Trim()) }
    }
    return [pscustomobject]@{
        secret_path = $paths.secret
        recovery_path = $paths.recovery
        qr_path = $paths.qr
        secret = $secret
        uri = $uri
        recovery_codes = $recoveryCodes.ToArray()
        created = $true
    }
}

function Show-CyberButlerTotpEnrollment {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$VaultPath,
        [Parameter(Mandatory = $true)]
        [string]$Issuer,
        [Parameter(Mandatory = $true)]
        [string]$Account,
        $Handlers = @{}
    )

    $paths = Get-CyberButlerTotpMaterialPaths -VaultPath $VaultPath
    $existing = (Test-CyberButlerPathExists -Path $paths.secret -AssumeExistsOnError) -or
        (Test-CyberButlerPathExists -Path $paths.recovery -AssumeExistsOnError) -or
        (Test-CyberButlerPathExists -Path $paths.qr -AssumeExistsOnError)

    $material = $null
    if (-not $existing) {
        $material = New-CyberButlerTotpMaterial -Root $Root -VaultPath $VaultPath -Issuer $Issuer -Account $Account -Handlers $Handlers
    }

    Write-Host ''
    Write-Host '================ TOTP ENROLLMENT ================'
    if ($existing) {
        Write-Host 'Existing TOTP material found; it will not be regenerated.'
        Write-Host ('QR image: ' + $paths.qr)
        Write-Host ('Recovery codes: ' + $paths.recovery)
        if (Test-CyberButlerPathExists -Path $paths.recovery) {
            try {
                $recoveryText = Get-Content -LiteralPath $paths.recovery -Raw -ErrorAction Stop
                if ($recoveryText) { Write-Host $recoveryText.Trim() }
            } catch {
                Write-Host 'Recovery codes exist but cannot be read by the current account.'
            }
        }
    } else {
        if ($material.secret) {
            $grouped = $material.secret -replace '(.{4})(?=.)', '$1 '
            Write-Host ('Base32 Secret: ' + $material.secret)
            Write-Host ('Grouped:       ' + $grouped)
            Write-Host 'Enter the secret without spaces if your TOTP app asks for it.'
        }
        if ($material.uri) { Write-Host ('otpauth URI:  ' + $material.uri) }
        Write-Host ('QR image:      ' + $paths.qr)
        if ($material.recovery_codes -and $material.recovery_codes.Count -gt 0) {
            Write-Host 'Recovery codes (store offline, one use each):'
            for ($i = 0; $i -lt $material.recovery_codes.Count; $i++) {
                Write-Host ('  ' + ($i + 1) + '. ' + $material.recovery_codes[$i])
            }
        } else {
            Write-Host ('Recovery codes: ' + $paths.recovery)
        }
    }
    Write-Host 'Scan the QR image or enter the Base32 Secret in your TOTP app.'
    Write-Host 'Then confirm SCANNED and RECOVERY-SAVED.'
    Write-Host '================================================'
    Write-Host ''

    if ($existing) {
        return [pscustomobject]@{
            secret_path = $paths.secret
            recovery_path = $paths.recovery
            qr_path = $paths.qr
            secret = $null
            uri = $null
            recovery_codes = @()
            created = $false
            existing = $true
        }
    }
    return $material
}

function Set-CyberButlerTotpVaultAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultPath,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount,
        [Parameter(Mandatory = $true)]
        [string]$AstrBotAccount,
        [bool]$RequireAstrBotDeny = $true,
        $Journal = $null,
        [string]$JournalStep = 'totp',
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'totp.acl') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'totp.acl' -Context ([pscustomobject]@{
            VaultPath = $VaultPath; ReaderAccount = $ReaderAccount; AstrBotAccount = $AstrBotAccount
            Journal = $Journal; JournalStep = $JournalStep
        }))
    }
    if ($ReaderAccount -ieq $AstrBotAccount) { throw 'Vault reader account cannot equal the AstrBot account.' }
    if ($null -eq $Journal) { throw 'TOTP vault ACL changes require a journal for backup.' }

    $backup = Backup-CyberButlerAcl -Journal $Journal -Step $JournalStep -Path $VaultPath -NoTrack
    $acl = Get-Acl -LiteralPath $VaultPath -ErrorAction Stop
    $acl.SetAccessRuleProtection($true, $false)
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $deny = [System.Security.AccessControl.AccessControlType]::Deny
    $inherit = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit,ObjectInherit'
    $prop = [System.Security.AccessControl.PropagationFlags]::None
    $currentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $astrbotSid = ([System.Security.Principal.NTAccount]$AstrBotAccount).Translate([System.Security.Principal.SecurityIdentifier]).Value
    $denyAstrBot = [bool]$RequireAstrBotDeny
    if ($currentSid -eq $astrbotSid) { $denyAstrBot = $false }

    # Remove stale explicit denies that would still block the installer or the
    # single-account AstrBot identity. Inherited rules were already removed.
    foreach ($rule in @($acl.Access)) {
        if ([string]$rule.AccessControlType -ne 'Deny') { continue }
        $ruleSid = $null
        try { $ruleSid = ([System.Security.Principal.NTAccount]([string]$rule.IdentityReference.Value)).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }
        if ($ruleSid -eq $currentSid -or (-not $denyAstrBot -and $ruleSid -eq $astrbotSid)) {
            $acl.RemoveAccessRule($rule) | Out-Null
        }
    }

    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('SYSTEM', 'FullControl', $inherit, $prop, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators', 'FullControl', $inherit, $prop, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($currentIdentity, 'FullControl', $inherit, $prop, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($ReaderAccount, 'Read,ReadAndExecute', $inherit, $prop, $allow)))
    if ($denyAstrBot) {
        $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($AstrBotAccount, 'FullControl', $inherit, $prop, $deny)))
    }
    Set-Acl -LiteralPath $VaultPath -AclObject $acl -ErrorAction Stop
    return $backup
}

function Assert-CyberButlerTotp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$VaultPath,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount,
        [Parameter(Mandatory = $true)]
        [string]$AstrBotAccount,
        [bool]$RequireAstrBotDeny = $true,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'totp.assert') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'totp.assert' -Context ([pscustomobject]@{
            VaultPath = $VaultPath; ReaderAccount = $ReaderAccount; AstrBotAccount = $AstrBotAccount
        }))
    }
    $test = Test-CyberButlerTotp -VaultPath $VaultPath -ReaderAccount $ReaderAccount -AstrBotAccount $AstrBotAccount -RequireAstrBotDeny $RequireAstrBotDeny -Handlers $Handlers
    return [bool]$test.satisfied
}

function Undo-CyberButlerTotp {
    param(
        [Parameter(Mandatory = $true)]
        $Paths,
        [bool]$Created = $false,
        [string]$AclBackup = '',
        [string]$VaultPath = '',
        [hashtable]$FileBackups = @{},
        [bool]$Uncertain = $false,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'totp.undo') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'totp.undo' -Context ([pscustomobject]@{
            Paths = $Paths; Created = $Created; AclBackup = $AclBackup; VaultPath = $VaultPath; FileBackups = $FileBackups; Uncertain = $Uncertain
        }))
    }
    if ($Uncertain -or -not $Created) {
        return [pscustomobject]@{ action = 'manual'; reason = 'pre-existing or uncertain material retained' }
    }
    foreach ($path in @($Paths.secret, $Paths.recovery, $Paths.qr)) {
        if (-not $path) { continue }
        if ($FileBackups.ContainsKey($path) -and (Test-CyberButlerPathExists -Path $FileBackups[$path])) {
            Copy-Item -LiteralPath $FileBackups[$path] -Destination $path -Force
        } elseif (Test-CyberButlerPathExists -Path $path -AssumeExistsOnError) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    if ($AclBackup -and (Test-CyberButlerPathExists -Path $AclBackup)) {
        try {
            $acl = Import-Clixml -LiteralPath $AclBackup
            Set-Acl -LiteralPath $VaultPath -AclObject $acl -ErrorAction Stop
        } catch { }
    }
    return [pscustomobject]@{ action = 'removed'; paths = @($Paths.secret, $Paths.recovery, $Paths.qr) }
}

function Invoke-CyberButlerTotp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$VaultPath,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount,
        [Parameter(Mandatory = $true)]
        [string]$AstrBotAccount,
        [bool]$RequireAstrBotDeny = $true,
        [string]$Issuer = 'Cyber-Butler',
        [string]$Account = 'owner',
        [string]$JournalStep = 'totp',
        $Journal = $null,
        [string]$Approval = '',
        [switch]$Scanned,
        [switch]$RecoverySaved,
        [switch]$SkipMaterialGeneration,
        [switch]$NonInteractive,
        [switch]$PlanOnly,
        $Handlers = @{}
    )

    $test = Test-CyberButlerTotp -VaultPath $VaultPath -ReaderAccount $ReaderAccount -AstrBotAccount $AstrBotAccount -RequireAstrBotDeny $RequireAstrBotDeny -Handlers $Handlers
    $base = [ordered]@{
        module = 'totp'
        step = $JournalStep
        vault_path = $VaultPath
        test = $test
        changed = $false
    }
    if ($test.satisfied) {
        $base.status = 'skipped'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if ($ReaderAccount -ieq $AstrBotAccount) {
        $base.status = 'conflict'
        $base.message = 'Vault reader account cannot equal the AstrBot account.'
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        return [pscustomobject]$base
    }
    if (-not $test.can_manage) {
        $base.status = 'needs_elevation'
        $base.message = 'TOTP vault hardening requires administrator rights.'
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        return [pscustomobject]$base
    }

    $approvalState = Get-CyberButlerApprovalState -Required 'APPROVE TOTP' -Approval $Approval -NonInteractive:$NonInteractive -PlanOnly:$PlanOnly
    if ($approvalState -eq 'plan') {
        $base.status = 'plan'
        $base.message = 'Would generate TOTP material and harden the vault ACL.'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if ($approvalState -ne 'approved') {
        $base.status = 'needs_approval'
        $base.exit_code = Get-InstallerExitCode -Name NeedsApproval
        return [pscustomobject]$base
    }
    if (-not $Scanned -or -not $RecoverySaved) {
        $base.status = 'needs_confirmation'
        $base.message = 'Confirm the QR code has been scanned and recovery codes have been stored offline.'
        $base.exit_code = Get-InstallerExitCode -Name NeedsApproval
        return [pscustomobject]$base
    }

    $paths = Get-CyberButlerTotpMaterialPaths -VaultPath $VaultPath
    $existedFiles = @{}
    foreach ($file in @($paths.secret, $paths.recovery, $paths.qr)) {
        $existedFiles[$file] = Test-CyberButlerPathExists -Path $file -AssumeExistsOnError
    }
    $vaultExisted = Test-CyberButlerPathExists -Path $paths.vault
    $fileBackups = @{}
    if ($null -ne $Journal) {
        Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status in_progress | Out-Null
        foreach ($file in @($paths.secret, $paths.recovery, $paths.qr)) {
            if (Test-CyberButlerPathExists -Path $file -AssumeExistsOnError) {
                $fileBackups[$file] = Backup-CyberButlerFile -Journal $Journal -Step $JournalStep -Path $file -AllowedRoot (Split-Path -Parent $file)
            }
        }
    }

    $created = $false
    $aclBackup = $null
    try {
        if (-not (Test-CyberButlerPathExists -Path $paths.vault)) {
            New-Item -ItemType Directory -Path $paths.vault -Force | Out-Null
            $created = $true
        }
        if (-not $SkipMaterialGeneration) {
            $material = New-CyberButlerTotpMaterial -Root $Root -VaultPath $VaultPath -Issuer $Issuer -Account $Account -Handlers $Handlers
            $created = $created -or [bool]$material.created
        }
        if ($null -ne $Journal) {
            foreach ($file in @($paths.secret, $paths.recovery, $paths.qr)) {
                if (-not $existedFiles[$file] -and (Test-CyberButlerPathExists -Path $file -AssumeExistsOnError)) {
                    Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                        type = 'delete-created-file'
                        path = [IO.Path]::GetFullPath($file)
                        allowed_root = [IO.Path]::GetFullPath($paths.vault)
                    })
                }
            }
        }
        $aclBackup = Set-CyberButlerTotpVaultAcl -VaultPath $paths.vault -ReaderAccount $ReaderAccount -AstrBotAccount $AstrBotAccount -RequireAstrBotDeny $RequireAstrBotDeny -Journal $Journal -JournalStep $JournalStep -Handlers $Handlers
        if ($null -ne $Journal -and $aclBackup) {
            Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                type = 'restore-acl'
                target = [IO.Path]::GetFullPath($paths.vault)
                backup = [IO.Path]::GetFullPath($aclBackup)
            })
        }
        $asserted = Assert-CyberButlerTotp -VaultPath $paths.vault -ReaderAccount $ReaderAccount -AstrBotAccount $AstrBotAccount -RequireAstrBotDeny $RequireAstrBotDeny -Handlers $Handlers
        if (-not $asserted) { throw 'TOTP assertion failed.' }
        if ($null -ne $Journal) { Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status completed | Out-Null }
        $base.status = 'completed'
        $base.changed = $created
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    } catch {
        $undo = Undo-CyberButlerTotp -Paths $paths -Created $created -AclBackup $aclBackup -VaultPath $paths.vault -FileBackups $fileBackups -Uncertain:(-not $created -and -not $vaultExisted) -Handlers $Handlers
        $base.status = 'failed'
        $base.message = $_.Exception.Message
        $base.undo = $undo
        $base.exit_code = if ($undo.action -eq 'manual') { Get-InstallerExitCode -Name NeedsApproval } else { Get-InstallerExitCode -Name ValidationFailed }
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ error = $_.Exception.Message; undo = $undo.action }) | Out-Null
        }
        return [pscustomobject]$base
    }
}
