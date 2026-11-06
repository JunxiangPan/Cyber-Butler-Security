"""Build a minimal valid SARIF 2.1.0 document from gate details."""
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
}
LOCATION = re.compile(r"^(?P<file>[^:\n]+):(?P<line>\d+):\s*(?P<message>.+)$")


def _result(gate: str, detail: str, root: Path, level: str = "error") -> dict:
    rule_id = RULE_IDS.get(gate, "CBP-UNKNOWN-001")
    lines = [line.strip() for line in detail.splitlines() if line.strip()]
    message = " / ".join(lines) if lines else gate + " gate failed"
    result = {
        "ruleId": rule_id,
        "level": level,
        "message": {"text": message[:1000]},
        "partialFingerprints": {
            "primaryLocationLineHash": hashlib.sha256((gate + ":" + message).encode("utf-8")).hexdigest()[:16]
        },
    }
    match = LOCATION.match(lines[0]) if lines else None
    if match:
        try:
            relative = Path(match.group("file")).resolve().relative_to(root.resolve()).as_posix()
        except (ValueError, OSError):
            relative = match.group("file").replace("\\", "/")
        result["locations"] = [{
            "physicalLocation": {
                "artifactLocation": {"uri": relative},
                "region": {"startLine": max(1, int(match.group("line")))},
            }
        }]
    return result


def build(gate_results: list[tuple[str, bool, str]], root: Path) -> dict:
    """Return a SARIF 2.1.0 document for all failed gates."""
    results = [
        _result(gate, detail, root, "warning" if passed else "error")
        for gate, passed, detail in gate_results
        if not passed or "WARN" in detail
    ]
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
