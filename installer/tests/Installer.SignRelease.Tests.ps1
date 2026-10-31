$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
$repoRoot = Split-Path -Parent $installerRoot
$python = Join-Path $repoRoot 'AstrBot\.venv\Scripts\python.exe'
$signScript = Join-Path $repoRoot 'tools\sign_release.py'

Describe 'Release signing path' {
    It 'honors --signature and uses update-manifest.sig by default' {
        if (-not (Test-Path -LiteralPath $python) -or -not (Test-Path -LiteralPath $signScript)) { return }
        $base = Join-Path $env:TEMP ('cb-sign-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $key = Join-Path $base 'private.pem'
            $manifest = Join-Path $base 'update-manifest.json'
            $keygen = Join-Path $base 'keygen.py'
            Set-Content -LiteralPath $manifest -Value '{}' -Encoding ASCII
            Set-Content -LiteralPath $keygen -Value @'
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa
key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
open(__import__('sys').argv[1], 'wb').write(key.private_bytes(
    serialization.Encoding.PEM,
    serialization.PrivateFormat.PKCS8,
    serialization.NoEncryption(),
))
'@ -Encoding ASCII
            & $python $keygen $key
            $LASTEXITCODE | Should Be 0

            $custom = Join-Path $base 'custom.sig'
            & $python $signScript --manifest $manifest --key $key --signature $custom | Out-Null
            $LASTEXITCODE | Should Be 0
            (Test-Path -LiteralPath $custom) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'update-manifest.json.sig')) | Should Be $false

            Remove-Item -LiteralPath $custom -Force
            & $python $signScript --manifest $manifest --key $key | Out-Null
            $LASTEXITCODE | Should Be 0
            (Test-Path -LiteralPath (Join-Path $base 'update-manifest.sig')) | Should Be $true
            (Test-Path -LiteralPath (Join-Path $base 'update-manifest.json.sig')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
