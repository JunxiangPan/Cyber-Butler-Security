"""PowerShell AST syntax gate.

Windows CI and the Windows dogfood job have PowerShell available. The gate is
skipped on hosts without a PowerShell executable instead of pretending that
scripts were parsed.
"""
from __future__ import annotations

import shutil
import subprocess
import tempfile
from pathlib import Path

_EXCLUDED_PARTS = {".git", ".venv", "__pycache__", "node_modules", "qa-temp", "build"}


def find_powershell() -> str | None:
    for name in ("pwsh.exe", "pwsh", "powershell.exe", "powershell"):
        found = shutil.which(name)
        if found:
            return found
    return None


def _script(root: Path) -> str:
    escaped = str(root).replace("'", "''")
    return r"""$ErrorActionPreference = 'Stop'
$root = '""" + escaped + """'
$failed = $false
$files = @(Get-ChildItem -LiteralPath $root -Recurse -Filter '*.ps1' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch '[\\/](?:\.git|\.venv|__pycache__|node_modules|qa-temp|build)[\\/]' })
foreach ($file in $files) {
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    foreach ($parseError in @($errors)) {
        if ($null -eq $parseError) { continue }
        Write-Output ('PS_SYNTAX_ERROR ' + $file.FullName + ':' + $parseError.Extent.StartLineNumber + ':' + $parseError.Message)
        $failed = $true
    }
}
if ($failed) { exit 1 }
Write-Output ('PS_SYNTAX_OK files=' + $files.Count)
"""


def check(root: Path, timeout: int = 180) -> tuple[bool, str]:
    executable = find_powershell()
    if executable is None:
        return True, "powershell syntax skipped: no PowerShell executable"
    files = [p for p in root.rglob("*.ps1") if not (_EXCLUDED_PARTS & set(p.parts))]
    if not files:
        return True, "powershell syntax=0 files"
    with tempfile.NamedTemporaryFile("w", suffix=".ps1", encoding="utf-8", delete=False) as handle:
        handle.write(_script(root))
        script_path = handle.name
    try:
        result = subprocess.run(
            [executable, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", script_path],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return False, f"powershell syntax gate failed to run: {exc}"
    finally:
        try:
            Path(script_path).unlink()
        except OSError:
            pass
    output = (result.stdout + result.stderr).strip()
    if result.returncode != 0:
        lines = [line for line in output.splitlines() if line.startswith("PS_SYNTAX_ERROR")]
        return False, "powershell syntax FAIL " + ("; ".join(lines) if lines else output[-1000:])
    return True, f"powershell syntax=OK files={len(files)}"
