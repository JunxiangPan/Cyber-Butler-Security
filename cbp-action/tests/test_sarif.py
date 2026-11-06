"""SARIF output must remain valid even when no gate fails."""
from __future__ import annotations

import json
from pathlib import Path

from cbp import sarif


def test_sarif_empty_results() -> None:
    document = sarif.build([("coverage", True, "coverage=100%")], Path("."))
    assert document["version"] == "2.1.0"
    assert document["runs"][0]["results"] == []


def test_sarif_failure_has_location() -> None:
    document = sarif.build([("comments", False, "src/example.py:12: slop comment")], Path("."))
    result = document["runs"][0]["results"][0]
    assert result["ruleId"] == "CBP-CMT-001"
    assert result["level"] == "error"
    assert result["locations"][0]["physicalLocation"]["artifactLocation"]["uri"] == "src/example.py"
    assert result["locations"][0]["physicalLocation"]["region"]["startLine"] == 12
    json.dumps(document)


def test_sarif_without_location_and_duplicate_rule() -> None:
    document = sarif.build([
        ("coverage", False, "coverage below threshold"),
        ("coverage", False, "coverage below threshold again"),
    ], Path("."))
    assert len(document["runs"][0]["results"]) == 2
    assert len(document["runs"][0]["tool"]["driver"]["rules"]) == 1
