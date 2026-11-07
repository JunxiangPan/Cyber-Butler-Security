"""Fixture-driven tests for CEL policy expressions."""
from __future__ import annotations

import json
from pathlib import Path

from .cel_policy import CelPolicyError, evaluate


def run_fixture(path: Path) -> tuple[bool, list[str]]:
    data = json.loads(path.read_text(encoding="utf-8"))
    failures: list[str] = []
    for case in data.get("cases", []):
        name = str(case.get("name", "case"))
        try:
            actual = evaluate(str(case["cel"]), dict(case.get("files", {})))
        except (KeyError, CelPolicyError) as exc:
            failures.append(f"{name}: {exc}")
            continue
        if actual != bool(case.get("expect")):
            failures.append(f"{name}: expected {case.get('expect')} got {actual}")
    return not failures, failures
