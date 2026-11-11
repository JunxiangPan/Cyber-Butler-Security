# A1 Q06: CBS service-account boundary (owner-approved redefinition; AgentRuntime external)
# Exit 0 only for a real PASS; exit 3 for blocked or failed prerequisites.
param(
    [string]$ArtifactZip = '',
    [string]$Nonce = '',
    [int]$TimeoutMinutes = 20
)
$ErrorActionPreference = 'Stop'
$InstallRoot = 'C:\CyberButler'
function Blocked([string]$reason) { Write-Output ('BLOCKED:' + $reason); exit 3 }
function Pass([string]$reason) { Write-Output ('PASS:' + $reason); exit 0 }
if (-not (Test-Path $InstallRoot)) { Blocked 'QA_VM_NOT_PROVISIONED' }
Import-Module Microsoft.PowerShell.LocalAccounts -ErrorAction SilentlyContinue
$user = Get-LocalUser -Name 'CyberButlerSvc' -ErrorAction SilentlyContinue
if (-not $user) { Blocked 'CYBERBUTLERSVC_MISSING' }
if (-not $user.Enabled) { Blocked 'CYBERBUTLERSVC_DISABLED' }
$sid = [string]$user.SID.Value
$admins = @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue)
$inAdmins = @($admins | Where-Object { [string]$_.SID.Value -eq $sid }).Count -gt 0
if ($inAdmins) { Blocked 'CYBERBUTLERSVC_IS_ADMIN' }
$cfg = Join-Path $env:TEMP ('cbs-a1-secedit-' + [Guid]::NewGuid().ToString('N') + '.inf')
try {
    & secedit.exe /export /areas USER_RIGHTS /cfg $cfg | Out-Null
    $rights = Get-Content -LiteralPath $cfg -Raw
    if ($rights -notmatch 'SeServiceLogonRight\s*=\s*[^\r\n]*CyberButlerSvc') {
        Blocked 'SE_SERVICE_LOGON_RIGHT_MISSING'
    }
} finally {
    if (Test-Path -LiteralPath $cfg) { Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue }
}
$acl = Get-Acl -LiteralPath $InstallRoot
$serviceAce = @($acl.Access | Where-Object {
    try { [string]$_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value -eq $sid } catch { $false }
})
if ($serviceAce.Count -eq 0) { Blocked 'CBS_DATA_ACL_MISSING_SERVICE_ACE' }
$agentService = Get-Service -Name 'CyberButlerAgentRuntime' -ErrorAction SilentlyContinue
if ($agentService) { Blocked 'CBS_HOLDS_AGENTRUNTIME_IDENTITY' }
Pass ('SID=' + $sid + ';ACL_ACES=' + $serviceAce.Count + ';SERVICE_LOGON=YES;AGENTRUNTIME=EXTERNAL')
