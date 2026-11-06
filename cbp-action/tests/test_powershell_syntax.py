from pathlib import Path

import pytest

from cbp import powershell_syntax


@pytest.mark.skipif(powershell_syntax.find_powershell() is None, reason="PowerShell is not installed")
def test_bad_powershell_is_rejected(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(powershell_syntax, "_EXCLUDED_PARTS", set())
    (tmp_path / "broken.ps1").write_text("if ($x -eq 1 { Write-Host 'broken' }\n", encoding="utf-8")
    ok, detail = powershell_syntax.check(tmp_path)
    assert ok is False
    assert "PS_SYNTAX_ERROR" in detail


@pytest.mark.skipif(powershell_syntax.find_powershell() is None, reason="PowerShell is not installed")
def test_valid_powershell_is_accepted(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setattr(powershell_syntax, "_EXCLUDED_PARTS", set())
    (tmp_path / "ok.ps1").write_text("$x = 1\nif ($x -eq 1) { Write-Host 'ok' }\n", encoding="utf-8")
    ok, detail = powershell_syntax.check(tmp_path)
    assert ok is True and "files=1" in detail
