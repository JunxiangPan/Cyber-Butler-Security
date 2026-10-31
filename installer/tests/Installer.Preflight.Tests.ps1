$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Tier.ps1')
. (Join-Path $installerRoot 'lib\Installer.Preflight.ps1')

Describe 'Installer preflight' {
    It 'returns the documented read-only shape' {
        $target = Join-Path $env:TEMP ('cb-preflight-clean-' + [guid]::NewGuid().ToString('N'))
        $json = $target + '.json'
        try {
            $p = Get-CyberButlerPreflight -InstallPath $target -OutputPath $json
            $p.schema | Should Be 1
            $p.read_only | Should Be $true
            $p.ports.Count | Should Be 5
            $p.install_path.has_existing_install | Should Be $false
            $p.install_path.existing_state | Should Be 'None'
            (Test-Path -LiteralPath $target) | Should Be $false
            (Test-Path -LiteralPath $json) | Should Be $true
            $disk = Get-Content -LiteralPath $json -Raw -Encoding UTF8 | ConvertFrom-Json
            $disk.read_only | Should Be $true
            $disk.host.os_caption | Should Not BeNullOrEmpty
            $disk.powershell.version | Should Not BeNullOrEmpty
            $disk.admin.identity | Should Not BeNullOrEmpty
            $disk.scheduled_tasks | Should Not BeNullOrEmpty
            $disk.defender | Should Not BeNullOrEmpty
            $disk.long_paths | Should Not BeNullOrEmpty
        } finally {
            if (Test-Path -LiteralPath $json) { Remove-Item -LiteralPath $json -Force }
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }

    It 'classifies None, Legacy and Installed with one shared function' {
        $target = Join-Path $env:TEMP ('cb-preflight-state-' + [guid]::NewGuid().ToString('N'))
        try {
            (Get-CyberButlerExistingState -InstallPath $target) | Should Be 'None'
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'VERSION') -Value '1.6.0' -Encoding ASCII
            (Get-CyberButlerExistingState -InstallPath $target) | Should Be 'Legacy'
            $jsonPath = Join-Path $target 'state.json'
            $p = Get-CyberButlerPreflight -InstallPath $target -OutputPath $jsonPath
            $p.install_path.existing_state | Should Be 'Legacy'
            $p.install_path.has_existing_install | Should Be $true
            Write-CyberButlerInstallStateMarker -InstallPath $target -Version '1.6.0' -Tier Medium -Isolation $false | Out-Null
            (Get-CyberButlerExistingState -InstallPath $target) | Should Be 'Installed'
        } finally {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }

    It 'detects an existing installation without changing it' {
        $target = Join-Path $env:TEMP ('cb-preflight-existing-' + [guid]::NewGuid().ToString('N'))
        $json = $target + '.json'
        try {
            New-Item -ItemType Directory -Path (Join-Path $target 'AstrBot') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'VERSION') -Value '1.6.0' -Encoding ASCII
            $p = Get-CyberButlerPreflight -InstallPath $target -OutputPath $json
            $p.install_path.existing_state | Should Be 'Legacy'
            $p.install_path.has_existing_install | Should Be $true
            $p.install_path.version | Should Be '1.6.0'
            (Test-Path -LiteralPath (Join-Path $target 'AstrBot')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $target 'local-overlay.json')) | Should Be $false
        } finally {
            if (Test-Path -LiteralPath $json) { Remove-Item -LiteralPath $json -Force }
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }

    It 'skips a WindowsApps placeholder and selects the real Python' {
        $target = Join-Path $env:TEMP ('cb-preflight-python-order-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $target 'WindowsApps') -Force | Out-Null
        try {
            $placeholder = Join-Path $target 'WindowsApps\python.cmd'
            Set-Content -LiteralPath $placeholder -Value '@echo Python was not found& exit /b 9009' -Encoding ASCII
            $real = (Get-Command python.exe -ErrorAction Stop).Source
            $p = Get-CyberButlerPreflight -InstallPath $target -PythonCandidates @($placeholder, $real)
            $p.python_usable | Should Be $true
            @($p.python).Count | Should Be 1
            $p.python[0].candidate_path | Should Be $real
            $p.python[0].path | Should Be $real
            $p.python[0].version_ok | Should Be $true
            @($p.blocking).Count | Should Be 0
        } finally {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }

    It 'marks Python 3.15 as bundled-required without blocking' {
        $target = Join-Path $env:TEMP ('cb-preflight-python315-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        try {
            $fake = Join-Path $target 'python315.cmd'
            $body = '@echo off' + "`r`n" +
                'if "%~1"=="-c" (' + "`r`n" +
                '  echo %~f0' + "`r`n" +
                '  exit /b 0' + "`r`n" +
                ')' + "`r`n" +
                'if "%~1"=="--version" (' + "`r`n" +
                '  echo Python 3.15.2' + "`r`n" +
                '  exit /b 0' + "`r`n" +
                ')' + "`r`n" +
                'exit /b 1'
            Set-Content -LiteralPath $fake -Value $body -Encoding ASCII
            $p = Get-CyberButlerPreflight -InstallPath $target -PythonCandidates @($fake)
            $p.python_usable | Should Be $false
            $p.python_needs_bundle | Should Be $true
            $p.python_source | Should Be 'bundled'
            @($p.blocking).Count | Should Be 0
        } finally {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }

    It 'marks missing Python as bundled-required without blocking' {
        $target = Join-Path $env:TEMP ('cb-preflight-python-' + [guid]::NewGuid().ToString('N'))
        try {
            $handlers = @{ 'preflight.python' = { param($c) @() } }
            $p = Get-CyberButlerPreflight -InstallPath $target -Handlers $handlers
            $p.python_usable | Should Be $false
            $p.python_needs_bundle | Should Be $true
            @($p.blocking).Count | Should Be 0
        } finally {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }

    It 'reports one entry for every required port' {
        $target = Join-Path $env:TEMP ('cb-preflight-ports-' + [guid]::NewGuid().ToString('N'))
        try {
            $p = Get-CyberButlerPreflight -InstallPath $target
            foreach ($port in @(6185, 18090, 8765, 11434, 11435)) {
                $matches = @($p.ports | Where-Object { $_.port -eq $port })
                $matches.Count | Should Be 1
                $matches[0].in_use.GetType().Name | Should Be 'Boolean'
                ($matches[0].PSObject.Properties.Name -contains 'pid') | Should Be $true
                ($matches[0].PSObject.Properties.Name -contains 'process_name') | Should Be $true
            }
        } finally {
            if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
        }
    }
}
