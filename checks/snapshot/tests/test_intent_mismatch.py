from __future__ import annotations

from pathlib import Path

import approval_preview


def test_test_reason_against_config_is_top_level_warning(tmp_path: Path):
    target = tmp_path / "settings" / "config.json"
    preview = approval_preview.build_preview(
        "write_file", str(target), content="x=1", reason="run tests and format css"
    )
    assert preview["intent_mismatch"] is True
    text = approval_preview.format_preview(preview)
    assert text.startswith("⚠️ INTENT MISMATCH: Agent claims [run tests and format css]")
    assert "but targets [" in text
    assert "malicious" not in text.lower()


def test_ui_reason_against_secret_is_warning(tmp_path: Path):
    target = tmp_path / "secrets" / "id_rsa"
    preview = approval_preview.build_preview(
        "write_file", str(target), content="x", reason="adjust the UI"
    )
    assert preview["intent_mismatch"] is True


def test_plain_reason_does_not_warn(tmp_path: Path):
    target = tmp_path / "notes" / "readme.md"
    preview = approval_preview.build_preview(
        "write_file", str(target), content="x", reason="write documentation"
    )
    assert preview["intent_mismatch"] is False
