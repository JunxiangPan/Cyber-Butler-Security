"""Checked-in release body must be subject to the same claims as generated notes."""
from __future__ import annotations

import json
from pathlib import Path

from cbp.claims_gate import run
from cbp.config import GateConfig


def _cfg(tmp_path: Path, body_text: str) -> GateConfig:
    (tmp_path / "quality-manifest.json").write_text(
        json.dumps({"counts": {"passed": 7, "total": 7}}), encoding="utf-8"
    )
    (tmp_path / "notes.md").write_text(
        "QUALITY_COUNTS: 7/7\nCBP is self-checked with all seven gates before a release.\n",
        encoding="utf-8",
    )
    (tmp_path / "body.md").write_text(body_text, encoding="utf-8")
    return GateConfig(
        root=tmp_path,
        claims_manifest="quality-manifest.json",
        claims_notes="notes.md",
        release_body="body.md",
    )


BODY = """# CBP v0.1.2

QUALITY_COUNTS: 7/7

CBP is self-checked with all seven gates before a release.
"""


def test_valid_body_passes(tmp_path: Path) -> None:
    assert run(_cfg(tmp_path, BODY))[0] is True


def test_false_first_release_claim_fails(tmp_path: Path) -> None:
    passed, detail = run(_cfg(tmp_path, BODY + "\nFirst public release.\n"))
    assert passed is False
    assert "First public release" in detail


def test_wrong_gate_word_fails(tmp_path: Path) -> None:
    passed, detail = run(_cfg(tmp_path, BODY.replace("seven", "six")))
    assert passed is False
    assert "six gates" in detail


def test_body_needs_quality_counts(tmp_path: Path) -> None:
    passed, detail = run(_cfg(tmp_path, BODY.replace("QUALITY_COUNTS: 7/7\n", "")))
    assert passed is False
    assert "QUALITY_COUNTS" in detail


def test_missing_body_file_fails(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path, BODY)
    cfg.release_body = "missing.md"
    passed, detail = run(cfg)
    assert passed is False and "release body missing" in detail


def test_body_wrong_counts_fails(tmp_path: Path) -> None:
    passed, detail = run(_cfg(tmp_path, BODY.replace("7/7", "6/7")))
    assert passed is False and "release body 6/7" in detail


def test_unknown_gate_word_fails(tmp_path: Path) -> None:
    passed, detail = run(_cfg(tmp_path, BODY.replace("seven", "eleven")))
    assert passed is False and "unknown gate count" in detail
