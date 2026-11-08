$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$installerRoot = Split-Path -Parent $here
. (Join-Path $installerRoot 'lib\Installer.Common.ps1')
. (Join-Path $installerRoot 'lib\Installer.Journal.ps1')
. (Join-Path $installerRoot 'lib\Installer.Python.ps1')
. (Join-Path $installerRoot 'lib\Installer.Preflight.ps1')

Describe 'Installer Python bundle' {
    It 'records a pinned Python 3.13.17 source with a valid SHA-256' {
        $source = Get-CyberButlerPythonSourceConfig -CoreSourcesPath (Join-Path $installerRoot 'core-sources.json')
        $source.version | Should Be '3.13.17'
        ([string]$source.sha256) | Should Match '^[0-9a-fA-F]{64}$'
        ([string]$source.url) | Should Match '^https://www\.python\.org/'
    }

    It 'selects an existing bundled Python without requiring a download' {
        $target = Join-Path $env:TEMP ('cb-python-bundled-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $target -Force | Out-Null
        try {
            $candidate = [pscustomobject]@{
                found = $true
                path = (Join-Path $target '.python\python.exe')
                candidate_path = (Join-Path $target '.python\python.exe')
                python_source = 'bundled'
                version = 'Python 3.13.17'
                version_ok = $true
                version_too_new = $false
            }
            $p = Get-CyberButlerPreflight -InstallPath $target -Handlers @{ 'preflight.python' = { param($c) @($candidate) } }
            $p.python_needs_bundle | Should Be $false
            $p.python_source | Should Be 'bundled'
            $p.python_resolved_path | Should Be $candidate.path
        } finally {
            Remove-Item -LiteralPath $target -Recurse -Force
        }
    }

    It 'stops immediately on a Python installer SHA-256 mismatch' {
        $base = Join-Path $env:TEMP ('cb-python-sha-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        try {
            $package = Join-Path $base 'python-3.13.17-amd64.exe'
            Set-Content -LiteralPath $package -Value 'not-a-real-installer' -Encoding ASCII
            $result = Invoke-CyberButlerPythonBootstrap -InstallPath (Join-Path $base 'install') -PythonPackage $package -PythonSha256 ('0' * 64)
            $result.status | Should Be 'failed'
            $result.reason | Should Be 'sha_mismatch'
            $result.code | Should Be 'python_bootstrap_failed'
            (Test-Path -LiteralPath (Join-Path $base 'install\.python')) | Should Be $false
        } finally {
            Remove-Item -LiteralPath $base -Recurse -Force
        }
    }
}
