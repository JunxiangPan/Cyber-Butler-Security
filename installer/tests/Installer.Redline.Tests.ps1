$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

Describe 'CBS release red lines' {
    It 'directory delete is rejected before snapshot' {
        $source = Get-Content -LiteralPath (Join-Path $root 'tools\broker.py') -Raw
        $source | Should Match 'action == "delete" and target\.is_dir\(\)'
        $source | Should Match 'directory deletion is not supported'
    }

    It 'verify does not read caller scoped_minutes' {
        $source = Get-Content -LiteralPath (Join-Path $root 'tools\broker.py') -Raw
        $source | Should Not Match 'payload\.get\("scoped_minutes"'
        $source | Should Match 'caller-supplied scoped_minutes is deliberately ignored'
    }

    It 'critical integrity is scoped under the CBS root' {
        $source = Get-Content -LiteralPath (Join-Path $root 'tools\broker.py') -Raw
        $source | Should Match 'path\.relative_to\(root\)'
    }

    It 'service shell observes child exit' {
        $source = Get-Content -LiteralPath (Join-Path $root 'installer\service\CyberButlerAgentRuntimeService.cs') -Raw
        $source | Should Match 'child\.Exited \+= ChildExited'
        $source | Should Match 'SERVICE_CHILD_EXIT'
        $source | Should Match 'CREATE_SUSPENDED'
        $source | Should Match 'ResumeThread'
    }

    It 'pending and trash require the broker token' {
        $source = Get-Content -LiteralPath (Join-Path $root 'tools\broker.py') -Raw
        $source | Should Match 'parsed\.path == "/pending"'
        $source | Should Match 'parsed\.path == "/trash"'
        $source | Should Match 'if not self\._auth\(\)'
    }

    It 'installer grants desktop read to the broker token' {
        $source = Get-Content -LiteralPath (Join-Path $root 'installer\Install-CyberButler.ps1') -Raw
        $source | Should Match '\$tokenReaders'
        $source | Should Match '\$DesktopAccount'
        $source | Should Match '\(R\)'
    }
}
