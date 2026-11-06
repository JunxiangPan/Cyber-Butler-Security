"""Smooth-upgrade gate: run user evidence and reject schema regressions."""
from __future__ import annotations

import json
import os
import re
import shlex
import subprocess
from pathlib import Path

from .config import GateConfig

RULE_ID = "CBP-UPG-001"
SHELL_META = re.compile(r"[&|;<>`$]|\r|\n")


def _run_script(cfg: GateConfig) -> str:
    script = getattr(cfg, "upgrade_script", "")
    if not script:
        return ""
    if os.environ.get("GITHUB_EVENT_NAME") in {"pull_request", "pull_request_target"}:
        return "upgrade script is not allowed on pull_request events"
    if SHELL_META.search(script):
        return "upgrade script contains forbidden shell metacharacters"
    try:
        arguments = shlex.split(script)
    except ValueError as exc:
        return f"upgrade script cannot be parsed safely: {exc}"
    if not arguments:
        return "upgrade script is empty after parsing"
    timeout = int(getattr(cfg, "upgrade_timeout_seconds", 120))
    try:
        result = subprocess.run(
            arguments,
            cwd=cfg.root,
            shell=False,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        return f"upgrade script failed: {exc}"
    if result.returncode != 0:
        detail = (result.stdout + "\n" + result.stderr).strip().splitlines()
        return "upgrade script failed (exit " + str(result.returncode) + "): " + (detail[-1] if detail else "no output")
    return ""


def _fixture_problem(cfg: GateConfig) -> str:
    for relative in getattr(cfg, "upgrade_fixtures", ()) or ():
        path = cfg.path(relative)
        if not path.is_file():
            return f"upgrade fixture missing: {relative}"
        try:
            from .config import load_config
            load_config(cfg.root, path)
        except (ValueError, OSError, json.JSONDecodeError) as exc:
            return f"upgrade fixture {relative} cannot be parsed: {exc}"
    return ""


def _schema_problem(cfg: GateConfig) -> str:
    old_path = getattr(cfg, "previous_schema", "")
    new_path = getattr(cfg, "current_schema", "")
    if not old_path or not new_path:
        return ""
    old_file, new_file = cfg.path(old_path), cfg.path(new_path)
    if not old_file.is_file() or not new_file.is_file():
        return "schema compatibility files are missing"
    try:
        old = json.loads(old_file.read_text(encoding="utf-8"))
        new = json.loads(new_file.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        return f"schema compatibility JSON is invalid: {exc}"
    old_props = set((old.get("properties") or {}).keys())
    new_props = set((new.get("properties") or {}).keys())
    removed = sorted(old_props - new_props)
    old_required = set(old.get("required") or [])
    new_required = set(new.get("required") or [])
    newly_required = sorted(new_required - old_required)
    problems = []
    if removed:
        problems.append("removed schema properties: " + ", ".join(removed))
    if newly_required:
        problems.append("newly required schema properties: " + ", ".join(newly_required))
    if problems:
        if getattr(cfg, "allow_breaking_changes", False):
            return ""
        return "schema compatibility failed: " + "; ".join(problems)
    return ""


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Run optional upgrade evidence and reject unapproved schema breaks."""
    script_problem = _run_script(cfg)
    if script_problem:
        return False, script_problem
    fixture_problem = _fixture_problem(cfg)
    if fixture_problem:
        return False, fixture_problem
    schema_problem = _schema_problem(cfg)
    if schema_problem:
        return False, schema_problem
    checks = []
    if getattr(cfg, "upgrade_script", ""):
        checks.append("script")
    if getattr(cfg, "upgrade_fixtures", ()):
        checks.append("fixtures")
    if getattr(cfg, "previous_schema", "") and getattr(cfg, "current_schema", ""):
        checks.append("schema")
    return True, "upgrade=" + (", ".join(checks) if checks else "no checks configured")
