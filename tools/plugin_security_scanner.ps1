#Requires -Version 5.1
<#
Cyber-Butler plugin security scanner.

Static, offline review of an AstrBot plugin package before it is installed.
It never executes the reviewed code. Findings carry a severity and a line
number; the installer blocks high findings unless the user explicitly
overrides after reading the report.

Used two ways:
  * dot-sourced by plugin_market.ps1 and the dashboard:
        . tools\plugin_security_scanner.ps1
        $report = Invoke-PluginSecurityScan -Path $dir
  * standalone:
        powershell -File tools\plugin_security_scanner.ps1 -Path $dir [-Json]
#>
param(
    [string]$Path = '',
    [switch]$Json,
    [ValidateSet('low', 'medium', 'high')]
    [string]$MinSeverity = 'low'
)

$script:ScannerRules = @(
    @{ Id = 'PY001'; Severity = 'high'; Pattern = '\beval\s*\('; Message = 'Dynamic code execution via eval()' },
    @{ Id = 'PY002'; Severity = 'high'; Pattern = '\bexec\s*\('; Message = 'Dynamic code execution via exec()' },
    @{ Id = 'PY003'; Severity = 'high'; Pattern = '\bos\.system\s*\('; Message = 'Shell command via os.system()' },
    @{ Id = 'PY004'; Severity = 'high'; Pattern = '\bos\.popen\s*\('; Message = 'Shell pipe via os.popen()' },
    @{ Id = 'PY005'; Severity = 'high'; Pattern = 'subprocess\.(run|call|Popen|check_output|check_call)\s*\([^)]*\bshell\s*=\s*True'; Message = 'subprocess with shell=True' },
    @{ Id = 'PY006'; Severity = 'high'; Pattern = '\b(ctypes\.(windll|CDLL|cdll)|WinDLL)\b'; Message = 'Native code loading via ctypes' },
    @{ Id = 'PY007'; Severity = 'medium'; Pattern = '\bwinreg\b'; Message = 'Windows registry access' },
    @{ Id = 'PY008'; Severity = 'medium'; Pattern = '\bshutil\.rmtree\s*\('; Message = 'Recursive directory deletion' },
    @{ Id = 'PY009'; Severity = 'medium'; Pattern = '\bos\.(remove|unlink|rename)\s*\('; Message = 'Direct filesystem modification' },
    @{ Id = 'PY010'; Severity = 'medium'; Pattern = '\bopen\s*\(\s*[rbf]?[''"]\s*(?:[A-Za-z]:\\\\|/(?:etc|usr|bin|sbin|var|root|boot)/)'; Message = 'Absolute system path access' },
    @{ Id = 'PY011'; Severity = 'medium'; Pattern = '\bpickle\.loads?\s*\('; Message = 'Unsafe deserialization with pickle' },
    @{ Id = 'PY012'; Severity = 'medium'; Pattern = '\byaml\.load\s*\('; Message = 'yaml.load() may allow object construction' },
    @{ Id = 'PY013'; Severity = 'medium'; Pattern = '\b__import__\s*\('; Message = 'Dynamic import' },
    @{ Id = 'PY014'; Severity = 'low'; Pattern = 'base64\.(b64decode|decodebytes)\s*\('; Message = 'Base64 decoding (check what it feeds)' },
    @{ Id = 'PY015'; Severity = 'low'; Pattern = '\brequests\.(post|put)\s*\('; Message = 'Outbound HTTP upload' },
    @{ Id = 'PY016'; Severity = 'low'; Pattern = '\bsocket\.socket\s*\('; Message = 'Raw socket creation' },
    @{ Id = 'PY017'; Severity = 'medium'; Pattern = '\bsubprocess\.(run|call|Popen|check_output|check_call)\s*\('; Message = 'External process execution' }
)

$script:SeverityRank = @{ low = 15; medium = 20; high = 30 }

function Invoke-PluginSecurityScan {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaxFiles = 800,
        [long]$MaxFileBytes = 2MB,
        [string]$MinSeverity = 'low'
    )

    $result = [pscustomobject]@{
        Path       = $Path
        ScannedAt  = (Get-Date).ToString('o')
        Files      = 0
        High       = 0
        Medium     = 0
        Low        = 0
        Verdict    = 'safe'
        Findings   = @()
        Skipped    = 0
        Error      = ''
    }

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        $result.Error = 'Package directory not found'
        $result.Verdict = 'error'
        return $result
    }

    $skipNames = @('__pycache__', '.git', '.venv', 'venv', 'node_modules', '.mypy_cache', '.pytest_cache')
    $files = New-Object System.Collections.ArrayList
    try {
        $all = @(Get-ChildItem -LiteralPath $Path -Recurse -File -Filter '*.py' -ErrorAction Stop)
        foreach ($file in $all) {
            if ($files.Count -ge $MaxFiles) { $result.Skipped++; continue }
            $relative = $file.FullName.Substring($Path.Length).TrimStart('\', '/')
            $parts = $relative -split '[\\/]'
            $skip = $false
            foreach ($part in $parts) {
                if ($skipNames -contains $part) { $skip = $true; break }
            }
            if ($skip) { continue }
            if ($file.Length -gt $MaxFileBytes) { $result.Skipped++; continue }
            [void]$files.Add($file)
        }
    } catch {
        $result.Error = $_.Exception.Message
        $result.Verdict = 'error'
        return $result
    }

    $findings = New-Object System.Collections.ArrayList
    $minimum = $script:SeverityRank[$MinSeverity]
    if (-not $minimum) { $minimum = 15 }

    foreach ($file in $files) {
        $result.Files++
        try {
            $lines = @(Get-Content -LiteralPath $file.FullName -Encoding UTF8 -ErrorAction Stop)
        } catch {
            $result.Skipped++
            continue
        }
        $relative = $file.FullName.Substring($Path.Length).TrimStart('\', '/')
        $hasBase64 = $false
        $hasExec = $false
        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            if ($line.Length -gt 4000) { $line = $line.Substring(0, 4000) }
            if ($line -match 'base64\.(b64decode|decodebytes)\s*\(') { $hasBase64 = $true }
            if ($line -match '\bexec\s*\(') { $hasExec = $true }
            foreach ($rule in $script:ScannerRules) {
                if ($script:SeverityRank[$rule.Severity] -lt $minimum) { continue }
                if ($line -match $rule.Pattern) {
                    [void]$findings.Add([pscustomobject]@{
                        RuleId   = $rule.Id
                        Severity = $rule.Severity
                        Message  = $rule.Message
                        File     = $relative
                        Line     = $index + 1
                        Code     = $line.Trim()
                    })
                }
            }
        }
        if ($hasBase64 -and $hasExec) {
            [void]$findings.Add([pscustomobject]@{
                RuleId   = 'PY900'
                Severity = 'high'
                Message  = 'Encoded payload passed to exec() in the same file'
                File     = $relative
                Line     = 1
                Code     = 'base64 decode + exec'
            })
        }
    }

    $result.Findings = @($findings | Sort-Object @{ Expression = { $script:SeverityRank[$_.Severity] }; Descending = $true }, File, Line)
    $result.High = @($result.Findings | Where-Object { $_.Severity -eq 'high' }).Count
    $result.Medium = @($result.Findings | Where-Object { $_.Severity -eq 'medium' }).Count
    $result.Low = @($result.Findings | Where-Object { $_.Severity -eq 'low' }).Count
    if ($result.High -gt 0) {
        $result.Verdict = 'unsafe'
    } elseif ($result.Medium -gt 0) {
        $result.Verdict = 'review'
    } else {
        $result.Verdict = 'safe'
    }
    return $result
}

function ConvertTo-ComparableVersion {
    param([string]$Text)
    if (-not $Text) { return $null }
    $clean = ($Text.Trim() -replace '^v', '') -replace '[^0-9.].*$', ''
    if (-not $clean) { return $null }
    $parts = @($clean -split '\.' | Where-Object { $_ -ne '' })
    while ($parts.Count -lt 2) { $parts += '0' }
    if ($parts.Count -gt 3) { $parts = @($parts[0], $parts[1], $parts[2]) }
    foreach ($part in $parts) {
        if ($part -notmatch '^\d+$') { return $null }
    }
    try { return [version]($parts -join '.') } catch { return $null }
}

function Test-AstrBotVersionSpec {
    param(
        [string]$Spec,
        [string]$Version
    )

    $result = [pscustomobject]@{ Ok = $true; Reason = '' }
    if (-not $Spec) {
        $result.Reason = 'plugin did not declare astrbot_version'
        return $result
    }
    if (-not $Version) {
        $result.Ok = $false
        $result.Reason = 'local AstrBot version is unknown'
        return $result
    }
    if ($Spec.Trim() -eq '*' -or $Spec.Trim() -eq '') { return $result }

    $local = ConvertTo-ComparableVersion $Version
    if (-not $local) {
        $result.Ok = $false
        $result.Reason = ("local version '{0}' is not numeric" -f $Version)
        return $result
    }

    foreach ($clause in ($Spec -split ',')) {
        $text = $clause.Trim()
        if (-not $text) { continue }
        if ($text -notmatch '^(>=|<=|==|!=|>|<|=)?\s*v?([0-9][0-9A-Za-z.\-]*)$') {
            $result.Ok = $false
            $result.Reason = ("unsupported version clause '{0}'" -f $text)
            return $result
        }
        $operator = if ($Matches[1]) { $Matches[1] } else { '==' }
        if ($operator -eq '=') { $operator = '==' }
        $requiredText = $Matches[2]
        $required = ConvertTo-ComparableVersion $requiredText
        if (-not $required) {
            $result.Ok = $false
            $result.Reason = ("plugin requires an invalid version '{0}'" -f $requiredText)
            return $result
        }
        $comparison = $local.CompareTo($required)
        $pass = switch ($operator) {
            '>=' { $comparison -ge 0 }
            '>' { $comparison -gt 0 }
            '<=' { $comparison -le 0 }
            '<' { $comparison -lt 0 }
            '==' { $comparison -eq 0 }
            '!=' { $comparison -ne 0 }
            default { $true }
        }
        if (-not $pass) {
            $result.Ok = $false
            $result.Reason = ("requires AstrBot {0}{1}, current {2}" -f $operator, $requiredText, $Version)
            return $result
        }
    }
    return $result
}

function Get-LocalAstrBotVersion {
    param([string]$ProjectRoot)
    if (-not $ProjectRoot) { return '' }
    $init = Join-Path $ProjectRoot 'AstrBot\astrbot\__init__.py'
    if (Test-Path -LiteralPath $init) {
        try {
            $text = Get-Content -LiteralPath $init -Raw -Encoding UTF8
            if ($text -match '__version__\s*=\s*["'']([^"'']+)["'']') { return $Matches[1] }
        } catch { }
    }
    return ''
}

if ($Path -and $MyInvocation.InvocationName -ne '.') {
    if (-not $Path) {
        Write-Output '用法：plugin_security_scanner.ps1 -Path <插件目录> [-Json] [-MinSeverity low|medium|high]'
        exit 2
    }
    $report = Invoke-PluginSecurityScan -Path $Path -MinSeverity $MinSeverity
    if ($Json) {
        $report | ConvertTo-Json -Depth 6
    } else {
        Write-Output ('VERDICT: ' + $report.Verdict + '  files=' + $report.Files + ' high=' + $report.High + ' medium=' + $report.Medium + ' low=' + $report.Low)
        foreach ($finding in $report.Findings) {
            Write-Output ('[{0}] {1} {2}:{3}  {4}' -f $finding.Severity.ToUpper(), $finding.RuleId, $finding.File, $finding.Line, $finding.Message)
            Write-Output ('    ' + $finding.Code)
        }
    }
    if ($report.Verdict -eq 'unsafe') { exit 2 }
    if ($report.Verdict -eq 'error') { exit 3 }
    exit 0
}
