"""Custom rules are configuration-driven and warn by default."""
from __future__ import annotations

from pathlib import Path

from cbp import custom_rules
from cbp.config import GateConfig


def _cfg(tmp_path: Path, mode: str = "warn") -> GateConfig:
    (tmp_path / "src").mkdir()
    (tmp_path / "src" / "app.py").write_text("print('debug')\n", encoding="utf-8")
    return GateConfig(
        root=tmp_path,
        custom_rules=(
            {
                "name": "no_print_statements",
                "pattern": "print\(",
                "files": ["src/**/*.py"],
                "message": "Do not use print() in production.",
                "mode": mode,
            },
        ),
    )


def test_custom_rule_default_warn(tmp_path: Path) -> None:
    passed, detail = custom_rules.run(_cfg(tmp_path))
    assert passed is True
    assert "custom=WARN" in detail
    assert "src/app.py:1" in detail


def test_custom_rule_enforce_fails(tmp_path: Path) -> None:
    passed, detail = custom_rules.run(_cfg(tmp_path, "enforce"))
    assert passed is False
    assert "custom=FAIL" in detail


def test_custom_rule_no_match_passes(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    (tmp_path / "src" / "app.py").write_text("print_was_removed = True\n", encoding="utf-8")
    passed, detail = custom_rules.run(cfg)
    assert passed is True
    assert "custom=1 rules" in detail


def test_invalid_regex_is_configuration_error(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    cfg.custom_rules[0]["pattern"] = "["  # type: ignore[index]
    passed, detail = custom_rules.run(cfg)
    assert passed is False
    assert "invalid regex" in detail
