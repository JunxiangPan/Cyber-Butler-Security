"""Media-component regression: Image/Record/Video paths must enter the TOTP chain.

This is a source-level guard for the overlay file, which imports the full
AstrBot runtime and is not importable in a lightweight CI environment. It
asserts that the generic path-component collection and owner fail-closed guard
remain present, preventing a return to the old Comp.File-only behavior.
"""

from __future__ import annotations

from pathlib import Path

SOURCE = (
    Path(__file__).resolve().parents[1]
    / "overlay"
    / "astrbot"
    / "core"
    / "tools"
    / "message_tools.py"
).read_text(encoding="utf-8")


def test_media_components_are_collected_together() -> None:
    assert "Comp.File" in SOURCE
    assert "Comp.Image" in SOURCE
    assert "Comp.Record" in SOURCE
    assert "Comp.Video" in SOURCE
    assert "path_components" in SOURCE
    assert "_totp_chain_risk(file_paths" in SOURCE


def test_owner_lookup_failure_is_fail_closed() -> None:
    assert "if not owner:" in SOURCE
    assert "无法确认文件所有者" in SOURCE
