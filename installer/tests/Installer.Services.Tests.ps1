$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Services.ps1')

Describe 'Installer services safety' {
    It 'uses the current user for Medium and the service account for High' {
        $desktop = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        $service = 'CyberButlerSvc'
        $mediumSpecs = @(Get-CyberButlerServiceSpecs -Root 'C:\CyberButler' -ServiceAccount $service -DesktopAccount $desktop -Isolation $false)
        ($mediumSpecs | Where-Object { $_.name -eq 'Cyber-Butler Broker' }).principal | Should Be 'SYSTEM'
        $highSpecs = @(Get-CyberButlerServiceSpecs -Root 'C:\CyberButler' -ServiceAccount $service -DesktopAccount $desktop -Isolation $true)
        ($highSpecs | Where-Object { $_.name -eq 'Cyber-Butler Web UI Services' }).principal | Should Be 'desktop'

        $mediumPrincipal = Get-CyberButlerTaskPrincipalSpec -PrincipalMode 'desktop' -DesktopAccount $desktop
        $mediumPrincipal.user_id | Should Be $desktop
        $mediumPrincipal.logon_type | Should Be 'Interactive'
        ($highSpecs | Where-Object { $_.name -eq 'Cyber-Butler Broker' }).kind | Should Be 'task'
        { Get-CyberButlerTaskPrincipalSpec -PrincipalMode 'service' -ServiceAccount $service } | Should Throw
    }

    It 'skips when all tasks and ports are already healthy' {
        $base = Join-Path $env:TEMP ('cb-services-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbServiceCalls = @{ apply = 0; undo = 0 }
            $handlers = @{
                'services.test' = { param($c) [pscustomobject]@{ satisfied = $true; supported = $true; can_manage = $true } }
                'services.apply' = { param($c) $global:cbServiceCalls.apply++; [pscustomobject]@{ created = @(); started_process_ids = @() } }
                'services.undo' = { param($c) $global:cbServiceCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerServices -Root $base -Approval 'APPROVE SERVICES' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'skipped'
            $global:cbServiceCalls.apply | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'registers tasks and records a process stop action' {
        $base = Join-Path $env:TEMP ('cb-services-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbServiceCalls = @{ apply = 0; undo = 0 }
            $handlers = @{
                'services.test' = { param($c) [pscustomobject]@{ satisfied = $false; supported = $true; can_manage = $true } }
                'services.apply' = { param($c) $global:cbServiceCalls.apply++; [pscustomobject]@{ created = @('AgentRuntime Service'); started_process_ids = @(4242) } }
                'services.assert' = { param($c) $true }
                'services.undo' = { param($c) $global:cbServiceCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerServices -Root $base -Approval 'APPROVE SERVICES' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'completed'
            $result.changed | Should Be $true
            $global:cbServiceCalls.apply | Should Be 1
            $step = Get-CyberButlerJournalStep -Journal $journal -Name 'services'
            $step.status | Should Be 'completed'
            $types = @($step.reverse_actions | ForEach-Object { $_.type })
            ($types -contains 'stop-created-process') | Should Be $true
            $step.reverse_actions[0].process_id | Should Be 4242
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'runs Undo when Assert fails' {
        $base = Join-Path $env:TEMP ('cb-services-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $base -Tier Medium
            $global:cbServiceCalls = @{ apply = 0; undo = 0 }
            $handlers = @{
                'services.test' = { param($c) [pscustomobject]@{ satisfied = $false; supported = $true; can_manage = $true } }
                'services.apply' = { param($c) $global:cbServiceCalls.apply++; [pscustomobject]@{ created = @('AgentRuntime Service'); started_process_ids = @() } }
                'services.assert' = { param($c) $false }
                'services.undo' = { param($c) $global:cbServiceCalls.undo++; [pscustomobject]@{ action = 'removed' } }
            }
            $result = Invoke-CyberButlerServices -Root $base -Approval 'APPROVE SERVICES' -Journal $journal -Handlers $handlers
            $result.status | Should Be 'failed'
            $result.undo.action | Should Be 'removed'
            $global:cbServiceCalls.undo | Should Be 1
            (Get-CyberButlerJournalStep -Journal $journal -Name 'services').status | Should Be 'failed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'returns NeedsApproval without executing under NonInteractive' {
        $base = Join-Path $env:TEMP ('cb-services-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbServiceCalls = @{ apply = 0 }
            $handlers = @{
                'services.test' = { param($c) [pscustomobject]@{ satisfied = $false; supported = $true; can_manage = $true } }
                'services.apply' = { param($c) $global:cbServiceCalls.apply++; [pscustomobject]@{ created = @(); started_process_ids = @() } }
            }
            $result = Invoke-CyberButlerServices -Root $base -NonInteractive -Handlers $handlers
            $result.status | Should Be 'needs_approval'
            $result.exit_code | Should Be 10
            $global:cbServiceCalls.apply | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'plans without applying under PlanOnly' {
        $base = Join-Path $env:TEMP ('cb-services-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $global:cbServiceCalls = @{ apply = 0 }
            $handlers = @{
                'services.test' = { param($c) [pscustomobject]@{ satisfied = $false; supported = $true; can_manage = $true } }
                'services.apply' = { param($c) $global:cbServiceCalls.apply++; [pscustomobject]@{ created = @(); started_process_ids = @() } }
            }
            $result = Invoke-CyberButlerServices -Root $base -PlanOnly -Handlers $handlers
            $result.status | Should Be 'plan'
            $global:cbServiceCalls.apply | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'fails safe when scheduled-task cmdlets are unavailable' {
        $base = Join-Path $env:TEMP ('cb-services-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $handlers = @{
                'services.test' = { param($c) [pscustomobject]@{ satisfied = $false; supported = $false; can_manage = $true } }
            }
            $result = Invoke-CyberButlerServices -Root $base -Approval 'APPROVE SERVICES' -Handlers $handlers
            $result.status | Should Be 'unsupported'
            $result.exit_code | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'formats service assertion details with task and port names' {
        $assertion = [pscustomobject]@{
            satisfied = $false
            tasks = @(
                [pscustomobject]@{ name = 'AgentRuntime TOTP Broker'; exists = $true; principal_ok = $true; state = 'Ready'; last_task_result = '0x00000000'; port = 18090 }
            )
            ports = @(
                [pscustomobject]@{ port = 18090; listening = $false; healthy = $false; owner_pid = $null }
            )
        }
        $text = Format-CyberButlerServiceAssertion -Assertion $assertion
        $text | Should Match 'Service assertion failed'
        $text | Should Match 'AgentRuntime TOTP Broker'
        $text | Should Match '18090 not listening'
        $text | Should Match 'task exited immediately'
    }

    It 'saves a service diagnostics snapshot' {
        $base = Join-Path $env:TEMP ('cb-services-diag-' + [guid]::NewGuid().ToString('N'))
        $logDir = Join-Path (Join-Path (Join-Path $base 'AgentRuntime') 'data') 'logs'
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $logDir 'agentruntime.log') -Value 'line' -Encoding UTF8
        try {
            $dir = Save-CyberButlerServicesDiagnostics -Root $base -SnapshotRoot (Join-Path $base 'diag') -Assertion ([pscustomobject]@{ satisfied = $false; tasks = @(); ports = @() })
            (Test-Path -LiteralPath $dir) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $dir 'assertion.json')) | Should Be $true
            (Get-Content -LiteralPath (Join-Path $dir 'assertion.json') -Raw) | Should Match 'satisfied'
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'stops listeners owned by the install root by port' {
        if ($env:CI) { return }
        $base = Join-Path $env:TEMP ('cb-services-ports-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $base 'AgentRuntime') -Force | Out-Null
        $python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
        if (-not $python) { return }
        $script = Join-Path (Join-Path $base 'AgentRuntime') 'fake-listener.py'
        Set-Content -LiteralPath $script -Value 'import socket,sys,time; s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(("127.0.0.1",int(sys.argv[1]))); s.listen(1); time.sleep(30)' -Encoding ASCII
        $ports = @(46233, 46234, 46235, 46236)
        $procs = @()
        try {
            foreach ($port in $ports) {
                $procs += Start-Process -FilePath $python -ArgumentList @($script, [string]$port) -WindowStyle Hidden -PassThru
            }
            $deadline = (Get-Date).AddSeconds(10)
            do {
                $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $ports -contains [int]$_.LocalPort })
                if ($listeners.Count -ge $ports.Count) { break }
                Start-Sleep -Milliseconds 200
            } while ((Get-Date) -lt $deadline)
            $stopped = @(Stop-CyberButlerInstallProcesses -Root $base -Ports $ports)
            $stopped.Count | Should BeGreaterThan 0
            $remaining = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $ports -contains [int]$_.LocalPort })
            $remaining.Count | Should Be 0
        } finally {
            foreach ($proc in $procs) {
                if (-not $proc.HasExited) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
            }
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'restores through the Undo handler' {
        $handlers = @{ 'services.undo' = { param($c) [pscustomobject]@{ action = 'removed' } } }
        $result = Undo-CyberButlerServices -Root 'C:\fake' -CreatedTasks @('Fake Task') -StartedProcessIds @(1) -Handlers $handlers
        $result.action | Should Be 'removed'
    }
}
