"""RC2 conformance with the real JSON Schema engine and real fixture bytes."""
from __future__ import annotations

import copy
import json
from pathlib import Path

import pytest
from jsonschema import ValidationError, validate

from tools.body_hash import base_hash, base_bytes

ROOT = Path(__file__).resolve().parents[2]
QUALITY_SCHEMA = json.loads((ROOT / "schemas" / "v1.7" / "quality-manifest.schema.json").read_text(encoding="utf-8"))
CBE_SCHEMA = json.loads((ROOT / "schemas" / "v1.7" / "cbe-report.schema.json").read_text(encoding="utf-8"))
FIXTURES = ROOT / "tests" / "v17" / "fixtures"
REAL_CBE = json.loads((FIXTURES / "real-cbe-report.json").read_text(encoding="utf-8"))
REAL_CBP_121 = json.loads((FIXTURES / "real-cbp-1.2.1-manifest.json").read_text(encoding="utf-8"))
LEGACY_CBP = json.loads((FIXTURES / "legacy-cbp-1.2.0-manifest.json").read_text(encoding="utf-8"))
LEGACY_BODY = (FIXTURES / "legacy-cbm-body.md").read_bytes()


def test_real_cbe_report_passes_schema() -> None:
    validate(REAL_CBE, CBE_SCHEMA)


def test_legacy_cbp_manifest_fails_rc2_schema() -> None:
    with pytest.raises(ValidationError):
        validate(LEGACY_CBP, QUALITY_SCHEMA)


def test_real_cbp_1_2_1_still_fails_rc2_object_requirement() -> None:
    with pytest.raises(ValidationError):
        validate(REAL_CBP_121, QUALITY_SCHEMA)


def test_projected_rc2_cbp_manifest_shape_passes() -> None:
    projected = copy.deepcopy(LEGACY_CBP)
    projected["artifact_repository"] = {
        "repository": "JunxiangPan/cbp-action",
        "run_id": "run-rc2",
        "artifact_name": "cbp-rc",
    }
    projected["ci_commit_sha"] = "a" * 40
    projected["ci_run_id"] = "run-rc2"
    projected["generated_at"] = "2026-11-09T00:00:00Z"
    projected["generated_by"] = "cbp-1.2.1-projection"
    validate(projected, QUALITY_SCHEMA)


def test_schema_version_integer_is_rejected() -> None:
    bad = copy.deepcopy(REAL_CBE)
    bad["schema_version"] = 1
    with pytest.raises(ValidationError):
        validate(bad, CBE_SCHEMA)


def test_artifact_repository_string_is_rejected() -> None:
    bad = copy.deepcopy(LEGACY_CBP)
    bad["artifact_repository"] = "JunxiangPan/cbp-action"
    with pytest.raises(ValidationError):
        validate(bad, QUALITY_SCHEMA)


def test_ci_commit_sha_is_required() -> None:
    bad = copy.deepcopy(LEGACY_CBP)
    bad["artifact_repository"] = {"repository": "JunxiangPan/cbp-action", "run_id": "1", "artifact_name": "rc"}
    with pytest.raises(ValidationError):
        validate(bad, QUALITY_SCHEMA)


def test_not_uploaded_is_valid_but_not_pass() -> None:
    cbe = copy.deepcopy(REAL_CBE); cbe["gate_status"] = "NOT_UPLOADED"; validate(cbe, CBE_SCHEMA)
    cbp = copy.deepcopy(LEGACY_CBP); cbp["artifact_repository"] = {"repository": "JunxiangPan/cbp-action", "run_id": "1", "artifact_name": "rc"}; cbp["ci_commit_sha"] = "a" * 40; cbp["gate_status"] = "NOT_UPLOADED"; validate(cbp, QUALITY_SCHEMA)
    assert cbe["gate_status"] != "PASS" and cbp["gate_status"] != "PASS"


def test_body_hash_binding_legacy_fails_and_marker_can_pass() -> None:
    declared = LEGACY_CBP["release_body_hash"]
    assert base_hash(LEGACY_BODY) != declared
    body = b"base body line\n<!-- CBP-BODY-BASE-END -->\ntrailer\n"
    assert base_bytes(body) == b"base body line\n"
    manifest = copy.deepcopy(LEGACY_CBP)
    manifest["release_body_hash"] = base_hash(body)
    assert manifest["release_body_hash"] == base_hash(body)
    assert base_hash(b"base body line X\n<!-- CBP-BODY-BASE-END -->\ntrailer\n") != manifest["release_body_hash"]
