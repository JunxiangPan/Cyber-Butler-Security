$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Core.ps1')

Describe 'Installer offline wheelhouse' {
    It 'contains the required Windows x64 Python 3.13 wheels' {
        $wheelhouse = Join-Path $installerRoot 'wheelhouse'
        (Test-Path -LiteralPath $wheelhouse) | Should Be $true
        $names = @(Get-ChildItem -LiteralPath $wheelhouse -Filter '*.whl' -File | Select-Object -ExpandProperty Name)
        ($names -join ';') | Should Match 'fastapi-'
        ($names -join ';') | Should Match 'pyotp-'
        ($names -join ';') | Should Match 'qrcode-'
        ($names -join ';') | Should Match 'pywin32-'
        ($names -join ';') | Should Match 'pillow-'
        ($names -join ';') | Should Match 'cp313'
        ($names -join ';') | Should Not Match 'pytest'
    }

    It 'uses --no-index and --find-links when the wheelhouse is present' {
        $base = Join-Path $env:TEMP ('cb-wheelhouse-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $argsFile = Join-Path $base 'pip-args.txt'
            $fake = Join-Path $base 'fake-python.cmd'
            $body = '@if "%1"=="-c" (echo 3.13 & exit /b 0)' + "`r`n" + '@echo %* >> "' + $argsFile + '"' + "`r`n" + '@exit /b 0'
            Set-Content -LiteralPath $fake -Value $body -Encoding ASCII
            $requirements = Join-Path $base 'requirements.txt'
            Set-Content -LiteralPath $requirements -Value 'fastapi==0.162.0' -Encoding ASCII
            $log = Join-Path $base 'pip.log'
            $result = Invoke-CyberButlerPipInstall -PythonPath $fake -Requirements $requirements -LogPath $log
            $result.exit_code | Should Be 0
            (Test-Path -LiteralPath $argsFile) | Should Be $true
            $args = Get-Content -LiteralPath $argsFile -Raw
            $args | Should Match '--no-index'
            $args | Should Match '--find-links'
            $args | Should Match 'wheelhouse'
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
