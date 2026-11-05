"""Regression tests for historical low-level defects.

These are static source checks for the exact broken literals that previously
escaped review. They do not replace a live dashboard test.
"""
from __future__ import annotations

from pathlib import Path

import pytest

from win_path_guard import TargetGuardError, _reject_unsafe_path_text


def test_path_guard_rejects_newline_control_character() -> None:
    with pytest.raises(TargetGuardError):
        _reject_unsafe_path_text("C:/tmp/bad\nname")
