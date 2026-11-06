"""Generic coverage gate with independent enforce/warn groups."""
from __future__ import annotations

RULE_ID = "CBP-COV-001"

import json
from pathlib import Path
from typing import Any

from .config import GateConfig

SKIP_PARTS = {".venv", "site-packages", "node_modules", "__pycache__", ".git"}


def _norm(value: str) -> str:
    return value.replace("\\", "/")


def _allowed(ranges: list[dict]) -> set[int]:
    out: set[int] = set()
    for item in ranges:
        start, end = item["lines"]
        out.update(range(int(start), int(end) + 1))
    return out


def _expand_files(cfg: GateConfig, patterns: list[str]) -> list[str]:
    """Expand glob patterns and keep only measured-looking Python files."""
    found: list[str] = []
    for pattern in patterns:
        text = str(pattern).replace("\\", "/")
        if any(char in text for char in "*?["):
            for path in sorted(cfg.root.glob(text)):
                if path.is_file() and path.suffix == ".py" and not (set(path.parts) & SKIP_PARTS):
                    found.append(_norm(str(path.relative_to(cfg.root))))
        else:
            found.append(text)
    return list(dict.fromkeys(found))


def _group_stats(
    cfg: GateConfig,
    group: dict[str, Any],
    files: dict[str, Any],
    allow: dict[str, Any],
    coverage_data: dict[str, Any],
) -> tuple[bool, str, list[str]]:
    raw_files = group.get("files", [])
    if isinstance(raw_files, str):
        raw_files = [raw_files]
    expected = _expand_files(cfg, list(raw_files))
    if not expected:
        return False, f"{group.get('name', 'unnamed')}: no files configured", []
    statements = 0
    missing_total = 0
    missing_files: list[str] = []
    for relative in expected:
        entry = files.get(_norm(relative))
        if entry is None:
            missing_files.append(relative)
            continue
        statements += int(entry["summary"]["num_statements"])
        allowed = _allowed(allow.get("files", {}).get(relative, []))
        missing_total += len([line for line in entry["missing_lines"] if line not in allowed])
    if not statements:
        return False, f"{group.get('name', 'unnamed')}: no measured statements", missing_files
    pct = (statements - missing_total) / statements * 100.0
    threshold = float(group.get("threshold", 0))
    passed = pct >= threshold and not missing_files
    detail = f"{group.get('name', 'unnamed')}={pct:.2f}%/{threshold:.2f}%"
    if missing_files:
        detail += " missing=" + ",".join(missing_files[:3])
    return passed, detail, missing_files


def _coverage_is_fresh(cfg: GateConfig, coverage: Path, relative_files: list[str]) -> str:
    sources = [cfg.path(relative) for relative in relative_files if cfg.path(relative).is_file()]
    if not sources:
        return ""
    newest = max(path.stat().st_mtime for path in sources)
    if coverage.stat().st_mtime < newest:
        return "coverage.json is older than the measured source; regenerate coverage"
    return ""


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Check every configured coverage group and honor its mode."""
    coverage = cfg.path(cfg.coverage_json)
    allowlist = cfg.path(cfg.coverage_allowlist)
    if not coverage.is_file() or not allowlist.is_file():
        return False, "coverage.json or coverage_allowlist.json is missing"
    data = json.loads(coverage.read_text(encoding="utf-8"))
    allow = json.loads(allowlist.read_text(encoding="utf-8"))
    files = {_norm(str(key)): value for key, value in data["files"].items()}

    groups = getattr(cfg, "coverage_groups", ())
    tracked_targets: list[str] = []
    if groups:
        for group in groups:
            raw = group.get("files", [])
            if isinstance(raw, str):
                raw = [raw]
            tracked_targets.extend(_expand_files(cfg, list(raw)))
    else:
        tracked_targets = list(cfg.target_files)
    freshness = _coverage_is_fresh(cfg, coverage, tracked_targets)
    if freshness:
        return False, freshness
    if groups:
        ok = True
        details: list[str] = []
        for group in groups:
            mode = str(group.get("mode", "enforce")).lower()
            if mode not in {"enforce", "warn"}:
                return False, f"{group.get('name', 'unnamed')}: invalid mode {mode!r}"
            passed, detail, _missing = _group_stats(cfg, group, files, allow, data)
            if passed:
                details.append(detail)
            elif mode == "enforce":
                ok = False
                details.append("FAIL " + detail)
            else:
                details.append("WARN " + detail)
        return ok, "; ".join(details)

    # Legacy single-file shape kept for existing consumers.
    policy = files.get(_norm(cfg.policy_file))
    if policy is None:
        return False, f"{cfg.policy_file} not measured"
    policy_pct = float(policy["summary"]["percent_covered"])
    if policy_pct < float(cfg.policy_threshold):
        return False, f"policy coverage {policy_pct:.2f}% < {cfg.policy_threshold:.2f}%"
    missing_total = 0
    statements = 0
    for relative in cfg.target_files:
        entry = files.get(_norm(relative))
        if entry is None:
            return False, f"{relative} not measured"
        statements += int(entry["summary"]["num_statements"])
        allowed = _allowed(allow.get("files", {}).get(relative, []))
        missing_total += len([line for line in entry["missing_lines"] if line not in allowed])
    pct = (statements - missing_total) / statements * 100.0 if statements else 0.0
    if pct < float(cfg.coverage_threshold):
        return False, f"target coverage {pct:.2f}% < {cfg.coverage_threshold:.2f}%"
    return True, f"coverage={pct:.2f}% policy={policy_pct:.2f}%"
