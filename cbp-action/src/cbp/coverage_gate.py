"""Generic coverage gate with independent enforce/warn groups."""
from __future__ import annotations

RULE_ID = "CBP-COV-001"

import hashlib
import json
import re
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import Any

from .config import GateConfig
from . import source_hash

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




def _lcov_files(text: str) -> dict[str, Any]:
    """Parse LCOV into the internal per-file coverage shape."""
    files: dict[str, Any] = {}
    current = ""
    statements: dict[str, int] = {}
    for line in text.splitlines():
        if line.startswith("SF:"):
            current = _norm(line[3:].strip())
            files.setdefault(current, {"summary": {}, "missing_lines": []})
            statements[current] = 0
        elif line.startswith("DA:") and current:
            body = line[3:].split(",", 1)
            if len(body) == 2 and body[0].isdigit():
                statements[current] = statements.get(current, 0) + 1
                if body[1].strip() == "0":
                    files[current]["missing_lines"].append(int(body[0]))
        elif line == "end_of_record" and current:
            files[current]["summary"] = {"num_statements": statements.get(current, 0)}
            current = ""
    return files


def _cobertura_files(text: str) -> dict[str, Any]:
    """Parse Cobertura XML into the internal per-file coverage shape."""
    root = ET.fromstring(text)
    files: dict[str, Any] = {}
    for node in root.iter():
        if node.tag.rsplit("}", 1)[-1] != "class":
            continue
        name = node.attrib.get("filename", "")
        if not name:
            continue
        missing: list[int] = []
        statements = 0
        for line in node:
            if line.tag.rsplit("}", 1)[-1] != "lines":
                continue
            for entry in line:
                if entry.tag.rsplit("}", 1)[-1] != "line":
                    continue
                statements += 1
                if entry.attrib.get("hits", "0") == "0" and entry.attrib.get("number", "").isdigit():
                    missing.append(int(entry.attrib["number"]))
        files[_norm(name)] = {"summary": {"num_statements": statements}, "missing_lines": missing}
    return files


def _load_coverage(path: Path) -> dict[str, Any]:
    """Read coverage.py JSON, LCOV, or Cobertura XML."""
    suffix = path.suffix.casefold()
    text = path.read_text(encoding="utf-8", errors="replace")
    if suffix == ".json":
        return json.loads(text)
    if suffix in {".lcov", ".info"} or text.startswith("TN:") or "SF:" in text:
        return {"files": _lcov_files(text), "format": "lcov"}
    if suffix == ".xml" or text.lstrip().startswith("<"):
        return {"files": _cobertura_files(text), "format": "cobertura"}
    raise ValueError(f"unsupported coverage format: {path.name}")

def _source_hash_problem(root: Path, data: dict) -> str:
    if data.get("format") in {"lcov", "cobertura"}:
        return ""
    files = source_hash.measured_files(root, data)
    expected = data.get("source_files_hash")
    if not expected:
        return "" if not files else "coverage.json has no source_files_hash; regenerate and stamp coverage"
    actual = source_hash.compute(root, files)
    if actual != expected:
        return "coverage.json is stale; source files have changed"
    return ""


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Check every configured coverage group and honor its mode."""
    coverage = cfg.path(cfg.coverage_json)
    allowlist = cfg.path(cfg.coverage_allowlist)
    if not coverage.is_file() or not allowlist.is_file():
        return False, "coverage.json or coverage_allowlist.json is missing"
    if getattr(cfg, "require_coverage_signature", False):
        signature = cfg.path(getattr(cfg, "coverage_signature", "") or (str(coverage) + ".sha256"))
        if not signature.is_file():
            return False, f"coverage signature missing: {signature}"
        parts = signature.read_text(encoding="utf-8").strip().split()
        actual = hashlib.sha256(coverage.read_bytes()).hexdigest()
        if not parts or parts[0].lower() != actual.lower():
            return False, "coverage signature mismatch"
    try:
        data = _load_coverage(coverage)
    except (ValueError, ET.ParseError, json.JSONDecodeError) as exc:
        return False, f"coverage file is unreadable: {exc}"
    allow = json.loads(allowlist.read_text(encoding="utf-8"))
    files = {_norm(str(key)): value for key, value in data["files"].items()}

    freshness = _source_hash_problem(cfg.root, data)
    if freshness:
        return False, freshness
    groups = getattr(cfg, "coverage_groups", ())
    ratchet: dict[str, float] = {}
    ratchet_path = cfg.path(getattr(cfg, "coverage_ratchet", "") or "")
    if ratchet_path.is_file():
        try:
            ratchet = {str(k): float(v) for k, v in json.loads(ratchet_path.read_text(encoding="utf-8")).items()}
        except (OSError, ValueError, TypeError) as exc:
            return False, f"coverage ratchet is unreadable: {exc}"
    if groups:
        ok = True
        details: list[str] = []
        for group in groups:
            mode = str(group.get("mode", "enforce")).lower()
            if mode not in {"enforce", "warn"}:
                return False, f"{group.get('name', 'unnamed')}: invalid mode {mode!r}"
            passed, detail, _missing = _group_stats(cfg, group, files, allow, data)
            name = str(group.get("name", "unnamed"))
            pct_match = re.search(r"=(\d+(?:\.\d+)?)%", detail)
            if passed and name in ratchet and pct_match and float(pct_match.group(1)) < ratchet[name]:
                passed = False
                detail = f"{name}={pct_match.group(1)}% below ratchet {ratchet[name]:.2f}%"
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
