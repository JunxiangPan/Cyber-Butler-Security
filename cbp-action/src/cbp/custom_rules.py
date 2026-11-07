"""Config-driven regex/literal custom rules."""
from __future__ import annotations

import hashlib
import json
import re
from pathlib import Path

from .config import GateConfig
from . import artifact_integrity, cel_gates, cel_policy, packs as packs_module, readers, powershell_syntax, regex_guard

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


def rules_digest(rules, packs) -> str:
    """Return a stable digest over the effective custom policy."""
    payload = json.dumps({"rules": rules, "packs": packs}, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


def _cache_key(cfg: GateConfig, rules) -> str:
    digest = rules_digest(rules, getattr(cfg, "packs", ()) or ())
    files = sorted(
        (path.relative_to(cfg.root).as_posix(), hashlib.sha256(path.read_bytes()).hexdigest())
        for path in cfg.root.rglob("*")
        if path.is_file() and not (set(path.parts) & SKIP_PARTS)
        and path.name != ".cache.json"
    )
    return hashlib.sha256((digest + json.dumps(files)).encode("utf-8")).hexdigest()


def _detect(cfg: GateConfig) -> tuple[bool, str]:
    """Evaluate configured rules; warn by default, enforce on demand."""
    rules = list(getattr(cfg, "custom_rules", ()) or ())
    for packed in getattr(cfg, "packs", ()) or ():
        try:
            pack = packs_module.load_pack(cfg.path(packed["path"]), str(packed.get("sha256", "")))
        except (KeyError, TypeError, packs_module.PackError) as exc:
            return False, f"custom pack failed: {exc}"
        rules.extend(pack["rules"])
    digest = rules_digest(rules, getattr(cfg, "packs", ()) or ())
    manifest = cfg.path(getattr(cfg, "rules_manifest", "") or "") if getattr(cfg, "rules_manifest", "") else None
    if manifest is not None and manifest.is_file():
        expected = manifest.read_text(encoding="utf-8").strip().split()[0] if manifest.read_text(encoding="utf-8").strip() else ""
        if expected != digest:
            return False, f"custom=FAIL rules hash changed ({digest[:12]}); update RULES-CHANGELOG and rules/rules.sha256"
    changelog_manifest = cfg.path(getattr(cfg, "rules_changelog_manifest", "") or "") if getattr(cfg, "rules_changelog_manifest", "") else None
    if changelog_manifest is not None and changelog_manifest.is_file():
        expected = changelog_manifest.read_text(encoding="utf-8").strip().split()[0] if changelog_manifest.read_text(encoding="utf-8").strip() else ""
        changelog = cfg.path("docs/RULES-CHANGELOG.md")
        if changelog.is_file():
            actual = hashlib.sha256(changelog.read_bytes()).hexdigest()
            if expected != actual:
                return False, "custom=FAIL rules changelog changed; update rules/changelog.sha256"
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
        if not all(isinstance(value, str) and value for value in (name, message)):
            return False, f"custom rule {index} needs name and message"
        if "cel" not in rule and not (isinstance(pattern, str) and pattern):
            return False, f"custom rule {index} needs pattern or cel"
        if not isinstance(files, list) or not files or not all(isinstance(item, str) and item for item in files):
            return False, f"custom rule {name} needs a non-empty files array"
        mode = rule.get("mode", "warn")
        if mode not in {"warn", "enforce"}:
            return False, f"custom rule {name} has invalid mode {mode!r}"
        severity = rule.get("severity", "warning")
        if severity not in {"error", "warning", "note"}:
            return False, f"custom rule {name} has invalid severity {severity!r}"
        rule_id = _rule_id(rule, index)
        if "cel" in rule:
            texts = {}
            for path in _files(cfg, files, rule.get("exclude", [])):
                reader = readers.resolve(cfg, path, str(rule.get("reader", "")))
                text, error = readers.read(path, reader)
                if not error:
                    texts[path.relative_to(cfg.root).as_posix()] = text
            try:
                hit = cel_policy.evaluate(str(rule["cel"]), texts)
            except cel_policy.CelPolicyError as exc:
                return False, f"custom rule {name}: {exc}"
            if hit:
                findings.append(f"{next(iter(texts), '<none>')}:1: [{rule_id}] {message}")
                if mode == "enforce":
                    enforced = True
            continue
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



def run(cfg: GateConfig) -> tuple[bool, str]:
    """Run custom detection with optional content-addressed cache."""
    cache_path = cfg.path(getattr(cfg, "cache_file", "") or "") if getattr(cfg, "cache_file", "") else None
    rules = list(getattr(cfg, "custom_rules", ()) or ())
    key = _cache_key(cfg, rules) if cache_path is not None else ""
    if cache_path is not None and cache_path.is_file():
        try:
            cached = json.loads(cache_path.read_text(encoding="utf-8"))
            if cached.get("key") == key:
                return bool(cached["passed"]), str(cached["detail"])
        except (OSError, ValueError, KeyError):
            pass
    passed, detail = _detect(cfg)
    passed, detail = cel_gates.apply("custom", passed, detail, cfg)
    if cache_path is not None:
        cache_path.parent.mkdir(parents=True, exist_ok=True)
        cache_path.write_text(json.dumps({"key": key, "passed": passed, "detail": detail}), encoding="utf-8")
    return passed, detail
