# A1 Q16: offline wheelhouse on Python-free clean Windows
# Exit 0 only for a real pass. Exit 3 is blocked; never exit 0 on a skip.
param(
    [string]$ArtifactZip = '',
    [string]$Nonce = '',
    [int]$TimeoutMinutes = 20
)
$ErrorActionPreference = 'Stop'
function Blocked([string]$reason) {
    Write-Output ('BLOCKED:' + $reason)
    exit 3
}
if (-not (Test-Path 'C:\CyberButler\VERSION')) {
    Blocked 'QA_VM_NOT_PROVISIONED'
}
if (-not (Test-Path $ArtifactZip) -and $ArtifactZip) {
    Blocked 'ARTIFACT_ZIP_MISSING'
}
# The real Q16 harness is intentionally not faked. It needs the installed CBS
# service and the Q-specific fixture from the A1 plan.
Blocked 'ADAPTER_SCAFFOLD_ONLY'
