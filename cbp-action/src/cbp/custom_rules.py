"""Config-driven regex/literal custom rules."""
from __future__ import annotations

import re
from pathlib import Path

from .config import GateConfig
from . import artifact_integrity, readers, powershell_syntax, regex_guard

RULE_ID = "CBP-CST-001"
MAX_PATTERN_CHARS = 4096
MAX_INPUT_BYTES = 2_000_000
SKIP_PARTS = {".git", ".venv", "venv", "__pycache__", "node_modules", "wheelhouse"}


def _rule_id(rule: dict, index: int) -> str:
    raw = str(rule.get("id") or rule.get("name") or f"rule-{index}").upper()
    safe = re.sub(r"[^A-Z0-9_-]+", "-", raw).strip("-")
    return raw if raw.startswith("CBP-CUSTOM-") else f"CBP-CUSTOM-{safe}"


def _files(cfg: GateConfig, patterns: list[str], excludes: list[str]) -> list[Path]:
    result: list[Path] = []
    for pattern in patterns:
        for path in cfg.root.glob(pattern):
            if not path.is_file() or any(part in SKIP_PARTS for part in path.parts):
                continue
            relative = path.relative_to(cfg.root).as_posix()
            if any(Path(relative).match(ex) for ex in excludes):
                continue
            if path not in result:
                result.append(path)
    return result


def run(cfg: GateConfig) -> tuple[bool, str]:
    """Evaluate configured rules; warn by default, enforce on demand."""
    rules = getattr(cfg, "custom_rules", ()) or ()
    findings: list[str] = []
    enforced = False
    integrity = artifact_integrity.check(cfg)
    if integrity:
        findings.extend(integrity)
        enforced = True
    ps_ok, ps_detail = powershell_syntax.check(cfg.root)
    if not ps_ok:
        findings.append(ps_detail)
        enforced = True
    for index, rule in enumerate(rules):
        if not isinstance(rule, dict):
            return False, f"custom rule {index} must be an object"
        name = rule.get("name")
        pattern = rule.get("pattern")
        files = rule.get("files")
        message = rule.get("message")
        if not all(isinstance(value, str) and value for value in (name, pattern, message)):
            return False, f"custom rule {index} needs name, pattern, and message"
        if not isinstance(files, list) or not files or not all(isinstance(item, str) and item for item in files):
            return False, f"custom rule {name} needs a non-empty files array"
        mode = rule.get("mode", "warn")
        if mode not in {"warn", "enforce"}:
            return False, f"custom rule {name} has invalid mode {mode!r}"
        severity = rule.get("severity", "warning")
        if severity not in {"error", "warning", "note"}:
            return False, f"custom rule {name} has invalid severity {severity!r}"
        rule_id = _rule_id(rule, index)
        match_kind = rule.get("match", "regex")
        if match_kind not in {"regex", "literal"}:
            return False, f"custom rule {name} has invalid match mode"
        flags = 0
        raw_flags = rule.get("flags", [])
        if isinstance(raw_flags, str):
            raw_flags = [raw_flags]
        if not isinstance(raw_flags, list):
            return False, f"custom rule {name} has invalid flags"
        for flag_name in raw_flags:
            if flag_name == "ignore_case":
                flags |= re.IGNORECASE
            elif flag_name == "multiline":
                flags |= re.MULTILINE
            elif flag_name == "dotall":
                flags |= re.DOTALL
            else:
                return False, f"custom rule {name} has unknown flag {flag_name!r}"
        try:
            expression = re.escape(pattern) if match_kind == "literal" else pattern
            matcher = re.compile(expression, flags)
        except re.error as exc:
            return False, f"custom rule {name} has invalid regex: {exc}"
        required = rule.get("required_pattern", "")
        required_matcher = None
        if len(pattern) > MAX_PATTERN_CHARS:
            return False, f"custom rule {name} pattern exceeds {MAX_PATTERN_CHARS} characters"
        if re.search(r"\([^)]*[+*][^)]*\)[+*{]", pattern):
            return False, f"custom rule {name} contains a nested quantifier that can cause ReDoS"
        if required:
            if len(required) > MAX_PATTERN_CHARS:
                return False, f"custom rule {name} required_pattern is too long"
            try:
                required_matcher = re.compile(required, flags)
            except re.error as exc:
                return False, f"custom rule {name} has invalid required_pattern: {exc}"
        limit = int(rule.get("max_matches", 100))
        count = 0
        for path in _files(cfg, files, rule.get("exclude", [])):
            try:
                reader = readers.resolve(cfg, path, str(rule.get("reader", "")))
            except ValueError as exc:
                return False, f"custom rule {name}: {exc}"
            text, error = readers.read(path, reader)
            if error:
                findings.append(f"{path.relative_to(cfg.root).as_posix()}:1: [{rule_id}] unreadable: {error}")
                count += 1
                continue
            if len(text.encode("utf-8", errors="replace")) > MAX_INPUT_BYTES:
                findings.append(f"{path.relative_to(cfg.root).as_posix()}:1: [{rule_id}] input exceeds ReDoS budget")
                count += 1
                continue
            try:
                if required_matcher is not None:
                    if not regex_guard.exists(required, flags, text):
                        findings.append(f"{path.relative_to(cfg.root).as_posix()}:1: [{rule_id}] {message} (required pattern missing)")
                        count += 1
                    continue
                for line in regex_guard.find_lines(expression, flags, text):
                    findings.append(f"{path.relative_to(cfg.root).as_posix()}:{line}: [{rule_id}] {message}")
                    count += 1
                    if count >= limit:
                        break
            except regex_guard.RegexTimeout as exc:
                findings.append(f"{path.relative_to(cfg.root).as_posix()}:1: [{rule_id}] {exc}")
                count += 1
                if count >= limit:
                    break
            if count >= limit:
                break
        if count and mode == "enforce":
            enforced = True
    if not rules and not findings:
        return True, "custom=0 rules; " + ps_detail
    if findings:
        prefix = "custom=FAIL" if enforced else "custom=WARN"
        return (not enforced), prefix + " " + "\n".join(findings)
    return True, f"custom={len(rules)} rules"

