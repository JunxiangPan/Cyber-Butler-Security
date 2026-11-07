"""Build a valid SARIF 2.1.0 document from gate details."""
from __future__ import annotations

import hashlib
import re
from pathlib import Path

SCHEMA = "https://json.schemastore.org/sarif-2.1.0.json"
RULE_IDS = {
    "encoding": "CBP-ENC-001",
    "coverage": "CBP-COV-001",
    "dependency": "CBP-DEP-001",
    "comments": "CBP-CMT-001",
    "docs": "CBP-DOC-001",
    "binary": "CBP-BIN-001",
    "claims": "CBP-CLM-001",
    "custom": "CBP-CST-001",
    "upgrade": "CBP-UPG-001",
}
LOCATION = re.compile(r"^(?P<file>[^:\n]+):(?P<line>\d+):\s*(?P<message>.+)$")
FILE_ONLY = re.compile(r"^(?P<file>[^:\n]+):\s*(?P<message>.+)$")


def _location(gate: str, line: str, root: Path) -> dict:
    match = LOCATION.match(line) or FILE_ONLY.match(line)
    if match:
        try:
            relative = Path(match.group("file")).resolve().relative_to(root.resolve()).as_posix()
        except (ValueError, OSError):
            relative = match.group("file").replace("\\", "/")
    else:
        relative = {"coverage": "coverage.json", "encoding": "repository"}.get(gate, "cbp.json")
    region = {"startLine": max(1, int(match.group("line"))) if LOCATION.match(line) else 1}
    return {
        "physicalLocation": {
            "artifactLocation": {"uri": relative},
            "region": region,
        }
    }


def _result(gate: str, line: str, root: Path, level: str = "error") -> dict:
    rule_id = RULE_IDS.get(gate, "CBP-UNKNOWN-001")
    message = line.strip() or gate + " gate failed"
    return {
        "ruleId": rule_id,
        "level": level,
        "message": {"text": message[:1000]},
        "locations": [_location(gate, line, root)],
        "partialFingerprints": {
            "primaryLocationLineHash": hashlib.sha256((gate + ":" + message).encode("utf-8")).hexdigest()[:16]
        },
    }


def build(gate_results: list[tuple[str, bool, str]], root: Path) -> dict:
    """Return one SARIF result per emitted finding, each with artifactLocation."""
    results = []
    for gate, passed, detail in gate_results:
        if passed and "WARN" not in detail:
            continue
        for line in detail.splitlines():
            line = line.strip()
            if not line or line.startswith("findings="):
                continue
            results.append(_result(gate, line, root, "warning" if passed else "error"))
    rules = []
    seen = set()
    for result in results:
        rule_id = result["ruleId"]
        if rule_id in seen:
            continue
        seen.add(rule_id)
        rules.append({
            "id": rule_id,
            "name": rule_id.lower(),
            "shortDescription": {"text": rule_id},
        })
    return {
        "$schema": SCHEMA,
        "version": "2.1.0",
        "runs": [{
            "tool": {"driver": {
                "name": "CBP",
                "informationUri": "https://github.com/marketplace/actions/cbp-coverage-and-build-policy",
                "rules": rules,
            }},
            "results": results,
        }],
    }
