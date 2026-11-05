# Hidden Python launcher for scheduled tasks.
# A task action that starts python.exe directly leaves a visible console.
# pythonw.exe avoids the console but can break applications that write to
# stdout/stderr. This wrapper keeps python.exe hidden and redirects its output.

param(
    [Parameter(Mandatory = $true)][string]$Python,
    [Parameter(Mandatory = $true)][string]$Script,
    [Parameter(Mandatory = $true)][string]$WorkDir,
    [string]$StdOut = '',
    [string]$StdErr = ''
)

$ErrorActionPreference = 'Stop'

$startArgs = @{
    FilePath = $Python
    ArgumentList = @($Script)
    WorkingDirectory = $WorkDir
    WindowStyle = 'Hidden'
    PassThru = $true
    Wait = $true
}
if (-not [string]::IsNullOrWhiteSpace($StdOut)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $StdOut) -Force | Out-Null
    $startArgs.RedirectStandardOutput = $StdOut
}
if (-not [string]::IsNullOrWhiteSpace($StdErr)) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $StdErr) -Force | Out-Null
    $startArgs.RedirectStandardError = $StdErr
}

$process = Start-Process @startArgs
exit $process.ExitCode
