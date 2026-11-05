"""Regression tests for historical low-level defects.

These are static source checks for the exact broken literals that previously
escaped review. They do not replace a live dashboard test.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from win_path_guard import TargetGuardError, _reject_unsafe_path_text


def test_dashboard_error_redaction_uses_real_word_boundaries() -> None:
    source = (Path(__file__).resolve().parents[1] / "tools" / "dashboard_errors.ps1").read_text(encoding="utf-8-sig")
    assert r"\bAuthorization" in source
    assert r"\bBearer" in source
    assert "\x08" not in source


def test_dashboard_dangerous_command_patterns_use_word_boundaries() -> None:
    source = (Path(__file__).resolve().parents[1] / "tools" / "dashboard_modules.ps1").read_text(encoding="utf-8-sig")
    for pattern in (r"\brm\b", r"\bdel\b", r"\biex\b"):
        assert pattern in source
    assert "\x08" not in source


def test_path_guard_rejects_newline_control_character() -> None:
    with pytest.raises(TargetGuardError):
        _reject_unsafe_path_text("C:/tmp/bad\nname")
