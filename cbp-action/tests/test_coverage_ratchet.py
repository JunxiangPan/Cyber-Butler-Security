"""Coverage ratchet must fail when a group drops below its recorded floor."""
from pathlib import Path
import json
from cbp.coverage_gate import run
from cbp.config import GateConfig


def test_ratchet_fails_below_floor(tmp_path: Path) -> None:
    (tmp_path / "coverage.json").write_text(json.dumps({
        "files": {"src/a.py": {"summary": {"num_statements": 10}, "missing_lines": [1, 2, 3, 4]}}
    }), encoding="utf-8")
    (tmp_path / "allow.json").write_text('{"files": {}}', encoding="utf-8")
    (tmp_path / "ratchet.json").write_text('{"core": 70.0}', encoding="utf-8")
    cfg = GateConfig(root=tmp_path, coverage_json=tmp_path / "coverage.json",
                     coverage_allowlist=tmp_path / "allow.json", coverage_ratchet=tmp_path / "ratchet.json",
                     coverage_groups=({"name": "core", "files": ["src/a.py"], "threshold": 50},))
    passed, detail = run(cfg)
    assert passed is False and "below ratchet" in detail
