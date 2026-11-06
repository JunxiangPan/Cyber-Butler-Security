"""Dogfood manifest validation and anti-forgery tests."""
from __future__ import annotations

from pathlib import Path

import pytest

from tools import dogfood_manifest as dogfood


def _manifest() -> dict:
    return {
        "schema": "cbp-quality-manifest/v1",
        "profile": "dogfood",
        "ci_run_id": "1",
        "ci_commit_sha": "abc",
        "generated_at": "2026-11-06T00:00:00Z",
        "generated_by": "cbp-action dogfood job",
        "gates": {name: "PASS" for name in ("coverage", "dependency", "comments", "docs", "binary", "encoding", "claims", "custom", "upgrade")},
        "counts": {"passed": 9, "total": 9},
        "coverage": {"cbp": 80.0, "security_core": 90.0},
    }


def test_validate_manifest_positive() -> None:
    assert dogfood.validate_manifest(_manifest(), actions=True) == []


def test_validate_manifest_rejects_wrong_metadata() -> None:
    manifest = _manifest()
    manifest["gates"]["coverage"] = "FAIL"
    manifest["generated_by"] = "manual"
    problems = dogfood.validate_manifest(manifest, actions=True)
    assert any("gate statuses" in item for item in problems)
    assert any("generated_by" in item for item in problems)


def test_actions_mode_requires_run_id(monkeypatch) -> None:
    monkeypatch.setenv("GITHUB_ACTIONS", "true")
    monkeypatch.delenv("GITHUB_RUN_ID", raising=False)
    monkeypatch.setenv("GITHUB_SHA", "abc")
    with pytest.raises(dogfood.ManifestError):
        dogfood.generate(Path("."))
