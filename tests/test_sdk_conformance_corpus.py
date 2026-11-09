"""P0-2: conformance corpus shape for the Broker v1 client."""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CASES = json.loads((ROOT / "sdk" / "conformance" / "cases.json").read_text(encoding="utf-8"))


def test_conformance_corpus_has_three_endpoints() -> None:
    endpoints = {case["endpoint"] for case in CASES["cases"]}
    assert endpoints == {
        "POST /request",
        "GET /api/request_approval/status",
        "POST /verify",
    }


def test_each_case_has_required_fields() -> None:
    for case in CASES["cases"]:
        for field in case["required"]:
            assert field in case["input"], (case["name"], field)
