"""Negative and positive tests for the release artifact verifier."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

from tools import verify_manifest_artifact as verifier

RUN_ID = "42212006579"
COMMIT = "0b6b5012b6fe0164dada4e4935ab991edeb4602c"


def _fixture(tmp_path: Path) -> tuple[Path, Path, Path]:
    manifest = {
        "schema": "cbp-quality-manifest/v1",
        "profile": "dogfood",
        "ci_run_id": RUN_ID,
        "ci_commit_sha": COMMIT,
        "generated_at": "2026-11-06T00:00:00Z",
        "generated_by": "cbp-action dogfood job",
        "gates": {name: "PASS" for name in ("coverage", "dependency", "comments", "docs", "binary", "encoding", "claims")},
        "counts": {"passed": 7, "total": 7},
        "coverage": {"cbp": 87.0, "security_core": 96.0},
    }
    manifest_path = tmp_path / "quality-manifest.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    digest = hashlib.sha256(manifest_path.read_bytes()).hexdigest()
    hash_path = tmp_path / "quality-manifest.json.sha256"
    hash_path.write_text(f"{digest}  quality-manifest.json\n", encoding="utf-8")
    notes = tmp_path / "RELEASE_NOTES.generated.md"
    notes.write_text("QUALITY_COUNTS: 7/7\n", encoding="utf-8")
    return manifest_path, hash_path, notes


def _verify(paths: tuple[Path, Path, Path], run_id: str = RUN_ID, commit: str = COMMIT) -> dict:
    return verifier.verify(paths[0], paths[1], paths[2], run_id, commit)


def test_artifact_positive(tmp_path) -> None:
    assert _verify(_fixture(tmp_path))["counts"] == {"passed": 7, "total": 7}


def test_artifact_hash_mismatch_is_rejected(tmp_path) -> None:
    paths = _fixture(tmp_path)
    paths[1].write_text("0" * 64 + "  quality-manifest.json\n", encoding="utf-8")
    with pytest.raises(verifier.ArtifactError, match="hash mismatch"):
        _verify(paths)


def test_artifact_run_id_mismatch_is_rejected(tmp_path) -> None:
    with pytest.raises(verifier.ArtifactError, match="ci_run_id mismatch"):
        _verify(_fixture(tmp_path), run_id="999")


def test_artifact_commit_mismatch_is_rejected(tmp_path) -> None:
    with pytest.raises(verifier.ArtifactError, match="ci_commit_sha mismatch"):
        _verify(_fixture(tmp_path), commit="deadbeef")


def test_artifact_missing_notes_is_rejected(tmp_path) -> None:
    paths = _fixture(tmp_path)
    paths[2].unlink()
    with pytest.raises(verifier.ArtifactError, match="release notes missing"):
        _verify(paths)


def test_artifact_notes_count_mismatch_is_rejected(tmp_path) -> None:
    paths = _fixture(tmp_path)
    paths[2].write_text("QUALITY_COUNTS: 5/6\n", encoding="utf-8")
    with pytest.raises(verifier.ArtifactError, match="notes counts"):
        _verify(paths)
