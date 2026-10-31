# DPAPI secret material and local-overlay lifecycle for the installer.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

function Get-CyberButlerSecretPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )
    $tools = Join-Path ([IO.Path]::GetFullPath($Root)) 'tools'
    return [pscustomobject][ordered]@{
        api_key = Join-Path $tools 'deepseek.key.dpapi'
        owner_qq = Join-Path $tools 'owner_qq.dpapi'
        smtp = Join-Path $tools 'smtp.secret.dpapi'
        overlay = Join-Path ([IO.Path]::GetFullPath($Root)) 'local-overlay.json'
    }
}

function Protect-CyberButlerString {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PlainText,
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$Scope = 'LocalMachine'
    )

    Add-Type -AssemblyName System.Security
    $dataScope = if ($Scope -eq 'LocalMachine') {
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    } else {
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    }
    $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    return [System.Security.Cryptography.ProtectedData]::Protect($bytes, $null, $dataScope)
}

function Unprotect-CyberButlerFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$Scope = 'LocalMachine'
    )

    Add-Type -AssemblyName System.Security
    $dataScope = if ($Scope -eq 'LocalMachine') {
        [System.Security.Cryptography.DataProtectionScope]::LocalMachine
    } else {
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect($bytes, $null, $dataScope)
    return [Text.Encoding]::UTF8.GetString($plain)
}

function Test-CyberButlerSecretAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount
    )

    $result = [ordered]@{ satisfied = $false; reason = '' }
    if (-not (Test-Path -LiteralPath $Path)) {
        $result.reason = 'file-missing'
        return [pscustomobject]$result
    }
    try {
        $readerSid = ([System.Security.Principal.NTAccount]$ReaderAccount).Translate([System.Security.Principal.SecurityIdentifier]).Value
        $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
        $readerOk = $false
        $unexpected = New-Object System.Collections.Generic.List[string]
        foreach ($rule in @($acl.Access)) {
            if ([string]$rule.AccessControlType -ne 'Allow') { continue }
            $sid = $null
            try { $sid = ([System.Security.Principal.NTAccount]([string]$rule.IdentityReference.Value)).Translate([System.Security.Principal.SecurityIdentifier]).Value } catch { }
            if ($sid -eq $readerSid) { $readerOk = $true; continue }
            if ($sid -in @('S-1-5-18', 'S-1-5-32-544')) { continue }
            if ((([int]$rule.FileSystemRights) -band [int][System.Security.AccessControl.FileSystemRights]::Read) -ne 0) {
                $unexpected.Add([string]$rule.IdentityReference.Value)
            }
        }
        $result.satisfied = $readerOk -and ($unexpected.Count -eq 0)
        if (-not $result.satisfied) { $result.reason = 'acl-not-restricted' }
    } catch {
        $result.reason = $_.Exception.Message
    }
    return [pscustomobject]$result
}

function Test-CyberButlerSecrets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount,
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$Scope = 'LocalMachine',
        $Handlers = @{}
    )

    $context = [pscustomobject]@{ Root = $Root; ReaderAccount = $ReaderAccount; Scope = $Scope }
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'secrets.test') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'secrets.test' -Context $context)
    }

    $paths = Get-CyberButlerSecretPaths -Root $Root
    $files = New-Object System.Collections.Generic.List[object]
    $allPresent = $true
    foreach ($item in @(
        @{ name = 'api_key'; path = $paths.api_key },
        @{ name = 'owner_qq'; path = $paths.owner_qq },
        @{ name = 'smtp'; path = $paths.smtp }
    )) {
        $exists = Test-Path -LiteralPath $item.path
        $decrypts = $false
        if ($exists) {
            try { Unprotect-CyberButlerFile -Path $item.path -Scope $Scope | Out-Null; $decrypts = $true } catch { $decrypts = $false }
        }
        $acl = if ($exists) { Test-CyberButlerSecretAcl -Path $item.path -ReaderAccount $ReaderAccount } else { [pscustomobject]@{ satisfied = $false; reason = 'file-missing' } }
        $files.Add([pscustomobject][ordered]@{
            name = $item.name
            path = $item.path
            exists = [bool]$exists
            decrypts = [bool]$decrypts
            acl_satisfied = [bool]$acl.satisfied
            acl_reason = $acl.reason
        })
        if (-not $exists -or -not $decrypts -or -not $acl.satisfied) { $allPresent = $false }
    }
    return [pscustomobject][ordered]@{
        root = [IO.Path]::GetFullPath($Root)
        reader_account = $ReaderAccount
        scope = $Scope
        files = $files.ToArray()
        overlay_exists = Test-Path -LiteralPath $paths.overlay
        satisfied = $allPresent -and (Test-Path -LiteralPath $paths.overlay)
        can_manage = [bool](Test-InstallerAdministrator)
        reason = if ($allPresent) { '' } else { 'secret-material-incomplete' }
    }
}

function Set-CyberButlerSecretFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [SecureString]$Value,
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$Scope = 'LocalMachine',
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'secrets.write') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'secrets.write' -Context ([pscustomobject]@{ Path = $Path; Scope = $Scope }))
    }
    $bstr = [IntPtr]::Zero
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Value)
        $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        $bytes = Protect-CyberButlerString -PlainText $plain -Scope $Scope
        $parent = Split-Path -Parent $Path
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        [IO.File]::WriteAllBytes($Path, $bytes)
    } finally {
        if ($bstr -ne [IntPtr]::Zero) { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    }
}

function Set-CyberButlerSecretAcl {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount,
        $Journal = $null,
        [string]$JournalStep = 'secrets',
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'secrets.acl') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'secrets.acl' -Context ([pscustomobject]@{ Path = $Path; ReaderAccount = $ReaderAccount }))
    }
    if ($null -eq $Journal) { throw 'Secret ACL changes require a journal for backup.' }
    $backup = Backup-CyberButlerAcl -Journal $Journal -Step $JournalStep -Path $Path -NoTrack
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $acl.SetAccessRuleProtection($true, $false)
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    $inherit = [System.Security.AccessControl.InheritanceFlags]'None'
    $prop = [System.Security.AccessControl.PropagationFlags]::None
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('SYSTEM', 'FullControl', $inherit, $prop, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule('BUILTIN\Administrators', 'FullControl', $inherit, $prop, $allow)))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($ReaderAccount, 'Read,ReadAndExecute', $inherit, $prop, $allow)))
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
    return $backup
}

function Assert-CyberButlerSecrets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount,
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$Scope = 'LocalMachine',
        $Handlers = @{}
    )
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'secrets.assert') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'secrets.assert' -Context ([pscustomobject]@{ Root = $Root; ReaderAccount = $ReaderAccount; Scope = $Scope }))
    }
    $test = Test-CyberButlerSecrets -Root $Root -ReaderAccount $ReaderAccount -Scope $Scope -Handlers $Handlers
    return [bool]$test.satisfied
}

function Undo-CyberButlerSecrets {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [bool]$Created = $false,
        [hashtable]$Backups = @{},
        [string[]]$NewFiles = @(),
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'secrets.undo') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'secrets.undo' -Context ([pscustomobject]@{ Root = $Root; Created = $Created; Backups = $Backups }))
    }
    $paths = Get-CyberButlerSecretPaths -Root $Root
    foreach ($key in @('api_key', 'owner_qq', 'smtp', 'overlay')) {
        $path = $paths.$key
        if ($Backups.ContainsKey($path) -and (Test-Path -LiteralPath $Backups[$path])) {
            Copy-Item -LiteralPath $Backups[$path] -Destination $path -Force
        } elseif (($NewFiles -contains $path) -and (Test-Path -LiteralPath $path)) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
    }
    return [pscustomobject]@{ action = if ($NewFiles.Count -gt 0) { 'removed' } else { 'restored' } }
}

function Invoke-CyberButlerSecrets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$ReaderAccount,
        [string]$OwnerQQ = '',
        [object]$ApiKey = $null,
        [object]$SmtpSecret = $null,
        [ValidateSet('LocalMachine', 'CurrentUser')]
        [string]$Scope = 'LocalMachine',
        [string]$JournalStep = 'secrets',
        $Journal = $null,
        [string]$Approval = '',
        [switch]$NonInteractive,
        [switch]$PlanOnly,
        [scriptblock]$Reader = $null,
        $Handlers = @{}
    )

    $ApiKey = ConvertTo-CyberButlerSecureString -Value $ApiKey
    $SmtpSecret = ConvertTo-CyberButlerSecureString -Value $SmtpSecret
    $test = Test-CyberButlerSecrets -Root $Root -ReaderAccount $ReaderAccount -Scope $Scope -Handlers $Handlers
    $base = [ordered]@{ module = 'secrets'; step = $JournalStep; root = $Root; test = $test; changed = $false }
    if ($test.satisfied) {
        $base.status = 'skipped'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if (-not $test.can_manage) {
        $base.status = 'needs_elevation'
        $base.message = 'Secret ACL hardening requires administrator rights.'
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        return [pscustomobject]$base
    }

    $approvalState = Get-CyberButlerApprovalState -Required 'APPROVE SECRETS' -Approval $Approval -NonInteractive:$NonInteractive -PlanOnly:$PlanOnly
    if ($approvalState -eq 'plan') {
        $base.status = 'plan'
        $base.message = 'Would write DPAPI secrets, local-overlay.json, and restricted ACLs.'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if ($approvalState -ne 'approved') {
        $base.status = 'needs_approval'
        $base.exit_code = Get-InstallerExitCode -Name NeedsApproval
        return [pscustomobject]$base
    }

    $skipApiKey = $false
    $skipSmtp = $false
    if (Test-CyberButlerSecureStringEmpty $ApiKey) {
        if ($NonInteractive) {
            $base.status = 'needs_configuration'
            $base.message = 'ApiKey is required. Supply -ApiKey or run interactively.'
            $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
            return [pscustomobject]$base
        }
        Write-Host 'Please enter your DeepSeek API Key (leave empty to skip):'
        $ApiKey = Read-CyberButlerSecureSecret -Prompt 'DeepSeek API Key (input hidden):' -Reader $Reader
        if (Test-CyberButlerSecureStringEmpty $ApiKey) { $skipApiKey = $true; $ApiKey = $null }
    }
    if (Test-CyberButlerSecureStringEmpty $SmtpSecret) {
        if ($NonInteractive) {
            $base.status = 'needs_configuration'
            $base.message = 'SmtpSecret is required. Supply -SmtpSecret or run interactively.'
            $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
            return [pscustomobject]$base
        }
        Write-Host 'Please enter your 163 SMTP Auth Code (leave empty to skip):'
        $SmtpSecret = Read-CyberButlerSecureSecret -Prompt 'SMTP Auth Code (input hidden):' -Reader $Reader
        if (Test-CyberButlerSecureStringEmpty $SmtpSecret) { $skipSmtp = $true; $SmtpSecret = $null }
    }

    $paths = Get-CyberButlerSecretPaths -Root $Root
    $backups = @{}
    $newFiles = New-Object System.Collections.Generic.List[string]
    $createdAll = $true
    foreach ($key in @('api_key', 'owner_qq', 'smtp', 'overlay')) {
        $path = $paths.$key
        if (Test-Path -LiteralPath $path) {
            $createdAll = $false
            if ($null -ne $Journal) {
                $backups[$path] = Backup-CyberButlerFile -Journal $Journal -Step $JournalStep -Path $path -AllowedRoot $Root
            }
        } else {
            $newFiles.Add($path)
        }
    }
    if ($null -ne $Journal) {
        Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status in_progress | Out-Null
    }

    $keysToWrite = New-Object System.Collections.Generic.List[string]
    $keysToWrite.Add('owner_qq')
    $keysToWrite.Add('overlay')
    if (-not $skipApiKey) { $keysToWrite.Add('api_key') }
    if (-not $skipSmtp) { $keysToWrite.Add('smtp') }

    try {
        if (-not $OwnerQQ) { throw 'OwnerQQ is required.' }
        if (-not $skipApiKey) { Set-CyberButlerSecretFile -Path $paths.api_key -Value $ApiKey -Scope $Scope -Handlers $Handlers | Out-Null }
        if (-not $skipSmtp) { Set-CyberButlerSecretFile -Path $paths.smtp -Value $SmtpSecret -Scope $Scope -Handlers $Handlers | Out-Null }
        Set-CyberButlerSecretFile -Path $paths.owner_qq -Value (ConvertTo-SecureString -String $OwnerQQ -AsPlainText -Force) -Scope $Scope -Handlers $Handlers | Out-Null
        $overlay = [ordered]@{
            schema = 1
            values = [ordered]@{ YOUR_QQ_ID = $OwnerQQ }
        }
        Write-InstallerJson -Path $paths.overlay -Value $overlay
        $statusPath = Join-Path (Split-Path -Parent $paths.api_key) 'secrets-status.json'
        $status = [ordered]@{
            schema = 1
            api_key = if ($skipApiKey) { 'PARTIAL (skipped by user)' } else { 'ENABLED' }
            smtp = if ($skipSmtp) { 'PARTIAL (skipped by user)' } else { 'ENABLED' }
            updated_at = Get-InstallerUtcTimestamp
        }
        Write-InstallerJson -Path $statusPath -Value $status
        if ($null -ne $Journal) {
            foreach ($key in $keysToWrite) {
                $path = $paths.$key
                if (-not $backups.ContainsKey($path) -and (Test-Path -LiteralPath $path)) {
                    Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                        type = 'delete-created-file'
                        path = [IO.Path]::GetFullPath($path)
                        allowed_root = [IO.Path]::GetFullPath($Root)
                    })
                }
            }
            Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                type = 'delete-created-file'
                path = [IO.Path]::GetFullPath($statusPath)
                allowed_root = [IO.Path]::GetFullPath($Root)
            })
        }
        foreach ($key in $keysToWrite) {
            $aclBackup = Set-CyberButlerSecretAcl -Path $paths.$key -ReaderAccount $ReaderAccount -Journal $Journal -JournalStep $JournalStep -Handlers $Handlers
            if ($null -ne $Journal -and $aclBackup) {
                Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action ([pscustomobject]@{
                    type = 'restore-acl'
                    target = [IO.Path]::GetFullPath($paths.$key)
                    backup = [IO.Path]::GetFullPath($aclBackup)
                })
            }
        }
        if (-not $skipApiKey -and -not $skipSmtp) {
            $asserted = Assert-CyberButlerSecrets -Root $Root -ReaderAccount $ReaderAccount -Scope $Scope -Handlers $Handlers
            if (-not $asserted) { throw 'Secrets assertion failed.' }
        }
        $partial = New-Object System.Collections.Generic.List[string]
        if ($skipApiKey) { $partial.Add('ApiKey: PARTIAL (skipped by user)') }
        if ($skipSmtp) { $partial.Add('SmtpSecret: PARTIAL (skipped by user)') }
        $base.partial = ($partial.Count -gt 0)
        $base.skipped = $partial.ToArray()
        $base.message = if ($partial.Count -gt 0) { $partial -join '; ' } else { 'DPAPI secrets written.' }
        $base.status = if ($skipApiKey -and $skipSmtp) { 'skipped' } else { 'completed' }
        $base.changed = $true
        $base.exit_code = Get-InstallerExitCode -Name Success
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status $base.status -Details ([pscustomobject]@{ reason = $base.message; partial = [bool]$base.partial }) | Out-Null
        }
        return [pscustomobject]$base
    } catch {
        $undo = Undo-CyberButlerSecrets -Root $Root -Created $createdAll -Backups $backups -NewFiles $newFiles.ToArray() -Handlers $Handlers
        $base.status = 'failed'
        $base.message = $_.Exception.Message
        $base.undo = $undo
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ error = $_.Exception.Message; undo = $undo.action }) | Out-Null
        }
        return [pscustomobject]$base
    }
}
