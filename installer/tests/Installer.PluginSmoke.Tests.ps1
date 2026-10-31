$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Services.ps1')

function New-SmokeLog {
    param([string]$Base, [string[]]$Lines)
    $logDir = Join-Path $Base 'AstrBot\data\logs'
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $logDir 'astrbot.log') -Value $Lines -Encoding UTF8
    return (Join-Path $logDir 'astrbot.log')
}

Describe 'Installer plugin load smoke' {
    It 'passes after the AstrBot startup marker with no CBS failures' {
        $base = Join-Path $env:TEMP ('cb-smoke-' + [guid]::NewGuid().ToString('N'))
        try {
            New-SmokeLog -Base $base -Lines @('AstrBot v4.29.3', 'Loading plugin astrbot_plugin_router ...', 'AstrBot started.') | Out-Null
            $result = Test-CyberButlerPluginLoadSmoke -Root $base -StartupTimeoutSeconds 5
            $result.ok | Should Be $true
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'fails on a CBS plugin failure even when the startup marker exists' {
        $base = Join-Path $env:TEMP ('cb-smoke-' + [guid]::NewGuid().ToString('N'))
        try {
            New-SmokeLog -Base $base -Lines @(
                'Loading plugin astrbot_plugin_router ...',
                '----- Failed to load plugin astrbot_plugin_router -----',
                '| ImportError: missing symbol',
                '----------------------------------',
                'AstrBot started.'
            ) | Out-Null
            $result = Test-CyberButlerPluginLoadSmoke -Root $base -StartupTimeoutSeconds 5
            $result.ok | Should Be $false
            $result.reason | Should Be 'plugin_failure'
            ($result.message -match 'astrbot_plugin_router') | Should Be $true
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'fails when no AstrBot log exists' {
        $base = Join-Path $env:TEMP ('cb-smoke-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path (Join-Path $base 'AstrBot\data') -Force | Out-Null
        try {
            $result = Test-CyberButlerPluginLoadSmoke -Root $base -StartupTimeoutSeconds 1
            $result.ok | Should Be $false
            $result.message | Should Match 'no AstrBot log found at expected paths'
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'fails when the startup marker never appears' {
        $base = Join-Path $env:TEMP ('cb-smoke-' + [guid]::NewGuid().ToString('N'))
        try {
            New-SmokeLog -Base $base -Lines @('AstrBot v4.29.3', 'Loading plugin astrbot_plugin_router ...') | Out-Null
            $result = Test-CyberButlerPluginLoadSmoke -Root $base -StartupTimeoutSeconds 1
            $result.ok | Should Be $false
            $result.reason | Should Be 'startup_timeout'
            $result.message | Should Match 'did not finish startup within 1s'
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'reports plugin failure instead of startup timeout when both are present' {
        $base = Join-Path $env:TEMP ('cb-smoke-' + [guid]::NewGuid().ToString('N'))
        try {
            New-SmokeLog -Base $base -Lines @(
                'Loading plugin astrbot_plugin_router ...',
                '----- Failed to load plugin astrbot_plugin_router -----',
                '| ImportError: missing symbol'
            ) | Out-Null
            $result = Test-CyberButlerPluginLoadSmoke -Root $base -StartupTimeoutSeconds 1
            $result.ok | Should Be $false
            $result.reason | Should Be 'plugin_failure'
            ($result.message -match 'astrbot_plugin_router') | Should Be $true
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'tolerates personal plugin failures only when no personal path was supplied' {
        $base = Join-Path $env:TEMP ('cb-smoke-' + [guid]::NewGuid().ToString('N'))
        try {
            New-SmokeLog -Base $base -Lines @(
                '----- Failed to load plugin astrbot_plugin_private_companion -----',
                '| ImportError: missing',
                'AstrBot started.'
            ) | Out-Null
            $without = Test-CyberButlerPluginLoadSmoke -Root $base -StartupTimeoutSeconds 5
            $without.ok | Should Be $true
            $with = Test-CyberButlerPluginLoadSmoke -Root $base -PersonalPluginsPath 'D:\plugins' -StartupTimeoutSeconds 5
            $with.ok | Should Be $false
            ($with.failed -contains 'astrbot_plugin_private_companion') | Should Be $true
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }
}
