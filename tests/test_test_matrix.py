from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def test_light_real_machine_is_disclosed() -> None:
    import json
    status = json.loads((ROOT / "docs" / "_data" / "status-v1.6.3.json").read_text(encoding="utf-8"))
    assert status["version"] == "1.6.3"
    assert any("PR-41" in item for item in status["not_completed"])


def test_appcontainer_is_not_claimed() -> None:
    text = (ROOT / "docs" / "TEST_MATRIX.md").read_text(encoding="utf-8")
    assert "AppContainer is **not implemented**" in text
    threat = (ROOT / "THREAT_MODEL.md").read_text(encoding="utf-8")
    assert "does not" in threat and "AppContainer" in threat
