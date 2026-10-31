$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Overlay.ps1')
. (Join-Path $installerRoot 'lib\Installer.Core.ps1')

function New-OverlayTestRoot {
    $base = Join-Path $env:TEMP ('cb-overlay-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    return $base
}

Describe 'Installer overlay compatibility' {
    It 'rejects a manifest whose AstrBot version does not match' {
        $base = New-OverlayTestRoot
        try {
            $astrbot = Join-Path $base 'AstrBot'
            $overlay = Join-Path $base 'overlay'
            New-Item -ItemType Directory -Path $astrbot, $overlay -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $astrbot 'VERSION') -Value '4.30.0' -Encoding ASCII
            $manifest = [ordered]@{ schema = 1; based_on_astrbot_version = '4.29.3'; files = @() }
            Write-InstallerJson -Path (Join-Path $overlay 'overlay-manifest.json') -Value $manifest
            { Test-CyberButlerOverlayManifest -AstrBotPath $astrbot -OverlayPath $overlay } | Should Throw
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'rejects a missing overlay dependency' {
        $base = New-OverlayTestRoot
        try {
            $astrbot = Join-Path $base 'AstrBot'
            $overlay = Join-Path $base 'overlay'
            New-Item -ItemType Directory -Path (Join-Path $astrbot 'astrbot\core') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $overlay 'astrbot\core') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $astrbot 'VERSION') -Value '4.29.3' -Encoding ASCII
            Set-Content -LiteralPath (Join-Path $overlay 'astrbot\core\demo.py') -Value '# demo' -Encoding ASCII
            $hash = (Get-FileHash -LiteralPath (Join-Path $overlay 'astrbot\core\demo.py') -Algorithm SHA256).Hash.ToLowerInvariant()
            $manifest = [ordered]@{
                schema = 1
                based_on_astrbot_version = '4.29.3'
                files = @([ordered]@{
                    path = 'astrbot/core/demo.py'
                    official_sha256 = $null
                    overlay_sha256 = $hash
                    reason = 'test'
                    depends_on = @('astrbot/core/missing.py')
                })
            }
            Write-InstallerJson -Path (Join-Path $overlay 'overlay-manifest.json') -Value $manifest
            { Test-CyberButlerOverlayManifest -AstrBotPath $astrbot -OverlayPath $overlay } | Should Throw
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'returns a clear failure when the AstrBot import smoke fails' {
        $base = New-OverlayTestRoot
        try {
            New-Item -ItemType Directory -Path (Join-Path $base 'AstrBot') -Force | Out-Null
            $fake = Join-Path $base 'fake-python.cmd'
            $fakeBody = '@echo ImportError: missing symbol 1>&2' + "`r`n" + '@exit /b 1'
            Set-Content -LiteralPath $fake -Value $fakeBody -Encoding ASCII
            $result = Test-CyberButlerCoreImportSmoke -InstallPath $base -PythonPath $fake
            $result.ok | Should Be $false
            $result.exit_code | Should Be 1
            (@($result.output) -join ' ') | Should Match 'ImportError'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }

    It 'checks symbol-present, symbol-missing and overlay-only scenarios' {
        $python = (Get-Command python.exe -ErrorAction SilentlyContinue).Source
        if (-not $python) { return }
        $base = New-OverlayTestRoot
        try {
            $official = Join-Path $base 'official'
            $overlay = Join-Path $base 'overlay'
            New-Item -ItemType Directory -Path (Join-Path $official 'astrbot\core') -Force | Out-Null
            New-Item -ItemType Directory -Path (Join-Path $overlay 'astrbot\core') -Force | Out-Null
            Set-Content -LiteralPath (Join-Path $official 'pyproject.toml') -Value 'version = "4.29.3"' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $official 'astrbot\__init__.py') -Value '' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $official 'astrbot\core\__init__.py') -Value '' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $official 'astrbot\core\po.py') -Value 'class Thing: pass' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $overlay 'astrbot\core\use.py') -Value 'from astrbot.core.po import Thing' -Encoding UTF8
            $checker = Join-Path (Split-Path $installerRoot -Parent) 'tools\check-overlay-compat.py'

            & $python $checker --official-source $official --overlay $overlay --expected-version 4.29.3 --output (Join-Path $base 'ok.json') | Out-Null
            $LASTEXITCODE | Should Be 0
            $ok = Get-Content -LiteralPath (Join-Path $base 'ok.json') -Raw | ConvertFrom-Json
            ($ok.files | Where-Object { $_.path -eq 'astrbot/core/use.py' }).status | Should Be 'ok'

            Set-Content -LiteralPath (Join-Path $overlay 'astrbot\core\use.py') -Value 'from astrbot.core.po import MissingThing' -Encoding UTF8
            & $python $checker --official-source $official --overlay $overlay --expected-version 4.29.3 --output (Join-Path $base 'bad.json') | Out-Null
            $LASTEXITCODE | Should Be 1
            $bad = Get-Content -LiteralPath (Join-Path $base 'bad.json') -Raw | ConvertFrom-Json
            ($bad.files | Where-Object { $_.path -eq 'astrbot/core/use.py' }).status | Should Be 'missing_dependency'

            Set-Content -LiteralPath (Join-Path $overlay 'astrbot\core\use.py') -Value 'from astrbot.core.po import Thing' -Encoding UTF8
            Set-Content -LiteralPath (Join-Path $overlay 'astrbot\core\added.py') -Value 'VALUE = 1' -Encoding UTF8
            & $python $checker --official-source $official --overlay $overlay --expected-version 4.29.3 --output (Join-Path $base 'added.json') | Out-Null
            $LASTEXITCODE | Should Be 0
            $added = Get-Content -LiteralPath (Join-Path $base 'added.json') -Raw | ConvertFrom-Json
            ($added.files | Where-Object { $_.path -eq 'astrbot/core/added.py' }).official_exists | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
