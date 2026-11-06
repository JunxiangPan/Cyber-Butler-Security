"""Exercise custom rule configuration and matching branches."""
from __future__ import annotations

from pathlib import Path

from cbp import custom_rules
from cbp.config import GateConfig


def _cfg(tmp_path: Path, rules: list[dict]) -> GateConfig:
    (tmp_path / "src").mkdir(exist_ok=True)
    (tmp_path / "src" / "app.py").write_text("x = 1\n", encoding="utf-8")
    return GateConfig(root=tmp_path, custom_rules=tuple(rules))


def test_no_rules_passes(tmp_path: Path) -> None:
    passed, detail = custom_rules.run(_cfg(tmp_path, []))
    assert passed is True
    assert detail == "custom=0 rules"


def test_literal_matching_and_exclude(tmp_path: Path) -> None:
    rule = {
        "name": "literal",
        "pattern": "x = 1",
        "match": "literal",
        "files": ["src/**/*.py"],
        "exclude": ["src/skip.py"],
        "message": "literal hit",
    }
    passed, detail = custom_rules.run(_cfg(tmp_path, [rule]))
    assert passed is True
    assert "custom=WARN" in detail


def test_invalid_mode_fails(tmp_path: Path) -> None:
    rule = {"name": "bad", "pattern": "x", "files": ["src/**/*.py"], "message": "m", "mode": "block"}
    passed, detail = custom_rules.run(_cfg(tmp_path, [rule]))
    assert passed is False
    assert "invalid mode" in detail


def test_invalid_severity_fails(tmp_path: Path) -> None:
    rule = {"name": "bad", "pattern": "x", "files": ["src/**/*.py"], "message": "m", "severity": "critical"}
    passed, detail = custom_rules.run(_cfg(tmp_path, [rule]))
    assert passed is False
    assert "invalid severity" in detail


def test_bad_rule_shape_fails(tmp_path: Path) -> None:
    passed, detail = custom_rules.run(_cfg(tmp_path, [{"name": "bad"}]))
    assert passed is False
    assert "needs name" in detail


def test_rule_without_files_and_invalid_match(tmp_path: Path) -> None:
    passed, detail = custom_rules.run(_cfg(tmp_path, [{"name": "bad", "pattern": "x", "files": [], "message": "m"}]))
    assert passed is False and "files array" in detail
    passed, detail = custom_rules.run(_cfg(tmp_path, [{"name": "bad", "pattern": "x", "files": ["src/**/*.py"], "message": "m", "match": "glob"}]))
    assert passed is False and "match mode" in detail


def test_rule_respects_max_matches(tmp_path: Path) -> None:
    rule = {"name": "limit", "pattern": "x", "files": ["src/**/*.py"], "message": "hit", "max_matches": 1}
    passed, detail = custom_rules.run(_cfg(tmp_path, [rule]))
    assert passed is True and detail.count("hit") == 1
