#!/usr/bin/env python3
"""P0-08: generate a sectioned Release body from artifact evidence."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def _hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def build(report: dict, wheel: Path, *, package: str = "cbs") -> str:
    status = report.get("gate_status", "FAIL")
    skip_count = int(report.get("skip_count", 0))
    skip_ratio = float(report.get("skip_ratio", 0.0))
    infra = report.get("infrastructure_failures", [])
    not_uploaded = report.get("not_uploaded", [])
    lines = [
        f"# {package} v{report.get('version', '?')} — Release evidence",
        "",
        "## Section A: Gate evidence (blocking)",
        "",
        f"- gate_status: **{status}**",
        f"- wheel: `{wheel.name}`",
        f"- wheel sha256: `{_hash(wheel)}`",
        f"- applicable checks: {report.get('applicable_count', report.get('applicable_gate_count', 0))}",
        f"- skipped: {skip_count} ({skip_ratio:.2%})",
        f"- blocking_skip: {str(report.get('blocking_skip', False)).lower()}",
        "",
    ]
    for gate in report.get("gates", []):
        lines.append(f"- {gate.get('name')}: {gate.get('status')}")
    lines += ["", "## Infrastructure failures", ""]
    lines += [f"- {item}" for item in infra] or ["- none"]
    lines += ["", "## NOT_UPLOADED", ""]
    lines += [f"- {item}" for item in not_uploaded] or ["- none"]
    lines += [
        "",
        "## Section B: AI audit (non-blocking)",
        "",
        "- AI gate results are audit-only; they do not replace Section A.",
        "",
        "## Honesty boundary",
        "",
        "CBE verifies the rule framework, CBP verifies evidence coherence. Neither",
        "proves that the code is secure. NOT_UPLOADED is not PASS, SKIPPED_INFRA is",
        "not PASS, and a green CI run is not a substitute for VM acceptance.",
    ]
    return "\n".join(lines) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--report", required=True)
    parser.add_argument("--wheel", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--package", default="cbs")
    args = parser.parse_args()
    report = json.loads(Path(args.report).read_text(encoding="utf-8"))
    Path(args.output).write_text(build(report, Path(args.wheel), package=args.package), encoding="utf-8")
    print("RELEASE_BODY_GENERATED", args.output)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
