"""P0-01: contract schemas have positive and negative fixtures."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUALITY = ROOT / "schemas" / "v1.7" / "quality-manifest.schema.json"
CBE = ROOT / "schemas" / "v1.7" / "cbe-report.schema.json"


def _valid_quality() -> dict:
    return {
        "schema_version": "1", "package_id": "cbs", "version": "v1.7.0",
        "gate_status": "PASS", "applicable_gate_count": 4, "skip_count": 0,
        "skip_ratio": 0.0, "blocking_skip": False,
        "gates": [{"name": "encoding", "status": "PASS", "reason": ""}],
        "artifact_hashes": {"wheel": "a" * 64},
        "release_body_hash": "b" * 64, "evidence_sha256": "c" * 64,
    }


def _valid_cbe() -> dict:
    return {
        "schema_version": "1", "package_id": "cbe", "version": "v1.7.0",
        "tag": "v1.7.0", "gate_status": "PASS", "exit_code": 0,
        "applicable_count": 4, "skip_count": 0, "skip_ratio": 0.0,
        "blocking_skip": False, "warn_count": 0,
        "rules_manifest_hash": "a" * 64, "sarif_paths": ["out.sarif"],
        "evidence_sha256": "b" * 64,
    }


def _check_required(schema_path: Path, value: dict) -> bool:
    schema = json.loads(schema_path.read_text(encoding="utf-8"))
    return all(key in value for key in schema["required"])


def test_quality_schema_accepts_valid_and_rejects_missing() -> None:
    assert _check_required(QUALITY, _valid_quality())
    broken = _valid_quality()
    del broken["skip_ratio"]
    assert not _check_required(QUALITY, broken)


def test_cbe_schema_accepts_valid_and_rejects_missing() -> None:
    assert _check_required(CBE, _valid_cbe())
    broken = _valid_cbe()
    del broken["blocking_skip"]
    assert not _check_required(CBE, broken)


def test_gate_status_enum_is_frozen() -> None:
    for path in (QUALITY, CBE):
        schema = json.loads(path.read_text(encoding="utf-8"))
        assert set(schema["properties"]["gate_status"]["enum"]) == {
            "PASS", "FAIL", "SKIPPED_INFRA", "PRECONDITION_FAIL",
        }
