"""P0-2: Broker v1 schema fixtures are parseable and closed."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCHEMAS = ROOT / "schemas" / "broker" / "v1"


def _load(name: str) -> dict:
    return json.loads((SCHEMAS / name).read_text(encoding="utf-8"))


def test_request_schema_requires_action_and_target() -> None:
    schema = _load("request.schema.json")
    assert schema["required"] == ["action", "target"]
    assert schema["additionalProperties"] is False
    assert set(schema["properties"]["action"]["enum"]) == {
        "delete", "overwrite", "write_file", "send",
    }


def test_verify_schema_requires_six_digit_code() -> None:
    schema = _load("verify.schema.json")
    assert schema["required"] == ["id", "code"]
    assert schema["properties"]["code"]["pattern"] == "^[0-9]{6}$"


def test_status_schema_has_known_states() -> None:
    schema = _load("approval-status.schema.json")
    assert "scoped_token" in schema["properties"]
    assert set(schema["properties"]["status"]["enum"]) == {
        "pending", "approved", "denied", "expired", "unknown",
    }
