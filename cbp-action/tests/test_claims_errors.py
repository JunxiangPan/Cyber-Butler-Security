"""Claims gate must distinguish a missing manifest from missing notes."""
from __future__ import annotations

from cbp.claims_gate import run
from cbp.config import GateConfig


def test_missing_manifest_has_actionable_message(tmp_path) -> None:
    cfg = GateConfig(
        root=tmp_path,
        claims_manifest="quality-manifest.json",
        claims_notes="docs/RELEASE_NOTES.generated.md",
    )
    passed, detail = run(cfg)
    assert passed is False
    assert "quality-manifest.json missing" in detail
    assert "dogfood_manifest.py" in detail
