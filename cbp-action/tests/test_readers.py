"""Evidence readers resolve by suffix or name without importing external code."""
from __future__ import annotations

from pathlib import Path

from cbp import custom_rules, readers
from cbp.config import GateConfig


def _cfg(tmp_path: Path) -> GateConfig:
    (tmp_path / "web").mkdir()
    (tmp_path / "web" / "app.jsx").write_text(
        "const x = <div dangerouslySetInnerHTML={{__html: data}} />;\n", encoding="utf-8"
    )
    return GateConfig(
        root=tmp_path,
        evidence_readers={"javascript": {"suffixes": [".js", ".jsx"], "encoding": "utf-8"}},
        custom_rules=(
            {
                "name": "no-dangerous-html",
                "pattern": "dangerouslySetInnerHTML",
                "files": ["web/**/*.jsx"],
                "reader": "javascript",
                "message": "Do not inject raw HTML.",
                "mode": "warn",
            },
        ),
    )


def test_reader_resolution_by_suffix_and_name(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    path = tmp_path / "web" / "app.jsx"
    reader = readers.resolve(cfg, path)
    assert reader.name == "javascript"
    assert readers.resolve(cfg, path, "javascript").encoding == "utf-8"


def test_cross_language_rule_matches(tmp_path: Path) -> None:
    passed, detail = custom_rules.run(_cfg(tmp_path))
    assert passed is True
    assert "web/app.jsx" in detail


def test_unknown_reader_fails(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    cfg.custom_rules[0]["reader"] = "missing"  # type: ignore[index]
    passed, detail = custom_rules.run(cfg)
    assert passed is False
    assert "reader not configured" in detail


def test_reader_size_limit(tmp_path: Path) -> None:
    cfg = _cfg(tmp_path)
    cfg.evidence_readers["javascript"]["max_bytes"] = 1
    passed, detail = custom_rules.run(cfg)
    assert passed is True
    assert "reader limit" in detail
