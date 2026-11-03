# Read-only defense diagnostics for the Cyber-Butler installer.
# Dot-source Installer.Common.ps1 and Installer.Tier.ps1 first.

function New-CyberButlerDiagnosticItem {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Id,
        [Parameter(Mandatory = $true)]
        [string]$Label,
        [Parameter(Mandatory = $true)]
        [ValidateSet('ENABLED', 'PARTIAL', 'MANUAL', 'FAILED')]
        [string]$Status,
        [string]$Reason = ''
    )
    return [pscustomobject][ordered]@{
        id = $Id
        label = $Label
        status = $Status
        reason = $Reason
    }
}

function Get-CyberButlerDiagnosticDefaults {
    return @(
        @{ id = 'isolation'; label = '双账户隔离' },
        @{ id = 'totp'; label = 'TOTP 审批' },
        @{ id = 'router'; label = 'Router fail-closed' },
        @{ id = 'webui'; label = 'Web UI 绑定' },
        @{ id = 'api_key'; label = 'API Key 保护' },
        @{ id = 'totp_vault'; label = 'TOTP 保险箱隔离' },
        @{ id = 'audit'; label = '审计' },
        @{ id = 'firewall'; label = '防火墙' }
    )
}

function Get-CyberButlerDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Tier,
        [Parameter(Mandatory = $true)]
        [string]$EffectiveTier,
        [bool]$Isolation = $false,
        [string]$Root = 'C:\CyberButler',
        [string]$ServiceAccount = 'CyberButlerSvc',
        [string]$TotpReaderAccount = 'BUILTIN\Administrators',
        [string]$ExternalAgentAccount = '',
        [ValidateSet('Loopback', 'Tailscale', 'LAN')]
        [string]$WebUIBind = 'Loopback',
        $Handlers = @{}
    )

    $items = New-Object System.Collections.Generic.List[object]
    if (Test-CyberButlerHandler -Handlers $Handlers -Name 'diagnostics.run') {
        $result = Invoke-CyberButlerHandler -Handlers $Handlers -Name 'diagnostics.run' -Context ([pscustomobject]@{
            Tier = $Tier; EffectiveTier = $EffectiveTier; Isolation = $Isolation
            Root = $Root; ServiceAccount = $ServiceAccount; TotpReaderAccount = $TotpReaderAccount; ExternalAgentAccount = $ExternalAgentAccount; WebUIBind = $WebUIBind
        })
        foreach ($item in @($result.items)) {
            $items.Add((New-CyberButlerDiagnosticItem -Id ([string]$item.id) -Label ([string]$item.label) -Status ([string]$item.status) -Reason ([string]$item.reason)))
        }
    } else {
        $rootFull = [IO.Path]::GetFullPath($Root)

        $isolationStatus = if (-not $Isolation) { 'MANUAL' } else {
            $user = Get-LocalUser -Name $ServiceAccount -ErrorAction SilentlyContinue
            if ($user) { 'ENABLED' } else { 'FAILED' }
        }
        $isolationReason = if (-not $Isolation) { '单账户模式；需要强隔离请使用 High 或 -EnableIsolation:$true' } elseif ($isolationStatus -eq 'ENABLED') { "服务账户存在: $ServiceAccount" } else { "服务账户不存在: $ServiceAccount" }
        $items.Add((New-CyberButlerDiagnosticItem -Id 'isolation' -Label '双账户隔离' -Status $isolationStatus -Reason $isolationReason))

        $vault = Join-Path $rootFull 'tools\totp-vault'
        $totpStatus = if (Test-Path -LiteralPath (Join-Path $vault 'totp_secret.dpapi')) {
            if (Get-Command Get-Acl -ErrorAction SilentlyContinue) { 'ENABLED' } else { 'PARTIAL' }
        } else { 'MANUAL' }
        $items.Add((New-CyberButlerDiagnosticItem -Id 'totp' -Label 'TOTP 审批' -Status $totpStatus -Reason $(if ($totpStatus -eq 'ENABLED') { 'TOTP secret 存在' } elseif ($totpStatus -eq 'PARTIAL') { 'secret 存在但 ACL 无法验证' } else { '未找到 TOTP secret' })))

        $routerConfig = Join-Path $rootFull 'ExternalAgent\data\router\settings.json'
        $routerStatus = 'MANUAL'
        $routerReason = 'Router settings not found'
        if (Test-Path -LiteralPath $routerConfig) {
            try {
                $router = Get-Content -LiteralPath $routerConfig -Raw -Encoding UTF8 | ConvertFrom-Json
                if ($null -ne $router.legacy_provider_patch -and $router.legacy_provider_patch -eq $false) {
                    $routerStatus = 'ENABLED'; $routerReason = 'legacy_provider_patch=false'
                } else {
                    $routerStatus = 'PARTIAL'; $routerReason = 'legacy provider patch is still enabled'
                }
            } catch { $routerStatus = 'FAILED'; $routerReason = 'Router settings unreadable' }
        }
        $items.Add((New-CyberButlerDiagnosticItem -Id 'router' -Label 'Router fail-closed' -Status $routerStatus -Reason $routerReason))

        $listener = $null
        if (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue) {
            try { $listener = @(Get-NetTCPConnection -State Listen -LocalPort 8765 -ErrorAction SilentlyContinue) | Select-Object -First 1 } catch { }
        }
        if ($null -eq $listener) {
            $webStatus = 'MANUAL'; $webReason = '8765 is not listening'
        } elseif ([string]$listener.LocalAddress -in @('0.0.0.0', '::')) {
            $webStatus = 'PARTIAL'; $webReason = '8765 is listening on all interfaces'
        } else {
            $webStatus = 'ENABLED'; $webReason = "8765 is bound to $($listener.LocalAddress)"
        }
        $items.Add((New-CyberButlerDiagnosticItem -Id 'webui' -Label 'Web UI 绑定' -Status $webStatus -Reason $webReason))

        $apiKey = Join-Path $rootFull 'tools\deepseek.key.dpapi'
        $apiStatus = if (Test-Path -LiteralPath $apiKey) { 'ENABLED' } else { 'MANUAL' }
        $apiReason = if ($apiStatus -eq 'ENABLED') { 'DPAPI secret file exists' } else { 'DPAPI secret file missing' }
        $secretsStatusPath = Join-Path $rootFull 'tools\secrets-status.json'
        if (Test-Path -LiteralPath $secretsStatusPath) {
            try {
                $secretsStatus = Get-Content -LiteralPath $secretsStatusPath -Raw -Encoding UTF8 | ConvertFrom-Json
                if ([string]$secretsStatus.api_key -match '^PARTIAL') {
                    $apiStatus = 'PARTIAL'
                    $apiReason = 'ApiKey: PARTIAL (skipped by user)'
                }
            } catch { }
        }
        $items.Add((New-CyberButlerDiagnosticItem -Id 'api_key' -Label 'API Key 保护' -Status $apiStatus -Reason $apiReason))

        $vaultAclStatus = 'MANUAL'
        $vaultAclReason = 'TOTP vault missing'
        if (Test-Path -LiteralPath $vault) {
            if (Get-Command Test-CyberButlerTotpVaultAcl -ErrorAction SilentlyContinue) {
                $aclCheck = Test-CyberButlerTotpVaultAcl -VaultPath $vault -ReaderAccount $TotpReaderAccount -ExternalAgentAccount $ExternalAgentAccount -RequireExternalAgentDeny:$Isolation
                if ($aclCheck.satisfied) { $vaultAclStatus = 'ENABLED'; $vaultAclReason = 'vault ACL is restricted' }
                else { $vaultAclStatus = 'PARTIAL'; $vaultAclReason = $aclCheck.reason }
            } else { $vaultAclStatus = 'PARTIAL'; $vaultAclReason = 'vault exists but ACL checker is unavailable' }
        }
        $items.Add((New-CyberButlerDiagnosticItem -Id 'totp_vault' -Label 'TOTP 保险箱隔离' -Status $vaultAclStatus -Reason $vaultAclReason))

        $auditPaths = @(
            (Join-Path $rootFull 'audit\ops.jsonl'),
            (Join-Path $env:ProgramData 'CyberButler\audit\ops.jsonl')
        )
        $auditPath = $auditPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        $auditStatus = if ($auditPath) { 'ENABLED' } else { 'MANUAL' }
        $items.Add((New-CyberButlerDiagnosticItem -Id 'audit' -Label '审计' -Status $auditStatus -Reason $(if ($auditPath) { "audit log: $auditPath" } else { 'audit log missing' })))

        $fwStatus = 'MANUAL'; $fwReason = 'firewall cmdlet unavailable'
        if (Get-Command Get-NetFirewallRule -ErrorAction SilentlyContinue) {
            try {
                $fw = @(Get-NetFirewallRule -ErrorAction Stop | Where-Object { [string]$_.DisplayName -match 'Cyber-Butler|ExternalAgent' })
                if ($fw.Count -gt 0) { $fwStatus = 'ENABLED'; $fwReason = "$($fw.Count) Cyber-Butler/ExternalAgent firewall rules found" }
                else { $fwStatus = 'MANUAL'; $fwReason = 'no Cyber-Butler/ExternalAgent firewall rules found' }
            } catch { $fwStatus = 'FAILED'; $fwReason = 'firewall rules unreadable' }
        }
        $items.Add((New-CyberButlerDiagnosticItem -Id 'firewall' -Label '防火墙' -Status $fwStatus -Reason $fwReason))
    }

    $defaults = Get-CyberButlerDiagnosticDefaults
    $byId = @{}
    foreach ($item in $items) { $byId[[string]$item.id] = $item }
    $complete = New-Object System.Collections.Generic.List[object]
    foreach ($default in $defaults) {
        if ($byId.ContainsKey($default.id)) { $complete.Add($byId[$default.id]) }
        else { $complete.Add((New-CyberButlerDiagnosticItem -Id $default.id -Label $default.label -Status 'MANUAL' -Reason 'diagnostic did not run')) }
    }

    $summary = [ordered]@{ enabled = 0; partial = 0; manual = 0; failed = 0 }
    foreach ($item in $complete) {
        switch ([string]$item.status) {
            'ENABLED' { $summary.enabled++ }
            'PARTIAL' { $summary.partial++ }
            'MANUAL' { $summary.manual++ }
            'FAILED' { $summary.failed++ }
        }
    }

    return [pscustomobject][ordered]@{
        schema = 1
        tier = $Tier
        effective_tier = $EffectiveTier
        isolation = [bool]$Isolation
        read_only = $true
        generated_at = Get-InstallerUtcTimestamp
        items = $complete.ToArray()
        summary = [pscustomobject]$summary
    }
}

function Format-CyberButlerDefenseList {
    param(
        [Parameter(Mandatory = $true)]
        $Diagnostics
    )
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Diagnostics.items)) {
        $lines.Add(('{0}: {1} ({2})' -f $item.label, $item.status, $item.reason))
    }
    return ($lines -join [Environment]::NewLine)
}
