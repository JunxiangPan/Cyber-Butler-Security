"""Claims must validate prose gate counts, not only the quality token."""
from __future__ import annotations

import json
from pathlib import Path

from cbp.claims_gate import run
from cbp.config import GateConfig


def _run(tmp_path: Path, phrase: str) -> tuple[bool, str]:
    (tmp_path / "quality-manifest.json").write_text(
        json.dumps({"counts": {"passed": 7, "total": 7}}), encoding="utf-8"
    )
    (tmp_path / "notes.md").write_text(
        f"QUALITY_COUNTS: 7/7\nCBP is self-checked with all {phrase} gates before a release.\n",
        encoding="utf-8",
    )
    return run(GateConfig(root=tmp_path, claims_manifest="quality-manifest.json", claims_notes="notes.md"))


def test_six_in_prose_is_rejected(tmp_path: Path) -> None:
    passed, detail = _run(tmp_path, "six")
    assert passed is False
    assert "six gates" in detail
    assert "manifest has 7" in detail


def test_seven_in_prose_is_accepted(tmp_path: Path) -> None:
    passed, detail = _run(tmp_path, "seven")
    assert passed is True
    assert "claims=7/7" in detail


def test_numeric_six_in_prose_is_rejected(tmp_path: Path) -> None:
    passed, detail = _run(tmp_path, "6")
    assert passed is False
    assert "6 gates" in detail
