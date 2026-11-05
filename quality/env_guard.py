#!/usr/bin/env python3
"""Reject tests that depend on author-machine paths or core ports."""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGETS = [*sorted((ROOT / "quality" / "tests").glob("*.py")), *sorted((ROOT / "tests").glob("*.py"))]
ALLOW = {"test_broker_workspace_policy.py"}
CORE_PORTS = re.compile(r"\b(?:18090|8765)\b")
LOCAL_TOKENS = ("C:/Users", "D:/qq", "C:/CyberButler")


def main() -> int:
    findings: list[str] = []
    for path in TARGETS:
        if path.name in ALLOW or path.name == "test_quality_matrix.py":
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for token in LOCAL_TOKENS:
            if token in text:
                findings.append(f"{path.relative_to(ROOT)}: local absolute path {token}")
        if "socket" in text and CORE_PORTS.search(text):
            findings.append(f"{path.relative_to(ROOT)}: test binds a core broker/webui port")
    if findings:
        print("ENV_GATE_FAILED")
        for item in findings:
            print("  " + item)
        return 1
    print("ENV_GATE_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
