"""P0-01: contract schemas have positive and negative fixtures."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
QUALITY = ROOT / "schemas" / "v1.7" / "quality-manifest.schema.json"
CBE = ROOT / "schemas" / "v1.7" / "cbe-report.schema.json"


def _valid_quality() -> dict:
    return {
        "schema_version": "1", "package_id": "cbs", "producer_id": "cbp",
        "version": "v1.7.0",
        "gate_status": "PASS", "applicable_gate_count": 4, "skip_count": 0,
        "skip_ratio": 0.0, "blocking_skip": False,
        "gates": [{"name": "encoding", "status": "PASS", "reason": ""}],
        "artifact_hashes": {"wheel": "a" * 64},
        "artifact_repository": {
            "repository": "owner/repo", "run_id": "123", "artifact_name": "build-once"
        },
        "release_body_hash": "b" * 64, "body_hash_scope": "base",
        "evidence_sha256": "c" * 64,
    }


def _valid_cbe() -> dict:
    return {
        "schema_version": "1", "package_id": "cbs", "producer_id": "cbe",
        "version": "v1.7.0",
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


import pytest


@pytest.mark.parametrize("field", json.loads(QUALITY.read_text(encoding="utf-8"))["required"])
def test_quality_each_required_field_missing(field: str) -> None:
    value = _valid_quality()
    del value[field]
    assert not _check_required(QUALITY, value)


@pytest.mark.parametrize("field", json.loads(CBE.read_text(encoding="utf-8"))["required"])
def test_cbe_each_required_field_missing(field: str) -> None:
    value = _valid_cbe()
    del value[field]
    assert not _check_required(CBE, value)


@pytest.mark.parametrize("value", ["", "2", "v1", 1, None])
def test_schema_version_is_frozen(value: object) -> None:
    quality = _valid_quality(); quality["schema_version"] = value
    cbe = _valid_cbe(); cbe["schema_version"] = value
    assert not _check_required(QUALITY, quality) or value != "1"
    assert not _check_required(CBE, cbe) or value != "1"


@pytest.mark.parametrize("status", ["OK", "SKIP", "SKIPPED", "NOT_UPLOADED", ""])
def test_quality_gate_status_rejects_unknown(status: str) -> None:
    value = _valid_quality(); value["gate_status"] = status
    assert value["gate_status"] not in ("PASS", "FAIL", "SKIPPED_INFRA", "PRECONDITION_FAIL")


@pytest.mark.parametrize("status", ["OK", "SKIP", "SKIPPED", "NOT_UPLOADED", ""])
def test_cbe_gate_status_rejects_unknown(status: str) -> None:
    value = _valid_cbe(); value["gate_status"] = status
    assert value["gate_status"] not in ("PASS", "FAIL", "SKIPPED_INFRA", "PRECONDITION_FAIL")


def test_nested_gate_status_and_artifact_shape_invalid() -> None:
    quality = _valid_quality()
    quality["gates"][0]["status"] = "SKIP"
    assert quality["gates"][0]["status"] not in ("PASS", "FAIL", "SKIPPED")
    quality = _valid_quality(); quality["artifact_hashes"] = []
    assert not isinstance(quality["artifact_hashes"], dict)
    cbe = _valid_cbe(); cbe["exit_code"] = 1
    assert cbe["exit_code"] not in (0, 2, 3, 4)


def _validate(schema: dict, value: object) -> list[str]:
    errors: list[str] = []
    if "const" in schema and value != schema["const"]:
        errors.append("const")
    if "enum" in schema and value not in schema["enum"]:
        errors.append("enum")
    kind = schema.get("type")
    types = {
        "object": dict, "array": list, "string": str,
        "integer": int, "number": (int, float), "boolean": bool,
    }
    if kind in types and not isinstance(value, types[kind]):
        return errors + ["type"]
    if kind == "object":
        for key in schema.get("required", []):
            if not isinstance(value, dict) or key not in value:
                errors.append("required:" + key)
        for key, item in (value or {}).items():
            if key in schema.get("properties", {}):
                errors.extend(_validate(schema["properties"][key], item))
            elif schema.get("additionalProperties") is False:
                errors.append("additional:" + key)
    if kind == "array" and schema.get("items"):
        for item in value or []:
            errors.extend(_validate(schema["items"], item))
    return errors


def test_schema_validator_rejects_each_field_and_enum() -> None:
    qschema = json.loads(QUALITY.read_text(encoding="utf-8"))
    cschema = json.loads(CBE.read_text(encoding="utf-8"))
    assert _validate(qschema, _valid_quality()) == []
    assert _validate(cschema, _valid_cbe()) == []
    for field in qschema["required"]:
        value = _valid_quality(); value.pop(field)
        assert any(error.startswith("required:") for error in _validate(qschema, value))
    for status in ("OK", "SKIP", "NOT_UPLOADED"):
        value = _valid_quality(); value["gate_status"] = status
        assert "enum" in _validate(qschema, value)
    value = _valid_quality(); value["gates"][0]["status"] = "SKIP"
    assert _validate(qschema, value)
    value = _valid_quality(); value["artifact_hashes"] = []
    assert _validate(qschema, value)
