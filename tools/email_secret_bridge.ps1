#Requires -Version 5.1
<#
Decrypt the machine-scope email configuration and emit it as JSON on stdout.

Only SYSTEM/Administrators can read email_secret.json. The broker calls this
bridge as SYSTEM; the plaintext exists only in memory and the child-process
pipe, never on disk or in a command line.
#>
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Security
$path = 'C:\ProgramData\CyberButler\email_secret.json'
$envelope = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
$entropy = [Text.Encoding]::UTF8.GetBytes([string]$envelope.entropy)
$cipher = [Convert]::FromBase64String([string]$envelope.ciphertext)
$plain = [Security.Cryptography.ProtectedData]::Unprotect(
    $cipher, $entropy, [Security.Cryptography.DataProtectionScope]::LocalMachine)
[Console]::Out.Write([Text.Encoding]::UTF8.GetString($plain))
