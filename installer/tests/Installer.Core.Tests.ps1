$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Core.ps1')
. (Join-Path $installerRoot 'lib\Installer.PersonalPlugins.ps1')
. (Join-Path $installerRoot 'lib\Installer.Services.ps1')

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
    It 'installs a clean AstrBot + SnowLuma + venv + overlay' {
        $base = Join-Path $env:TEMP ('cb-core-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $astrbot = New-CoreFixture -Root $base -Name 'astrbot-fixture' -MainFile 'main.py' -Files @{
                'requirements.txt' = ''
                'astrbot\core\probe.py' = 'probe'
            }
            $snow = New-CoreFixture -Root $base -Name 'snow-fixture' -MainFile 'index.mjs' -Files @{
                'package.json' = '{}'
            }
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath (Join-Path $base 'install') -Tier Medium
            $realPython = (Get-Command python.exe -ErrorAction Stop).Source
            $pythonMarker = Join-Path $base 'python-shim.marker'
            $pythonShim = Join-Path $base 'python-shim.cmd'
            $shimText = '@echo %* > "' + $pythonMarker + '"' + "`r`n" + '"' + $realPython + '" %*' + "`r`n" + 'exit /b %ERRORLEVEL%'
            Set-Content -LiteralPath $pythonShim -Value $shimText -Encoding ASCII
            $result = Invoke-CyberButlerCoreDeploy -InstallPath (Join-Path $base 'install') -ExistingState 'None' -Tier Medium `
                -AstrBotPackage $astrbot.path -SnowLumaPackage $snow.path `
                -AstrBotSha256 $astrbot.sha256 -SnowLumaSha256 $snow.sha256 -PythonPath $pythonShim -PythonSource 'bundled' -PythonVersion 'Python 3.13.17' -SkipOverlayManifest -Journal $journal
            $result.status | Should Be 'completed'
            $result.python_source | Should Be 'bundled'
            $result.python_path | Should Be $pythonShim
            (Test-Path -LiteralPath (Join-Path $base 'install\AstrBot\main.py')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install\AstrBot\.venv\Scripts\python.exe')) | Should Be $true
            (Test-Path -LiteralPath $pythonMarker) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install\SnowLuma\index.mjs')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install\workspace')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install\tools')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install\webui\run.py')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install\tools\broker.py')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install\tools\email_approval.py')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install	oolsroker_config.json')) | Should Be $true
            $fixtureBrokerConfig = Get-Content -LiteralPath (Join-Path $base 'install	oolsroker_config.json') -Raw -Encoding UTF8 | ConvertFrom-Json
            ([string]$fixtureBrokerConfig.approval_channel) | Should Be 'qq'
            (Test-Path -LiteralPath (Join-Path $base 'install\AstrBot\data')) | Should Be $true
            foreach ($cbs in @('astrbot_plugin_at_gate','astrbot_plugin_cloud_fallback','astrbot_plugin_dsh_bridge','astrbot_plugin_dst_guard','astrbot_plugin_mcp_readonly','astrbot_plugin_router','astrbot_plugin_security_gate','astrbot_plugin_totp_broker','astrbot_plugin_weather_tools','astrbot_plugin_webui_bridge')) {
                $cbsPath = Join-Path (Join-Path (Join-Path $base 'install\AstrBot\data') 'plugins') ($cbs + '\main.py')
                if (-not (Test-Path -LiteralPath $cbsPath)) { Write-Host ('MISSING_CBS ' + $cbsPath) }
                (Test-Path -LiteralPath $cbsPath) | Should Be $true
            }
            $specs = Get-CyberButlerServiceSpecs -Root (Join-Path $base 'install') -DesktopAccount 'DOMAIN\Desktop'
            foreach ($spec in $specs) {
                (Test-Path -LiteralPath $spec.exe) | Should Be $true
            }
            (Test-Path -LiteralPath (Join-Path $base 'install\data')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install\AstrBot\astrbot\core\tools\message_tools.py')) | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'accepts local package paths without network' {
        $base = Join-Path $env:TEMP ('cb-core-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $astrbot = New-CoreFixture -Root $base -Name 'astrbot-local' -MainFile 'main.py' -Files @{ 'requirements.txt' = '' }
            $snow = New-CoreFixture -Root $base -Name 'snow-local' -MainFile 'index.mjs' -Files @{ 'package.json' = '{}' }
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath (Join-Path $base 'install') -Tier Medium
            $result = Invoke-CyberButlerCoreDeploy -InstallPath (Join-Path $base 'install') -ExistingState 'None' -Tier Medium `
                -AstrBotPackage $astrbot.path -SnowLumaPackage $snow.path `
                -AstrBotSha256 $astrbot.sha256 -SnowLumaSha256 $snow.sha256 `
                -SkipDependencyInstall -SkipOverlayManifest -Journal $journal
            $result.status | Should Be 'completed'
            (Test-Path -LiteralPath (Join-Path $base 'install\AstrBot\main.py')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'install\SnowLuma\index.mjs')) | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'merges a Legacy install without touching data or extra files' {
        $base = Join-Path $env:TEMP ('cb-core-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $target = Join-Path $base 'install'
            New-Item -ItemType Directory -Path (Join-Path $target 'AstrBot\data') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $target 'VERSION') -Value '1.5.3' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $target 'AstrBot\data\keep.txt') -Value 'keep' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $target 'AstrBot\old.txt') -Value 'old' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $target 'AstrBot\main.py') -Value 'old-main' -Encoding ASCII
            $astrbot = New-CoreFixture -Root $base -Name 'astrbot-legacy' -MainFile 'main.py' -Files @{
                'requirements.txt' = ''
                'astrbot\core\probe.py' = 'new'
            }
            $snow = New-CoreFixture -Root $base -Name 'snow-legacy' -MainFile 'index.mjs' -Files @{ 'package.json' = '{}' }
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath $target -Tier Medium
            $result = Invoke-CyberButlerCoreDeploy -InstallPath $target -ExistingState 'Legacy' -Tier Medium `
                -AstrBotPackage $astrbot.path -SnowLumaPackage $snow.path `
                -AstrBotSha256 $astrbot.sha256 -SnowLumaSha256 $snow.sha256 -SkipOverlayManifest -Journal $journal
            $result.status | Should Be 'completed'
            (Get-Content -LiteralPath (Join-Path $target 'AstrBot\data\keep.txt') -Raw).Trim() | Should Be 'keep'
            (Get-Content -LiteralPath (Join-Path $target 'AstrBot\old.txt') -Raw).Trim() | Should Be 'old'
            (Get-Content -LiteralPath (Join-Path $target 'AstrBot\main.py') -Raw).Trim() | Should Be 'fixture'
            (Test-Path -LiteralPath (Join-Path $target 'AstrBot\astrbot\core\tools\message_tools.py')) | Should Be $true
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'streams pip output and writes a pip install log' {
        $base = Join-Path $env:TEMP ('cb-pip-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $fake = Join-Path $base 'fake-pip.cmd'
            $log = Join-Path $base 'pip-install.log'
            $requirements = Join-Path $base 'requirements.txt'
            Set-Content -LiteralPath $requirements -Value '' -Encoding ASCII
            $fakeText = "@echo off`r`necho FAKE_PIP_OUTPUT`r`necho FAKE_PIP_ERROR 1>&2`r`nexit /b 0"
            Set-Content -LiteralPath $fake -Value $fakeText -Encoding ASCII
            $result = Invoke-CyberButlerPipInstall -PythonPath $fake -Requirements $requirements -LogPath $log
            $result.exit_code | Should Be 0
            (Test-Path -LiteralPath $log) | Should Be $true
            ((Get-Content -LiteralPath $log -Raw) -match 'FAKE_PIP_OUTPUT') | Should Be $true
            (@($result.output) -join "`n") | Should Match 'FAKE_PIP_OUTPUT'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'prints a heartbeat while pip is silent and keeps the full log' {
        $base = Join-Path $env:TEMP ('cb-pip-heartbeat-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $fake = Join-Path $base 'fake-pip.cmd'
            $log = Join-Path $base 'pip-install.log'
            $requirements = Join-Path $base 'requirements.txt'
            Set-Content -LiteralPath $requirements -Value '' -Encoding ASCII
            $fakeText = "@echo off`r`necho Installing collected packages: demo`r`nping -n 6 127.0.0.1 >nul`r`necho Successfully installed demo`r`nexit /b 0"
            Set-Content -LiteralPath $fake -Value $fakeText -Encoding ASCII
            $script:cbFakeNow = Get-Date
            $clock = { $script:cbFakeNow = $script:cbFakeNow.AddSeconds(300); $script:cbFakeNow }
            $captured = & { Invoke-CyberButlerPipInstall -PythonPath $fake -Requirements $requirements -LogPath $log -HeartbeatSeconds 30 -PollMilliseconds 100 -Clock $clock } 6>&1
            $text = ($captured | ForEach-Object { [string]$_ }) -join "`n"
            $result = @($captured | Where-Object { $_.PSObject.Properties['heartbeats'] })[0]
            $text | Should Match 'CORE pip still running\.\.\.'
            $result.heartbeats | Should BeGreaterThan 0
            (@($result.output) -join "`n") | Should Not Match 'CORE pip still running'
            $raw = Get-Content -LiteralPath $log -Raw
            $raw | Should Match 'Installing collected packages: demo'
            $raw | Should Match 'Successfully installed demo'
            $result.exit_code | Should Be 0
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'does not leave a partial fresh install when SHA-256 verification fails' {
        $base = Join-Path $env:TEMP ('cb-core-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $astrbot = New-CoreFixture -Root $base -Name 'astrbot-bad' -MainFile 'main.py' -Files @{ 'requirements.txt' = '' }
            $snow = New-CoreFixture -Root $base -Name 'snow-bad' -MainFile 'index.mjs' -Files @{ 'package.json' = '{}' }
            $journal = New-CyberButlerJournal -Root (Join-Path $base 'state') -InstallPath (Join-Path $base 'install') -Tier Medium
            $result = Invoke-CyberButlerCoreDeploy -InstallPath (Join-Path $base 'install') -ExistingState 'None' -Tier Medium `
                -AstrBotPackage $astrbot.path -SnowLumaPackage $snow.path `
                -AstrBotSha256 ('0' * 64) -SnowLumaSha256 $snow.sha256 -SkipOverlayManifest -Journal $journal
            $result.status | Should Be 'failed'
            $result.message | Should Match 'SHA-256 mismatch'
            (Test-Path -LiteralPath (Join-Path $base 'install\AstrBot')) | Should Be $false
            (Test-Path -LiteralPath (Join-Path $base 'install\SnowLuma')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'keeps Core completed when personal plugin copy fails' {
        $base = Join-Path $env:TEMP ('cb-core-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $astrbot = New-CoreFixture -Root $base -Name 'astrbot-personal' -MainFile 'main.py' -Files @{ 'requirements.txt' = ''; 'astrbot\core\probe.py' = 'probe' }
            $snow = New-CoreFixture -Root $base -Name 'snow-personal' -MainFile 'index.mjs' -Files @{ 'package.json' = '{}' }
            $personal = Join-Path $base 'personal'
            foreach ($name in @('astrbot_plugin_private_companion','astrbot_plugin_livingmemory')) {
                New-Item -ItemType Directory -Path (Join-Path $personal $name) -Force | Out-Null
                Set-Content -LiteralPath (Join-Path $personal ($name + '\main.py')) -Value 'x' -Encoding UTF8
                Set-Content -LiteralPath (Join-Path $personal ($name + '\metadata.yaml')) -Value 'x' -Encoding UTF8
            }
            $python = (Get-Command python.exe -ErrorAction Stop).Source
            $result = Invoke-CyberButlerCoreDeploy -InstallPath (Join-Path $base 'install') -ExistingState 'None' -Tier Medium `
                -AstrBotPackage $astrbot.path -SnowLumaPackage $snow.path -AstrBotSha256 $astrbot.sha256 -SnowLumaSha256 $snow.sha256 `
                -PythonPath $python -SkipDependencyInstall -SkipOverlayManifest -PersonalPluginsPath $personal
            $result.status | Should Be 'completed'
            $result.personal_plugins_status | Should Be 'failed'
            (Test-Path -LiteralPath (Join-Path $base 'install\AstrBot')) | Should Be $true
        } finally { Remove-Item -LiteralPath $base -Recurse -Force }
    }

    It 'fails when the import smoke reports a missing symbol' {
        $base = Join-Path $env:TEMP ('cb-core-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $astrbot = New-CoreFixture -Root $base -Name 'astrbot-smoke' -MainFile 'main.py' -Files @{
                'requirements.txt' = '# dependency'
                'astrbot\core\probe.py' = 'probe'
            }
            $snow = New-CoreFixture -Root $base -Name 'snow-smoke' -MainFile 'index.mjs' -Files @{ 'package.json' = '{}' }
            $python = (Get-Command python.exe -ErrorAction Stop).Source
            $handlers = @{
                'core.import' = { param($c) [pscustomobject]@{ ok = $false; exit_code = 1; output = @('ImportError: cannot import name Missing') } }
            }
            $result = Invoke-CyberButlerCoreDeploy -InstallPath (Join-Path $base 'install') -ExistingState 'None' -Tier Medium `
                -AstrBotPackage $astrbot.path -SnowLumaPackage $snow.path `
                -AstrBotSha256 $astrbot.sha256 -SnowLumaSha256 $snow.sha256 -PythonPath $python -SkipOverlayManifest -Handlers $handlers
            $result.status | Should Be 'failed'
            $result.message | Should Match 'import smoke failed'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'imports astrbot.core with the pinned overlay pair' {
        $repoRoot = Split-Path $installerRoot -Parent
        $python = Join-Path $repoRoot 'AstrBot\.venv\Scripts\python.exe'
        if (-not (Test-Path -LiteralPath $python)) { return }
        $smoke = Test-CyberButlerCoreImportSmoke -InstallPath $repoRoot -PythonPath $python
        $smoke.ok | Should Be $true
    }
}

