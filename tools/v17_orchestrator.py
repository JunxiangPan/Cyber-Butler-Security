#!/usr/bin/env python3
"""P0-07 mock-decoupled orchestration decision for the v1.7 release train."""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Decision:
    """A gate decision with an exit code and reasons."""
    exit_code: int
    gate_status: str
    publish: bool
    reasons: list[str]


def _gate(report: dict, name: str) -> list[str]:
    """Evaluate one gate result."""
    reasons = []
    status = report.get("gate_status")
    if status not in {"PASS", "FAIL", "SKIPPED_INFRA", "PRECONDITION_FAIL"}:
        reasons.append(f"{name}: invalid/missing gate_status -> input error")
        return reasons
    if status == "SKIPPED_INFRA":
        reasons.append(f"{name}: SKIPPED_INFRA")
    elif status != "PASS":
        reasons.append(f"{name}: {status}")
    if report.get("blocking_skip") is True:
        reasons.append(f"{name}: blocking_skip")
    if float(report.get("skip_ratio", 0.0)) > 0.20:
        reasons.append(f"{name}: skip_ratio > 0.20")
    return reasons


def decide(main_ci: str, cbe: dict, cbp: dict, tag_commit: str, ci_commit: str) -> Decision:
    """Return the ordered publish decision."""
    reasons: list[str] = []
    if main_ci != "success":
        return Decision(2, "PRECONDITION_FAIL", False, ["main CI is not success"])
    if not cbe or not cbp:
        return Decision(2, "PRECONDITION_FAIL", False, ["missing gate report"])
    if tag_commit != ci_commit:
        return Decision(2, "PRECONDITION_FAIL", False, ["tag commit != CI commit"])
    cbe_errors = _gate(cbe, "CBE")
    cbp_errors = _gate(cbp, "CBP")
    reasons.extend(cbe_errors + cbp_errors)
    if any("invalid/missing" in item for item in reasons):
        return Decision(2, "FAIL", False, reasons)
    if cbe.get("gate_status") == "SKIPPED_INFRA" or cbp.get("gate_status") == "SKIPPED_INFRA":
        return Decision(3, "SKIPPED_INFRA", False, reasons)
    if any("blocking_skip" in item for item in reasons):
        return Decision(3, "FAIL", False, reasons)
    if any("skip_ratio" in item for item in reasons):
        return Decision(4, "FAIL", False, reasons)
    if reasons:
        return Decision(3, "FAIL", False, reasons)
    return Decision(0, "PASS", True, [])
