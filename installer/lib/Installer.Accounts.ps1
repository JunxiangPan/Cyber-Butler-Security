# Local service-account lifecycle for the Cyber-Butler installer.
# Dot-source Installer.Common.ps1 and Installer.Journal.ps1 first.

function New-CyberButlerRandomPassword {
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!@#$%^&*'
    $bytes = New-Object byte[] 32
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $rng.GetBytes($bytes) } finally { $rng.Dispose() }
    $chars = New-Object char[] 32
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $chars[$i] = $alphabet[$bytes[$i] % $alphabet.Length]
    }
    return (-join $chars)
}

function Get-CyberButlerAccountLogonRights {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountName
    )

    $result = [ordered]@{
        readable = $false
        deny_interactive = $null
        batch_logon = $null
        error = $null
    }
    if (-not (Get-Command secedit.exe -ErrorAction SilentlyContinue)) {
        $result.error = 'secedit.exe is unavailable'
        return [pscustomobject]$result
    }

    $user = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    if (-not $user) {
        $result.error = 'account not found'
        return [pscustomobject]$result
    }
    $sid = [string]$user.SID.Value
    $tmp = Join-Path $env:TEMP ('cb-secedit-' + [guid]::NewGuid().ToString('N') + '.inf')
    try {
        & secedit.exe /export /cfg $tmp /areas SECURITYPOLICY 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp)) {
            throw 'secedit export failed'
        }
        $lines = Get-Content -LiteralPath $tmp -Encoding Unicode -ErrorAction Stop
        $denyLine = $lines | Where-Object { $_ -match '^SeDenyInteractiveLogonRight\s*=' } | Select-Object -First 1
        $batchLine = $lines | Where-Object { $_ -match '^SeBatchLogonRight\s*=' } | Select-Object -First 1
        $result.deny_interactive = [bool]($denyLine -and $denyLine -match [regex]::Escape($sid))
        $result.batch_logon = [bool]($batchLine -and $batchLine -match [regex]::Escape($sid))
        $result.readable = $true
    } catch {
        $result.error = $_.Exception.Message
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    return [pscustomobject]$result
}

function Set-CyberButlerLogonRight {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountName,
        [Parameter(Mandatory = $true)]
        [ValidateSet('SeDenyInteractiveLogonRight', 'SeBatchLogonRight', 'SeServiceLogonRight')]
        [string]$Right,
        [switch]$Remove
    )

    $user = Get-LocalUser -Name $AccountName -ErrorAction Stop
    $sid = [string]$user.SID.Value
    $tmp = Join-Path $env:TEMP ('cb-secedit-' + [guid]::NewGuid().ToString('N') + '.inf')
    try {
        & secedit.exe /export /cfg $tmp /areas SECURITYPOLICY 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $tmp)) { throw 'secedit export failed' }
        $lines = New-Object System.Collections.Generic.List[string]
        foreach ($line in Get-Content -LiteralPath $tmp -Encoding Unicode) { $lines.Add($line) }
        $matched = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch ('^' + [regex]::Escape($Right) + '\s*=')) { continue }
            $matched = $true
            $values = @(($lines[$i] -split '=', 2)[1] -split ',')
            $values = @($values | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            $sidToken = '*' + $sid
            if ($Remove) {
                $values = @($values | Where-Object { $_.TrimStart('*') -ne $sid })
            } elseif (@($values | ForEach-Object { $_.TrimStart('*') }) -notcontains $sid) {
                $values += $sidToken
            }
            $lines[$i] = $Right + ' = ' + ($values -join ',')
        }
        if (-not $matched -and -not $Remove) {
            $lines.Add($Right + ' = *' + $sid)
        }
        [IO.File]::WriteAllLines($tmp, $lines, (New-Object Text.UnicodeEncoding($false, $true)))
        $securityDbDir = Join-Path $env:SystemRoot 'security\database'
        Push-Location -LiteralPath $securityDbDir
        try {
            $configureOutput = & secedit.exe /configure /db 'secedit.sdb' /cfg $tmp /areas SECURITYPOLICY 2>&1
        } finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0) { throw ('secedit configure failed: ' + (($configureOutput | ForEach-Object { [string]$_ }) -join ' ')) }
        $verified = Get-CyberButlerAccountLogonRights -AccountName $AccountName
        if ($Remove) {
            $stillPresent = if ($Right -eq 'SeDenyInteractiveLogonRight') { $verified.deny_interactive } elseif ($Right -eq 'SeBatchLogonRight') { $verified.batch_logon } else { $false }
            if ($stillPresent) { throw ('secedit did not remove ' + $Right) }
        } else {
            $present = if ($Right -eq 'SeDenyInteractiveLogonRight') { $verified.deny_interactive } elseif ($Right -eq 'SeBatchLogonRight') { $verified.batch_logon } else { $true }
            if (-not $present) { throw ('secedit did not apply ' + $Right) }
        }
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Test-CyberButlerAccount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountName,
        $Handlers = @{}
    )

    $context = [pscustomobject]@{ AccountName = $AccountName }
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'accounts.test') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'accounts.test' -Context $context)
    }

    $isAdmin = Test-InstallerAdministrator
    $supported = $null -ne (Get-Command Get-LocalUser -ErrorAction SilentlyContinue) -and
        $null -ne (Get-Command New-LocalUser -ErrorAction SilentlyContinue)
    $result = [ordered]@{
        account_name = $AccountName
        supported = [bool]$supported
        can_manage = [bool]$isAdmin
        exists = $false
        enabled = $null
        in_users_group = $null
        in_administrators_group = $null
        deny_interactive = $null
        batch_logon = $null
        satisfied = $false
        reason = ''
    }

    if (-not $supported) {
        $result.reason = 'local-user-management-unavailable'
        return [pscustomobject]$result
    }

    $user = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
    if (-not $user) {
        $result.reason = 'account-missing'
        return [pscustomobject]$result
    }

    $result.exists = $true
    $result.enabled = [bool]$user.Enabled
    try {
        $usersGroup = Get-LocalGroup -SID 'S-1-5-32-545' -ErrorAction Stop
        $adminsGroup = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
        $usersMembers = @(Get-LocalGroupMember -Group $usersGroup.Name -ErrorAction SilentlyContinue)
        $adminsMembers = @(Get-LocalGroupMember -Group $adminsGroup.Name -ErrorAction SilentlyContinue)
        $accountSid = [string]$user.SID.Value
        $matchesAccount = {
            param($member)
            $memberSid = [string]$member.SID.Value
            if ($accountSid -and $memberSid) { return $memberSid -eq $accountSid }
            $memberName = [string]$member.Name
            $slash = $memberName.LastIndexOf([char]92)
            if ($slash -ge 0) { $memberName = $memberName.Substring($slash + 1) }
            return $memberName -eq $AccountName
        }
        $result.in_users_group = [bool](@($usersMembers | Where-Object { & $matchesAccount $_ }).Count -gt 0)
        $result.in_administrators_group = [bool](@($adminsMembers | Where-Object { & $matchesAccount $_ }).Count -gt 0)
    } catch {
        $result.reason = 'group-membership-unreadable'
    }

    $rights = Get-CyberButlerAccountLogonRights -AccountName $AccountName
    $result.deny_interactive = $rights.deny_interactive
    $result.batch_logon = $rights.batch_logon
    $result.satisfied = $result.enabled -and $result.in_users_group -and
        (-not $result.in_administrators_group) -and $result.deny_interactive -and $result.batch_logon
    if (-not $result.satisfied -and -not $result.reason) { $result.reason = 'account-not-compliant' }
    return [pscustomobject]$result
}

function Assert-CyberButlerAccount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountName,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'accounts.assert') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'accounts.assert' -Context ([pscustomobject]@{ AccountName = $AccountName }))
    }
    $test = Test-CyberButlerAccount -AccountName $AccountName -Handlers $Handlers
    return [bool]$test.satisfied
}

function New-CyberButlerLocalAccount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountName,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'accounts.create') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'accounts.create' -Context ([pscustomobject]@{ AccountName = $AccountName }))
    }

    $passwordText = New-CyberButlerRandomPassword
    $password = ConvertTo-SecureString -String $passwordText -AsPlainText -Force
    try {
        $user = New-LocalUser -Name $AccountName -Password $password -AccountNeverExpires -PasswordNeverExpires -UserMayNotChangePassword -ErrorAction Stop
        $usersGroupName = (Get-LocalGroup -SID 'S-1-5-32-545' -ErrorAction Stop).Name
        try {
            Add-LocalGroupMember -Group $usersGroupName -Member $AccountName -ErrorAction Stop
        } catch {
            $alreadyMember = $false
            try {
                $members = @(Get-LocalGroupMember -Group $usersGroupName -ErrorAction SilentlyContinue)
                $alreadyMember = [bool](@($members | Where-Object { [string]$_.SID.Value -eq [string]$user.SID.Value }).Count -gt 0)
            } catch { }
            if (-not $alreadyMember) { throw ('Add-LocalGroupMember failed: ' + $_.Exception.Message) }
        }
        $rightErrors = @()
        foreach ($right in @('SeDenyInteractiveLogonRight', 'SeBatchLogonRight', 'SeServiceLogonRight')) {
            try { Set-CyberButlerLogonRight -AccountName $AccountName -Right $right -ErrorAction Stop }
            catch { $rightErrors += ($right + ': ' + $_.Exception.Message) }
        }
        if ($rightErrors.Count -gt 0) { throw ('Logon right configuration failed: ' + ($rightErrors -join '; ')) }
        return [pscustomobject]@{ created = $true; account_name = $AccountName; sid = [string]$user.SID.Value }
    } catch {
        throw "New-LocalUser failed: $($_.Exception.Message)"
    }
}

function Undo-CyberButlerAccount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$AccountName,
        [bool]$Created = $false,
        $Handlers = @{}
    )

    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'accounts.undo') {
        return (Invoke-CyberButlerHandler -Handlers $Handlers -Name 'accounts.undo' -Context ([pscustomobject]@{ AccountName = $AccountName; Created = $Created }))
    }
    if (-not $Created) { return [pscustomobject]@{ action = 'none'; account_name = $AccountName; reason = 'account-existed-before-run' } }

    try {
        $user = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
        if ($user) { Remove-LocalUser -Name $AccountName -ErrorAction Stop }
        return [pscustomobject]@{ action = 'removed'; account_name = $AccountName }
    } catch {
        try {
            Disable-LocalUser -Name $AccountName -ErrorAction Stop
            return [pscustomobject]@{ action = 'disabled'; account_name = $AccountName; reason = $_.Exception.Message }
        } catch {
            return [pscustomobject]@{ action = 'failed'; account_name = $AccountName; reason = $_.Exception.Message }
        }
    }
}

function Invoke-CyberButlerAccountSetup {
    [CmdletBinding()]
    param(
        [string]$AccountName = 'CyberButlerSvc',
        [string]$JournalStep = 'account',
        $Journal = $null,
        [string]$Approval = '',
        [switch]$NonInteractive,
        [switch]$PlanOnly,
        $Handlers = @{}
    )

    $test = Test-CyberButlerAccount -AccountName $AccountName -Handlers $Handlers
    $base = [ordered]@{
        module = 'accounts'
        step = $JournalStep
        account_name = $AccountName
        test = $test
        changed = $false
    }

    if ($test.satisfied) {
        $base.status = 'skipped'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if (-not $test.supported) {
        $base.status = 'unsupported'
        $base.message = 'Local user management is unavailable; account isolation must be completed manually.'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if (-not $test.can_manage) {
        $base.status = 'needs_elevation'
        $base.message = 'Account creation requires administrator rights.'
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        return [pscustomobject]$base
    }

    $approvalState = Get-CyberButlerApprovalState -Required 'APPROVE ACCOUNT' -Approval $Approval -NonInteractive:$NonInteractive -PlanOnly:$PlanOnly
    if ($approvalState -eq 'plan') {
        $base.status = 'plan'
        $base.message = 'Would create or verify the service account.'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    }
    if ($approvalState -ne 'approved') {
        $base.status = 'needs_approval'
        $base.exit_code = Get-InstallerExitCode -Name NeedsApproval
        return [pscustomobject]$base
    }

    if ($test.exists) {
        $base.status = 'existing_noncompliant'
        $base.message = 'An existing account is present but not compliant; it is not modified or deleted by this step.'
        $base.exit_code = Get-InstallerExitCode -Name ValidationFailed
        return [pscustomobject]$base
    }

    if ($null -ne $Journal) {
        Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status in_progress | Out-Null
    }

    $created = $false
    try {
        $creation = New-CyberButlerLocalAccount -AccountName $AccountName -Handlers $Handlers
        $created = [bool]$creation.created
        $base.changed = $created
        if ($created) {
            $action = [pscustomobject][ordered]@{
                type = 'delete-created-account'
                account_name = $AccountName
            }
            if ($null -ne $Journal) {
                Add-CyberButlerReverseAction -Journal $Journal -Step $JournalStep -Action $action
            }
        }

        $asserted = Assert-CyberButlerAccount -AccountName $AccountName -Handlers $Handlers
        if (-not $asserted) { throw 'account assertion failed' }

        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status completed | Out-Null
        }
        $base.status = 'completed'
        $base.exit_code = Get-InstallerExitCode -Name Success
        return [pscustomobject]$base
    } catch {
        $after = $null
        try { $after = Test-CyberButlerAccount -AccountName $AccountName -Handlers $Handlers } catch { }
        $undo = Undo-CyberButlerAccount -AccountName $AccountName -Created $created -Handlers $Handlers
        $base.status = 'failed'
        $base.message = $_.Exception.Message
        if ($after -and $_.Exception.Message -like '*assertion failed*') {
            $base.message = ('account assertion failed: enabled={0}; users_group={1}; administrators_group={2}; deny_interactive={3}; batch_logon={4}; reason={5}' -f $after.enabled, $after.in_users_group, $after.in_administrators_group, $after.deny_interactive, $after.batch_logon, $after.reason)
        }
        $base.test = $after
        $base.undo = $undo
        $base.exit_code = if ($undo.action -eq 'failed') { Get-InstallerExitCode -Name RollbackFailed } else { Get-InstallerExitCode -Name ValidationFailed }
        if ($null -ne $Journal) {
            Add-CyberButlerJournalStep -Journal $Journal -Name $JournalStep -Status failed -Details ([pscustomobject]@{ error = $_.Exception.Message; undo = $undo.action }) | Out-Null
        }
        return [pscustomobject]$base
    }
}
