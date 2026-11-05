from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_light_real_machine_is_disclosed() -> None:
    text = (ROOT / "docs" / "TEST_MATRIX.md").read_text(encoding="utf-8")
    assert "Light" in text
    assert "real-machine" in text
    assert "not yet run" in text


def test_appcontainer_is_not_claimed() -> None:
    text = (ROOT / "docs" / "TEST_MATRIX.md").read_text(encoding="utf-8")
    assert "AppContainer is **not implemented**" in text
    threat = (ROOT / "THREAT_MODEL.md").read_text(encoding="utf-8")
    assert "does not" in threat and "AppContainer" in threat
