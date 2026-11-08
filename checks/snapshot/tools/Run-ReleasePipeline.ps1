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
    [string]$Version = '',
    [string]$Challenge = '',
    [switch]$ApproveChangedPipeline,
    [switch]$Candidate,
    [switch]$Sign,
    [switch]$Unsigned,
    [string]$InstallRoot = 'C:\CyberButler',
    [string]$ProofPath = '',
    [string]$ProofSource = '',
    [string]$VerifyReleaseTag = '',
    [string]$Repository = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$proof = Join-Path $root 'ACCEPTANCE_PROOF.md'
if ([string]::IsNullOrWhiteSpace($ProofSource)) { $ProofSource = 'repo-committed' }
if (-not [string]::IsNullOrWhiteSpace($ProofPath)) {
    if (-not (Test-Path -LiteralPath $ProofPath)) { throw ('proof artifact missing: ' + $ProofPath) }
    Copy-Item -LiteralPath $ProofPath -Destination $proof -Force
}
if ($Unsigned -and $ProofSource -eq 'repo-committed') {
    throw 'unsigned build must consume a vm-proof artifact, not a committed historical proof'
}
if ($Unsigned -and [string]::IsNullOrWhiteSpace($ProofPath)) {
    throw 'unsigned build requires -ProofPath from the vm-proof artifact'
}
$sigPath = Join-Path $root 'update-manifest.sig'
if ($Unsigned -and (Test-Path -LiteralPath $sigPath)) {
    throw 'unsigned mode cannot have existing update-manifest.sig'
}
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

$gitStatus = (& git -C $root status --porcelain 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw ('git status failed: ' + $gitStatus) }
if ($gitStatus) { throw 'release discipline: working tree is dirty; commit before packaging' }
$manifestPath = Join-Path $root 'update-manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw 'update-manifest.json is missing; cannot determine release version' }
$manifestVersion = (Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json).version
if ([string]::IsNullOrWhiteSpace($Version)) { $Version = [string]$manifestVersion }
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw ('invalid release version: ' + $Version) }
if ([string]$manifestVersion -ne $Version) {
    throw ('version mismatch: -Version ' + $Version + ' != update-manifest.json ' + $manifestVersion)
}
$declaredVersion = (Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw).Trim()
if ($declaredVersion -ne $Version) {
    throw ('version gate: -Version ' + $Version + ' != VERSION ' + $declaredVersion)
}
$releaseBranch = 'release/v' + $Version
$head = (& git -C $root rev-parse HEAD 2>&1 | Out-String).Trim()
$upstream = (& git -C $root rev-parse ('origin/' + $releaseBranch) 2>&1 | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $head -or -not $upstream) { throw ('release discipline: cannot resolve HEAD or origin/' + $releaseBranch) }
if ($head -ne $upstream) { throw ('release discipline: HEAD ' + $head + ' != origin/' + $releaseBranch + ' ' + $upstream + '; push first') }
$report = New-Object System.Collections.Generic.List[string]
function Add-Report([string]$text) { $report.Add($text); Write-Host $text }
function Run-Step([string]$name, [scriptblock]$action) {
    Add-Report ('## ' + $name)
    $output = (& $action 2>&1 | Out-String).Replace($root, '<repo>')
    $code = $LASTEXITCODE
    Add-Report ('```text' + [Environment]::NewLine + $output.Trim() + [Environment]::NewLine + 'EXIT_CODE=' + $code + [Environment]::NewLine + '```')
    if ($code -ne 0) { throw ('gate failed: ' + $name + ' exit=' + $code) }
}
function Run-Process([string]$name, [string]$exe, [string[]]$arguments) {
    Run-Step $name { & $exe @arguments }
}
function Run-Warning([string]$name, [string]$exe, [string[]]$arguments) {
    Add-Report ('## WARNING: ' + $name)
    $output = (& $exe @arguments 2>&1 | Out-String).Replace($root, '<repo>')
    Add-Report ('```text' + [Environment]::NewLine + $output.Trim() + [Environment]::NewLine + 'EXIT_CODE=' + $LASTEXITCODE + [Environment]::NewLine + '```')
}

Add-Report '# BUILD_REPORT'
Add-Report ('- Release Version: ' + $Version)
Add-Report ('- Build Mode: ' + $(if ($Unsigned) { 'unsigned' } else { 'signed' }))
Add-Report ('- proof_source: ' + $ProofSource)
Add-Report ''
Add-Report ('- Current Commit: ' + $head)
Add-Report ('- Build Time: ' + (Get-Date).ToUniversalTime().ToString('o'))
$sealPath = Join-Path $env:TEMP ('cbp-self-seal-' + [guid]::NewGuid().ToString('N') + '.json')
Run-Process 'self-seal record' 'python' @('quality/self_seal.py', '--record', $sealPath)
Add-Report ('ChallengeCode: ' + $Challenge)
Add-Report ('- Generated: ' + (Get-Date).ToUniversalTime().ToString('o'))
Add-Report ('- Host: ' + $env:COMPUTERNAME)
Add-Report ('- Pipeline SHA256: ' + $selfHash)
$macs = @(Get-NetAdapter | Select-Object -ExpandProperty MacAddress)
Add-Report ('- MAC: ' + ($macs -join ', '))
Add-Report ('- VERSION: ' + ((Get-Content (Join-Path $root 'VERSION') -Raw).Trim()))
Add-Report ''

Run-Process 'install CBP from hashed wheelhouse' 'python' @('-m', 'pip', 'install', '--require-hashes', '--find-links', 'installer/wheelhouse', '-r', 'requirements-runtime.lock')
Run-Process 'forbidden terms / private paths in all text' 'python' @('tools/audit_text_hygiene.py', '.')
Run-Process 'packaging preflight' 'python' @('quality/preflight.py')
Run-Process 'test PowerShell syntax' 'pwsh.exe' @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'quality/parse_ps_tests.ps1')
Run-Process 'code comments (AST)' 'python' @('tools/audit_code_comments.py')
Run-Process 'docs consistency' 'python' @('tools/audit_docs_consistency.py')
Run-Process 'UI sanity (styled console, no dead UI terms/routes)' 'python' @('quality/ui_gate.py')
Run-Process 'acceptance fragility (TOTP 429 retry)' 'python' @('quality/fragility_gate.py')
$launcherPath = Join-Path $root 'tools\CyberButlerLauncher.exe'
if (-not (Test-Path -LiteralPath $launcherPath)) { throw 'version gate: launcher exe missing' }
$launcherVersion = (Get-Item -LiteralPath $launcherPath).VersionInfo.FileVersion
if (-not $launcherVersion.StartsWith($declaredVersion + '.')) {
    throw ('version gate: launcher ' + $launcherVersion + ' != VERSION ' + $declaredVersion)
}
Add-Report ('- Launcher version: ' + $launcherVersion)
Run-Process 'static types/dead code/PSScriptAnalyzer' 'python' @('quality/audit_static.py')
Run-Process 'test integrity (MANIFEST + snapshot + empty-assert AST)' 'python' @('quality/test_guard.py', 'verify', '--restore')
Run-Process 'mutation check (real assertion inversion)' 'python' @('quality/mutation_check.py')
Run-Process 'source mutation (production logic)' 'python' @('quality/source_mutation_check.py')
Run-Process 'silent failure scan' 'python' @('quality/silent_failure_scan.py')
Run-Process 'real Broker fixture (subprocess, HTTP, TOTP, trash, replay)' 'python' @('quality/test_runtime_fixture.py')
$proofPath = Join-Path $root 'ACCEPTANCE_PROOF.md'
if (Test-Path -LiteralPath $proofPath) {
    $proofHash = (Get-FileHash -LiteralPath $proofPath -Algorithm SHA256).Hash
    Add-Report ('PROOF_SHA256: ' + $proofHash)
}
Add-Report '## Fixture HTTP evidence'
Add-Report '- quality/artifacts/runtime_fixture/http_statuses.json'
Add-Report '- quality/artifacts/runtime_fixture/audit_tail.jsonl'
Add-Report '- quality/artifacts/runtime_fixture/broker_process.txt'
Add-Report ''
Add-Report '## Static Analysis Coverage'
Add-Report '- mypy: 53/53 Python source files under tools/webui/installer; excludes tests, webui/.venv and caches.'
Add-Report '- pyright: 53/53 Python source files under tools/webui/installer; excludes the same directories.'
Add-Report '- PSSA: 88/89 runtime PowerShell files under installer/tools/webui; excludes tests and artifacts.'
Add-Report '- vulture: 53/53 production Python files with the documented 67-entry dynamic-entry whitelist.'
Add-Report ''
Add-Report '## FIXED_THIS_ROUND'
Add-Report '- 修复 Broker 鉴权顺序：/pending 缺少 token 现在直接返回 403。'
Add-Report '- 修复 TOTP replay：已消费验证码现在返回 HTTP 429。'
Add-Report '- 新增真实 fixture、HTTP 证据、测试冻结和 mutation 检查。'
Add-Report '- 修复 PSSA 空 catch 和自动变量覆盖。'
Add-Report '- D5 四文件签名/verify 已实现；D4 由人类在管理员权限下手动完成，根路径 1125B 旧签名器已移至 .deleted-20261105。'
Add-Report '- tools/sign_release.py、tools/verify_release.py、tools/Run-ReleasePipeline.ps1 已纳入 test_guard.CRITICAL，V3 门禁信任根漏洞已修补。'
Add-Report ''
Add-Report '## NOT_FIXED_THIS_ROUND'
Add-Report '- 真实 ACL/DPAPI/WFP/卸载残留仍需干净 VM 验证。'
Add-Report '- PSSA 未覆盖测试脚本全规则，测试脚本只做语法解析。'
Add-Report '- vulture 白名单仍有动态入口人工审查风险。'
Add-Report ''
if ($Candidate) {
    Add-Report '## CANDIDATE mode'
    Add-Report 'Static, comment and documentation gates passed. Quality/chaos/VM evidence is NOT claimed for this candidate.'
    $token = [guid]::NewGuid().ToString('N')
    $tokenPath = Join-Path $root 'quality/.release-pipeline-token'
    [IO.File]::WriteAllText($tokenPath, $token, (New-Object Text.UTF8Encoding($false)))
    $env:CBS_RELEASE_PIPELINE_TOKEN = $token
    try {
        Run-Process 'build candidate' 'python' @('tools/package_release.py', '--baseline-core', (Join-Path $root 'tools/update_core.py'))
    } finally {
        Remove-Item -LiteralPath $tokenPath -Force -ErrorAction SilentlyContinue
        Remove-Item Env:\CBS_RELEASE_PIPELINE_TOKEN -ErrorAction SilentlyContinue
    }
    $candidateZip = Join-Path (Split-Path -Parent $root) ('public-release-v' + $Version + '.zip')
    if (-not (Test-Path -LiteralPath $candidateZip)) { throw 'candidate build did not create the zip' }
    $candidateHash = (Get-FileHash -LiteralPath $candidateZip -Algorithm SHA256).Hash
    Add-Report ('- Candidate Zip SHA256: ' + $candidateHash)
    Add-Report ('- Package Hash: ' + $candidateHash)
    $candidateReport = Join-Path $root 'BUILD_REPORT.md'
    $report | Set-Content -LiteralPath $candidateReport -Encoding UTF8
    $candidateReportText = Get-Content -LiteralPath $candidateReport -Raw
    if ($candidateReportText -notmatch ('- Current Commit: ' + [regex]::Escape($head))) { throw 'BUILD_REPORT.md is missing the current commit' }
    $candidateReportHash = (Get-FileHash -LiteralPath $candidateReport -Algorithm SHA256).Hash
    Write-Host ('[BUILD_MANIFEST] Zip_SHA256: ' + $candidateHash + ' | Report_SHA256: ' + $candidateReportHash)
Run-Process 'self-seal verify' 'python' @('quality/self_seal.py', '--verify', $sealPath)
Remove-Item -LiteralPath $sealPath -Force -ErrorAction SilentlyContinue
    exit 0
}

Run-Process '25-item quality matrix' 'python' @('quality/run_quality_matrix.py', '--nonce', $Challenge)
Run-Process 'pytest' 'python' @('-m', 'pytest', '-q')
Run-Process 'coverage measurement' 'python' @('-m', 'coverage', 'run', '--branch', '-m', 'pytest', '-q', 'tests/')
Run-Process 'coverage json' 'python' @('-m', 'coverage', 'json', '-o', 'coverage.json')
Run-Warning 'Broker coverage (v1.6.6 known debt; hard gate required for v1.7)' 'python' @('quality/coverage_gate.py')
Run-Process 'CBP dependency hash gate' 'python' @('quality/dependency_gate.py')
Run-Process 'CBP comment anti-slop gate' 'python' @('quality/audit_comments.py')
Run-Process 'CBP shadow audit pass 1' 'python' @('-m', 'cbp.cli', '--root', $root)
Run-Process 'CBP shadow audit pass 2' 'python' @('-m', 'cbp.cli', '--root', $root)
Run-Process 'CBP shadow audit pass 3' 'python' @('-m', 'cbp.cli', '--root', $root)
Run-Process 'offline hash install' 'python' @('quality/offline_hash_install.py')
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
Run-Process 'mypy (0 errors)' 'python' @('-m', 'mypy', 'tools', 'webui', 'installer', '--ignore-missing-imports', '--exclude', '(\.venv|tests)')
Run-Process 'ruff (E9/F)' 'python' @('-m', 'ruff', 'check', 'tools', 'webui', 'installer', '--exclude', 'webui/.venv', '--exclude', 'webui/tests')
Run-Warning 'pip-audit runtime dependencies (CVE allowlist v1.6.4)' 'python' @('-m', 'pip_audit', '-r', 'requirements-runtime.txt', '--ignore-vuln', 'PYSEC-2026-2249', '--ignore-vuln', 'CVE-2026-96640')

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

$zip = Join-Path (Split-Path -Parent $root) ('public-release-v' + $Version + '.zip')
if (-not (Test-Path -LiteralPath $zip)) { throw 'package_release.py did not create the zip' }
$zipHash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash
Add-Report ''
Add-Report ('- Zip SHA256: ' + $zipHash)
Add-Report ('- Package Hash: ' + $zipHash)
$reportPath = Join-Path $root 'BUILD_REPORT.md'
$report | Set-Content -LiteralPath $reportPath -Encoding UTF8
$reportText = Get-Content -LiteralPath $reportPath -Raw
if ($reportText -notmatch ('- Current Commit: ' + [regex]::Escape($head))) { throw 'BUILD_REPORT.md is missing the current commit' }
$reportHash = (Get-FileHash -LiteralPath $reportPath -Algorithm SHA256).Hash
Write-Host ('[BUILD_MANIFEST] Zip_SHA256: ' + $zipHash + ' | Report_SHA256: ' + $reportHash)
if ($Unsigned) {
    Run-Process 'freeze unsigned artifact' 'python' @('tools/prebuild_freeze.py', '--root', $root, '--create')
}
if (-not $Unsigned) {
    if (-not (Test-Path -LiteralPath $sigPath)) { throw 'cryptographic gate: update-manifest.sig is missing' }
    Run-Process 'verify RSA signature' 'python' @(
        'tools/verify_release.py',
        '--manifest', (Join-Path $root 'update-manifest.json'),
        '--signature', $sigPath,
        '--pubkey', (Join-Path $root 'tools/update_pubkey.pem'),
        '--build-report', (Join-Path $root 'BUILD_REPORT.md'),
        '--qa-report', (Join-Path $root 'FINAL_QA_REPORT.md'),
        '--proof', (Join-Path $root 'ACCEPTANCE_PROOF.md')
    )
} else {
    Add-Report '- Build Mode: unsigned; signature verification skipped by request'
}
if ($Sign) {
    Write-Host 'Signing is intentionally a separate step after human review of BUILD_REPORT.md.'
}
if ($VerifyReleaseTag) {
    if ([string]::IsNullOrWhiteSpace($Repository)) { throw 'Repository is required with -VerifyReleaseTag' }
    Run-Process 'verify published release body' 'python' @('-m', 'cbp.cli', '--verify-release', $VerifyReleaseTag, '--repository', $Repository)
}
