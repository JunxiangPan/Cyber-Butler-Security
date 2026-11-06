#!/usr/bin/env python3
"""Audit CBP rule declarations, registry entries, changelog rows, and tests."""
from __future__ import annotations

import argparse
import ast
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Any

TIMEOUT_SECONDS = 60
RULE_CONSTANT = "RULE_ID"
SKIP_DIRS = {"__pycache__", ".venv", "site-packages", "node_modules", ".git"}


def _normalize_node(value: str) -> str:
    return value.replace("\\", "/")


def _valid_rule_id(value: str) -> bool:
    if not value.startswith("CBP-"):
        return False
    parts = value[4:].split("-")
    return len(parts) == 2 and parts[0].isalnum() and parts[1].isdigit() and len(parts[1]) == 3


def _valid_node(value: str) -> bool:
    if "\\" in value:
        return False
    path, separator, test = value.partition("::")
    return bool(path.endswith(".py") and separator and test and "::" not in test)


def _module_rule_ids(source_dir: Path) -> tuple[dict[str, str], list[str]]:
    found: dict[str, str] = {}
    errors: list[str] = []
    for path in sorted(source_dir.rglob("*.py")):
        if set(path.parts) & SKIP_DIRS:
            continue
        try:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
        except (SyntaxError, UnicodeDecodeError) as exc:
            errors.append(f"ERROR parse {path}: {exc}")
            continue
        for node in tree.body:
            if not isinstance(node, ast.Assign):
                continue
            if len(node.targets) != 1 or not isinstance(node.targets[0], ast.Name):
                continue
            if node.targets[0].id != RULE_CONSTANT:
                continue
            if not isinstance(node.value, ast.Constant) or not isinstance(node.value.value, str):
                errors.append(f"ERROR {path}: {RULE_CONSTANT} must be a string literal")
                continue
            rule_id = node.value.value
            if not _valid_rule_id(rule_id):
                errors.append(f"ERROR {path}: invalid rule id {rule_id!r}")
                continue
            if rule_id in found:
                errors.append(f"Duplicate rule id: {rule_id}")
            found[rule_id] = str(path)
    return found, errors


def _load_registry(path: Path) -> tuple[list[dict[str, Any]], list[str]]:
    errors: list[str] = []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as exc:
        return [], [f"ERROR registry: {exc}"]
    rules = data.get("rules") if isinstance(data, dict) else None
    if not isinstance(rules, list) or not rules:
        return [], ["ERROR registry: rules must be a non-empty array"]
    known: dict[str, dict[str, Any]] = {}
    for rule in rules:
        if not isinstance(rule, dict):
            errors.append("ERROR registry: rule must be an object")
            continue
        rule_id = rule.get("id")
        if not isinstance(rule_id, str) or not _valid_rule_id(rule_id):
            errors.append(f"ERROR registry: invalid rule id {rule_id!r}")
            continue
        if rule_id in known:
            errors.append(f"ERROR registry: duplicate rule id {rule_id}")
        source = rule.get("source")
        if not isinstance(source, dict) or not all(
            isinstance(source.get(key), str) and source.get(key) for key in ("project", "pr", "issue")
        ):
            errors.append(f"ERROR registry {rule_id}: source.project/pr/issue must be non-empty")
        for key in ("negative_test", "positive_test"):
            value = rule.get(key)
            if not isinstance(value, str) or not _valid_node(value):
                errors.append(f"ERROR registry {rule_id}: {key} must be path::test")
        if rule.get("status") not in {"active", "deprecated"}:
            errors.append(f"ERROR registry {rule_id}: status must be active or deprecated")
        known[rule_id] = rule
    return rules, errors


def _load_changelog(path: Path) -> tuple[dict[str, dict[str, str]], list[str]]:
    errors: list[str] = []
    rows: dict[str, dict[str, str]] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        return {}, [f"ERROR changelog: {exc}"]
    header: list[str] | None = None
    for line in lines:
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [cell.strip() for cell in stripped.strip("|").split("|")]
        if header is None:
            if cells and cells[0] == "Rule ID":
                header = cells
            continue
        if all(set(cell) <= {"-", ":", " "} for cell in cells):
            continue
        if len(cells) != len(header):
            errors.append(f"ERROR changelog: malformed row {stripped}")
            continue
        row = dict(zip(header, cells))
        rule_id = row.get("Rule ID", "")
        if not _valid_rule_id(rule_id):
            errors.append(f"ERROR changelog: invalid rule id {rule_id!r}")
            continue
        if rule_id in rows:
            errors.append(f"ERROR changelog: duplicate rule id {rule_id}")
        rows[rule_id] = row
    if header is None:
        errors.append("ERROR changelog: missing Rule ID table")
    return rows, errors


def _run_node(root: Path, node: str, collect: bool, basetemp: str) -> tuple[bool, str, int | None]:
    normalized = _normalize_node(node)
    command = [sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider", "--basetemp", basetemp]
    if collect:
        command.append("--collect-only")
    command.append(normalized)
    try:
        result = subprocess.run(
            command,
            cwd=root,
            capture_output=True,
            text=True,
            timeout=TIMEOUT_SECONDS,
        )
    except subprocess.TimeoutExpired:
        return False, "timeout", None
    except OSError as exc:
        return False, f"launch error: {exc}", None
    output = _normalize_node((result.stdout or "") + "\n" + (result.stderr or ""))
    if collect:
        return normalized in output and result.returncode == 0, output, result.returncode
    if result.returncode == 0:
        return True, output, 0
    if result.returncode == 1:
        return False, "assertion failed", 1
    return False, "collection/import error", result.returncode


def audit(root: Path, registry_path: Path | None = None, changelog_path: Path | None = None) -> list[str]:
    """Return all rule-source findings; an empty list means the audit passed."""
    root = root.resolve()
    registry = registry_path or root / "rules" / "registry.json"
    changelog = changelog_path or root / "RULES-CHANGELOG.md"
    source = root / "src"
    issues: list[str] = []
    code_rules, scan_errors = _module_rule_ids(source)
    issues.extend(scan_errors)
    rules, registry_errors = _load_registry(registry)
    issues.extend(registry_errors)
    rows, changelog_errors = _load_changelog(changelog)
    issues.extend(changelog_errors)

    for rule_id in sorted(set(code_rules) - {rule["id"] for rule in rules if isinstance(rule.get("id"), str)}):
        issues.append(f"Unregistered rule: {rule_id}")
    registry_ids = {rule["id"] for rule in rules if isinstance(rule.get("id"), str)}
    for rule_id in sorted(registry_ids - set(code_rules)):
        issues.append(f"Orphaned registry entry: {rule_id}")
    for rule_id in sorted(set(rows) - registry_ids):
        issues.append(f"Ghost changelog entry: {rule_id}")

    with tempfile.TemporaryDirectory(prefix="cbp-rule-audit-") as basetemp:
        for rule in rules:
            rule_id = rule.get("id")
            if not isinstance(rule_id, str):
                continue
            if rule_id not in rows:
                issues.append(f"Rule {rule_id}: missing changelog entry")
            for label, key in (("negative", "negative_test"), ("positive", "positive_test")):
                node = rule.get(key)
                if not isinstance(node, str):
                    continue
                collected, detail, _code = _run_node(root, node, collect=True, basetemp=basetemp)
                if not collected:
                    issues.append(f"Rule {rule_id}: {label} test not collected")
                    continue
                passed, reason, _code = _run_node(root, node, collect=False, basetemp=basetemp)
                if not passed:
                    issues.append(f"Rule {rule_id}: {label} test {reason}")
    return issues


def main(argv: list[str] | None = None) -> int:
    """Run the rule-source audit and print one finding per line."""
    parser = argparse.ArgumentParser(prog="audit-rule-sources")
    parser.add_argument("--root", default=".")
    parser.add_argument("--registry", default="")
    parser.add_argument("--changelog", default="")
    args = parser.parse_args(argv)
    root = Path(args.root)
    registry = Path(args.registry) if args.registry else None
    changelog = Path(args.changelog) if args.changelog else None
    issues = audit(root, registry, changelog)
    if issues:
        print("RULE_SOURCE_AUDIT_FAILED")
        for issue in issues:
            print(issue)
        return 1
    print("RULE_SOURCE_AUDIT_OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
