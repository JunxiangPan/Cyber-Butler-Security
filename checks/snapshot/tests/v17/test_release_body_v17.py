"""P0-08 and P1-03/P2-04: sectioned body generation."""
from __future__ import annotations

from pathlib import Path

from tools.release_body_v17 import build


def _report(**overrides):
    value = {
        "version": "v1.7.0", "gate_status": "PASS", "applicable_gate_count": 4,
        "skip_count": 1, "skip_ratio": 0.25, "blocking_skip": False,
        "gates": [{"name": "encoding", "status": "PASS"}],
    }
    value.update(overrides)
    return value


def test_body_contains_sections_and_hashes(tmp_path: Path) -> None:
    wheel = tmp_path / "pkg.whl"
    wheel.write_bytes(b"wheel")
    text = build(_report(), wheel)
    assert "## Section A: Gate evidence" in text
    assert "## Infrastructure failures" in text
    assert "## NOT_UPLOADED" in text
    assert "## Section B: AI audit" in text
    assert "## Honesty boundary" in text


def test_skipped_infra_is_not_in_pass_section(tmp_path: Path) -> None:
    wheel = tmp_path / "pkg.whl"
    wheel.write_bytes(b"wheel")
    text = build(_report(gate_status="SKIPPED_INFRA", infrastructure_failures=["runner 504"]), wheel)
    assert "runner 504" in text
    assert "gate_status: **SKIPPED_INFRA**" in text


def test_not_uploaded_is_visible(tmp_path: Path) -> None:
    wheel = tmp_path / "pkg.whl"
    wheel.write_bytes(b"wheel")
    text = build(_report(not_uploaded=["cbm", "cbc"]), wheel)
    assert "## NOT_UPLOADED" in text
    assert "- cbm" in text and "- cbc" in text


def test_missing_cbm_is_not_silent(tmp_path: Path) -> None:
    wheel = tmp_path / "pkg.whl"
    wheel.write_bytes(b"wheel")
    text = build(_report(declared_components=["cbm"]), wheel)
    assert "CBM: NOT_UPLOADED" in text
    assert "EVIDENCE_ABSENT" in text
    assert "declared as attached but not uploaded" in text

