"""Generic coverage gate."""
from __future__ import annotations

import json

from .config import GateConfig


def _norm(value: str) -> str:
    return value.replace("\\", "/")


def _allowed(ranges: list[dict]) -> set[int]:
    out: set[int] = set()
    for item in ranges:
        start, end = item["lines"]
        out.update(range(int(start), int(end) + 1))
    return out


def run(cfg: GateConfig) -> tuple[bool, str]:
    coverage = cfg.path(cfg.coverage_json)
    allowlist = cfg.path(cfg.coverage_allowlist)
    if not coverage.is_file() or not allowlist.is_file():
        return False, "coverage.json or coverage_allowlist.json is missing"
    data = json.loads(coverage.read_text(encoding="utf-8"))
    allow = json.loads(allowlist.read_text(encoding="utf-8"))
    files = {_norm(str(key)): value for key, value in data["files"].items()}
    policy = files.get(cfg.policy_file)
    if policy is None:
        return False, f"{cfg.policy_file} not measured"
    policy_pct = float(policy["summary"]["percent_covered"])
    if policy_pct < float(cfg.policy_threshold):
        return False, f"policy coverage {policy_pct:.2f}% < {cfg.policy_threshold:.2f}%"
    missing_total = 0
    statements = 0
    for relative in cfg.broker_files:
        entry = files.get(relative)
        if entry is None:
            return False, f"{relative} not measured"
        statements += int(entry["summary"]["num_statements"])
        allowed = _allowed(allow.get("files", {}).get(relative, []))
        missing_total += len([line for line in entry["missing_lines"] if line not in allowed])
    pct = (statements - missing_total) / statements * 100.0 if statements else 0.0
    if pct < float(cfg.coverage_threshold):
        return False, f"broker coverage {pct:.2f}% < {cfg.coverage_threshold:.2f}%"
    return True, f"coverage={pct:.2f}% policy={policy_pct:.2f}%"
