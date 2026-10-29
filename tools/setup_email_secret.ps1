#Requires -RunAsAdministrator
#Requires -Version 5.1
<#
Configure the Cyber-Butler email approval channel.

Security properties:
  * Secrets are entered with Read-Host -AsSecureString in an elevated console;
    they never appear in command lines, logs, or the repository.
  * The SMTP/IMAP configuration is encrypted with DPAPI machine scope and
    written to C:\ProgramData\CyberButler\email_secret.json.
  * The file ACL is reset to SYSTEM (read) + Administrators (full) + the
    optional broker service account (read). The interactive user cannot read it.
  * A test email is sent after the file is written.

Run this only after rotating the mailbox authorization code.
#>
param(
    [string]$SmtpHost = 'smtp.163.com',
    [int]$SmtpPort = 465,
    [string]$SmtpUser = 'owner@example.com',
    [string]$ImapHost = 'imap.163.com',
    [int]$ImapPort = 993,
    [string]$AllowedSender = 'owner@example.com',
    [string]$BrokerAccount = 'SYSTEM',
    [string]$TargetDir = 'C:\ProgramData\CyberButler'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security

$statusPath = Join-Path $PSScriptRoot '..\..\tmp-plugins\email_setup_status.json'
$secretPath = Join-Path $TargetDir 'email_secret.json'

function Write-Status([bool]$Ok, [string]$Message) {
    try {
        $dir = Split-Path -Parent $statusPath
        if ($dir) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [ordered]@{
            ok         = $Ok
            message    = $Message
            secret     = $secretPath
            broker     = $BrokerAccount
            checked_at = (Get-Date).ToString('o')
        } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statusPath -Encoding UTF8
    } catch { }
}

try {
    Write-Host ''
    Write-Host '=== Cyber-Butler email approval setup ===' -ForegroundColor Cyan
    Write-Host 'ROTATE the mailbox authorization code first. Do not reuse a leaked code.'
    Write-Host ''
    Write-Host ('SMTP: {0}:{1}  user={2}' -f $SmtpHost, $SmtpPort, $SmtpUser)
    Write-Host ('IMAP: {0}:{1}  user={2}' -f $ImapHost, $ImapPort, $SmtpUser)
    Write-Host ('Allowed sender: {0}' -f $AllowedSender)
    Write-Host ''
    $secure = Read-Host -AsSecureString 'New SMTP/IMAP authorization code (input hidden)'
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        $password = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        if (-not $password) { throw 'empty authorization code' }

        $payload = [ordered]@{
            version         = 1
            smtp_host       = $SmtpHost
            smtp_port       = $SmtpPort
            smtp_security   = 'ssl'
            smtp_user       = $SmtpUser
            smtp_pass       = $password
            smtp_from       = $SmtpUser
            approval_to     = $AllowedSender
            imap_host       = $ImapHost
            imap_port       = $ImapPort
            imap_security   = 'ssl'
            imap_user       = $SmtpUser
            imap_pass       = $password
            imap_mailbox    = 'INBOX'
            allowed_sender  = $AllowedSender
            created_at      = (Get-Date).ToString('o')
        }
        $plain = [Text.Encoding]::UTF8.GetBytes(($payload | ConvertTo-Json -Depth 5))
        $entropy = [Text.Encoding]::UTF8.GetBytes('CyberButler.EmailSecret.v1')
        $cipher = [Security.Cryptography.ProtectedData]::Protect(
            $plain, $entropy, [Security.Cryptography.DataProtectionScope]::LocalMachine)

        New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
        $envelope = [ordered]@{
            version    = 1
            scope      = 'machine'
            entropy    = 'CyberButler.EmailSecret.v1'
            ciphertext = [Convert]::ToBase64String($cipher)
        }
        $envelope | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $secretPath -Encoding UTF8 -NoNewline

        # Replace inherited permissions: SYSTEM read, Administrators full,
        # broker account read. The interactive user is deliberately not listed.
        $grants = @('*S-1-5-18:(R)', '*S-1-5-32-544:(F)')
        if ($BrokerAccount -and $BrokerAccount -ne 'SYSTEM') { $grants += ($BrokerAccount + ':(R)') }
        & icacls.exe $secretPath /inheritance:r /grant:r $grants | Out-Null
        if ($LASTEXITCODE -ne 0) { throw ('icacls failed: ' + $LASTEXITCODE) }

        Write-Host ''
        Write-Host 'Encrypted configuration written; sending test email...' -ForegroundColor Yellow
        $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..')).Path
        $python = Join-Path $root 'AstrBot\.venv\Scripts\python.exe'
        $helper = Join-Path $PSScriptRoot 'send_email_stdin.py'
        if (-not (Test-Path -LiteralPath $python)) { throw ('python not found: ' + $python) }
        if (-not (Test-Path -LiteralPath $helper)) { throw ('email test helper missing: ' + $helper) }
        $payload | ConvertTo-Json -Depth 5 | & $python $helper
        if ($LASTEXITCODE -ne 0) { throw ('test email failed with exit ' + $LASTEXITCODE) }

        Write-Status $true 'encrypted config written; test email sent'
        Write-Host 'SUCCESS: test email sent.' -ForegroundColor Green
    } finally {
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        $password = $null
        $secure = $null
    }
} catch {
    Write-Status $false ($_.Exception.Message)
    Write-Host ('FAILED: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host 'If authentication failed, rotate the authorization code and run again.'
    exit 1
}
