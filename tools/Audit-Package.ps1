#requires -Version 5.1
<#
Audit-Package.ps1

Reverse-audit a release zip. It does not trust a BUILD_REPORT.md by itself:
it checks the challenge, the zip SHA-256, the report SHA-256, and the presence
of raw icacls/curl/audit evidence. A report inside the zip would create a
self-referential hash; this project therefore requires the report sidecar
next to the zip. If a report is found inside the zip, it is also inspected.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ZipPath,
    [string]$ReportPath = '',
    [string]$Challenge = ''
)

$ErrorActionPreference = 'Stop'
$zip = [IO.Path]::GetFullPath($ZipPath)
if (-not (Test-Path -LiteralPath $zip)) { throw 'zip not found: ' + $zip }
if ([string]::IsNullOrWhiteSpace($ReportPath)) {
    $ReportPath = Join-Path (Split-Path -Parent $zip) 'BUILD_REPORT.md'
}
$report = [IO.Path]::GetFullPath($ReportPath)
if (-not (Test-Path -LiteralPath $report)) {
    # fall back to a report embedded in the zip
    $temp = Join-Path $env:TEMP ('cbs-audit-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $temp -Force | Out-Null
    try {
        Expand-Archive -LiteralPath $zip -DestinationPath $temp -Force
        $inside = Join-Path $temp 'BUILD_REPORT.md'
        if (-not (Test-Path -LiteralPath $inside)) {
            throw 'BUILD_REPORT.md is neither beside the zip nor inside it'
        }
        $report = $inside
    } finally {
        # keep no artifact; report is read below before cleanup is irrelevant
    }
}
if ([string]::IsNullOrWhiteSpace($Challenge)) {
    $Challenge = Read-Host 'Enter the challenge you supplied to Run-ReleasePipeline.ps1'
}
if ([string]::IsNullOrWhiteSpace($Challenge)) { throw 'challenge required' }

$text = Get-Content -LiteralPath $report -Raw -Encoding UTF8
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
$reportHash = (Get-FileHash -LiteralPath $report -Algorithm SHA256).Hash
$problems = New-Object System.Collections.Generic.List[string]

if ($text -notmatch ('Challenge:\s*`?' + [regex]::Escape($Challenge))) {
    $problems.Add('challenge mismatch')
}
if ($text -notmatch ('Zip SHA256:\s*' + [regex]::Escape($zipHash))) {
    $problems.Add('zip SHA-256 mismatch')
}
if ($text -notmatch 'Overall: PASS') { $problems.Add('report is not Overall: PASS') }
foreach ($marker in @('icacls', 'curl', 'audit.jsonl', 'HTTP_STATUS', 'negative_403=True')) {
    if ($text -notmatch [regex]::Escape($marker)) { $problems.Add('missing evidence marker: ' + $marker) }
}

$status = if ($problems.Count -eq 0) { 'PASS' } else { 'FAIL' }
[pscustomobject]@{
    zip = $zip
    zip_sha256 = $zipHash
    report = $report
    report_sha256 = $reportHash
    challenge = $Challenge
    status = $status
    problems = @($problems)
} | ConvertTo-Json -Depth 5
if ($problems.Count -eq 0) {
    Write-Host 'AUDIT_PASS'
    exit 0
}
Write-Host 'AUDIT_FAIL'
exit 1
