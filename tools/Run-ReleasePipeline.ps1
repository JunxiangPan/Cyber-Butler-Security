#requires -Version 5.1
<#
Run-ReleasePipeline.ps1

The ONLY supported way to build a release. It:
  1. prints its own SHA-256 and refuses an unapproved changed pipeline;
  2. requires a human-provided random challenge;
  3. runs static, comment, docs, quality and Pester gates;
  4. requires a real ACCEPTANCE_PROOF.md from the VM;
  5. only then writes a token that package_release.py accepts;
  6. writes BUILD_REPORT.md and prints the final two hashes.

No zip is produced when any gate is red.
#>
[CmdletBinding()]
param(
    [string]$Challenge = '',
    [switch]$ApproveChangedPipeline,
    [switch]$Sign,
    [string]$InstallRoot = 'C:\CyberButler'
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pipeline = $PSCommandPath
$selfHash = (Get-FileHash -LiteralPath $pipeline -Algorithm SHA256).Hash
Write-Host ('PIPELINE_SHA256=' + $selfHash)

$hashFile = Join-Path $PSScriptRoot 'Run-ReleasePipeline.sha256'
if (Test-Path -LiteralPath $hashFile) {
    $expected = (Get-Content -LiteralPath $hashFile -Raw).Trim()
    if ($expected -ne $selfHash) {
        if (-not $ApproveChangedPipeline) {
            throw 'Pipeline hash changed. Re-run with -ApproveChangedPipeline only after human review.'
        }
        $confirm = Read-Host 'Human review: type MODIFIED to accept the changed pipeline'
        if ($confirm -ne 'MODIFIED') { throw 'Changed pipeline not approved' }
    }
}
if ([string]::IsNullOrWhiteSpace($Challenge)) {
    $Challenge = Read-Host 'Enter the random challenge for this build'
}
if ([string]::IsNullOrWhiteSpace($Challenge)) { throw 'A non-empty random challenge is required' }

$report = New-Object System.Collections.Generic.List[string]
function Add-Report([string]$text) { $report.Add($text); Write-Host $text }
function Run-Step([string]$name, [scriptblock]$action) {
    Add-Report ('## ' + $name)
    $output = & $action 2>&1 | Out-String
    $code = $LASTEXITCODE
    Add-Report ('```text' + [Environment]::NewLine + $output.Trim() + [Environment]::NewLine + 'EXIT_CODE=' + $code + [Environment]::NewLine + '```')
    if ($code -ne 0) { throw ('gate failed: ' + $name + ' exit=' + $code) }
}
function Run-Process([string]$name, [string]$exe, [string[]]$arguments) {
    Run-Step $name { & $exe @arguments }
}

Add-Report '# BUILD_REPORT'
Add-Report ''
Add-Report ('- Challenge: `' + $Challenge + '`')
Add-Report ('- Generated: ' + (Get-Date).ToUniversalTime().ToString('o'))
Add-Report ('- Host: ' + $env:COMPUTERNAME)
Add-Report ('- Pipeline SHA256: ' + $selfHash)
$macs = @(Get-NetAdapter | Select-Object -ExpandProperty MacAddress)
Add-Report ('- MAC: ' + ($macs -join ', '))
Add-Report ('- VERSION: ' + ((Get-Content (Join-Path $root 'VERSION') -Raw).Trim()))
Add-Report ''

Run-Process 'packaging preflight' 'python' @('quality/preflight.py')
Run-Process 'code comments (AST)' 'python' @('tools/audit_code_comments.py')
Run-Process 'docs consistency' 'python' @('tools/audit_docs_consistency.py')
Run-Process '25-item quality matrix' 'python' @('quality/run_quality_matrix.py', '--nonce', $Challenge)
Run-Process 'pytest' 'python' @('-m', 'pytest', '-q')
Run-Step 'Pester' {
    Import-Module Pester -MinimumVersion 3.4 -ErrorAction Stop
    $result = Invoke-Pester -Script (Join-Path $root 'installer/tests') -PassThru
    if ($result.FailedCount -ne 0) { exit 1 }
}

# Physical proof from the real VM acceptance run.
$proof = Join-Path $root 'ACCEPTANCE_PROOF.md'
if (-not (Test-Path -LiteralPath $proof)) { throw 'ACCEPTANCE_PROOF.md missing; VM evidence is mandatory' }
$proofText = Get-Content -LiteralPath $proof -Raw -Encoding UTF8
Add-Report '## VM acceptance proof'
Add-Report ('```markdown' + [Environment]::NewLine + $proofText.Trim() + [Environment]::NewLine + '```')
if ($proofText -notmatch 'Overall: PASS') { throw 'ACCEPTANCE_PROOF.md is not PASS' }
if ($proofText -notmatch 'negative_403=True') { throw 'negative TOTP evidence missing' }
if ($proofText -notmatch 'negative_path=True') { throw 'negative path evidence missing' }

# Build only from this pipeline via the token gate.
$token = [guid]::NewGuid().ToString('N')
$tokenPath = Join-Path $root 'quality/.release-pipeline-token'
[IO.File]::WriteAllText($tokenPath, $token, (New-Object Text.UTF8Encoding($false)))
$env:CBS_RELEASE_PIPELINE_TOKEN = $token
try {
    Run-Process 'build package' 'python' @('tools/package_release.py', '--baseline-core', (Join-Path $root 'tools/update_core.py'))
} finally {
    Remove-Item -LiteralPath $tokenPath -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\CBS_RELEASE_PIPELINE_TOKEN -ErrorAction SilentlyContinue
}

$zip = Join-Path (Split-Path -Parent $root) 'public-release-v1.6.3.zip'
if (-not (Test-Path -LiteralPath $zip)) { throw 'package_release.py did not create the zip' }
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
Add-Report ''
Add-Report ('- Zip SHA256: ' + $zipHash)
$reportPath = Join-Path $root 'BUILD_REPORT.md'
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$reportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash
Write-Host ('[BUILD_MANIFEST] Zip_SHA256: ' + $zipHash + ' | Report_SHA256: ' + $reportHash)
if ($Sign) {
    Write-Host 'Signing is intentionally a separate step after human review of BUILD_REPORT.md.'
}
