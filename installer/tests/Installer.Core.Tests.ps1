$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Core.ps1')
. (Join-Path $installerRoot 'lib\Installer.Services.ps1')

<#
.SYNOPSIS
    New-CoreFixture performs its documented CBS operation.
.DESCRIPTION
    Internal installer/runtime helper. Parameters and return behavior are defined by the function body.
#>
function New-CoreFixture {
    param(
        [string]$Root,
        [string]$Name,
        [string]$MainFile,
        [hashtable]$Files
    )
    $source = Join-Path $Root ($Name + '-src')
    New-Item -ItemType Directory -Path $source -Force | Out-Null
    foreach ($relative in $Files.Keys) {
        $path = Join-Path $source $relative
        $parent = Split-Path -Parent $path
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Set-Content -LiteralPath $path -Value $Files[$relative] -Encoding UTF8
    }
    Set-Content -LiteralPath (Join-Path $source $MainFile) -Value 'fixture' -Encoding UTF8
    $zip = Join-Path $Root ($Name + '.zip')
    Compress-Archive -Path (Join-Path $source '*') -DestinationPath $zip -Force
    return [pscustomobject]@{
        path = $zip
        sha256 = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
        source = $source
    }
}

Describe 'Installer core deployment' {
    It 'reports an empty install as incomplete' {
        $base = Join-Path $env:TEMP ('cb-core-empty-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $test = Test-CyberButlerCoreDeploy -InstallPath $base
            $test.satisfied | Should Be $false
            (($test.missing -join ';') -match 'tools') | Should Be $true
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'deploys a CBS-only tree without AgentRuntime or AuxRuntimeApplication' {
        $base = Join-Path $env:TEMP ('cb-core-cbs-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $target = Join-Path $base 'install'
            $result = Invoke-CyberButlerCoreDeploy -InstallPath $target -ExistingState 'None' -Tier Medium -SkipDependencyInstall
            $result.status | Should Be 'completed'
            (Test-Path -LiteralPath (Join-Path $target 'tools\broker.py')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $target 'webui\run.py')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $target 'data')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $target 'workspace')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $target 'AgentRuntime')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $target 'AuxRuntimeApplication')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $target 'python\python.exe')) | Should Be $true
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'reports a satisfied CBS-only tree' {
        $base = Join-Path $env:TEMP ('cb-core-satisfied-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            foreach ($dir in @('tools', 'webui', 'python', 'data', 'workspace')) {
                New-Item -ItemType Directory -Path (Join-Path $base $dir) -Force | Out-Null
            }
            foreach ($file in @('tools\broker.py', 'tools\email_approval.py', 'tools\wfp_guard.py', 'webui\run.py', 'webui\requirements.txt', 'python\python.exe', 'python\pip.pyz', 'VERSION')) {
                Set-Content -LiteralPath (Join-Path $base $file) -Value 'fixture' -Encoding ASCII
            }
            $test = Test-CyberButlerCoreDeploy -InstallPath $base
            $test.satisfied | Should Be $true
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'keeps the core.deploy handler contract' {
        $base = Join-Path $env:TEMP ('cb-core-handler-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $handlers = @{ 'core.deploy' = { param($c) [pscustomobject]@{ status = 'completed'; changed = $true; exit_code = 0; reason = 'handler' } } }
            $result = Invoke-CyberButlerCoreDeploy -InstallPath $base -Handlers $handlers
            $result.status | Should Be 'completed'
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }
}
