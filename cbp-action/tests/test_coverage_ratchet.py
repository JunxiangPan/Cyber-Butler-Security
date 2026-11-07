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


def _cfg(tmp_path: Path, coverage: Path, groups):
    (tmp_path / "allow.json").write_text('{"files": {}}', encoding="utf-8")
    return GateConfig(root=tmp_path, coverage_json=coverage,
                      coverage_allowlist=tmp_path / "allow.json",
                      coverage_groups=tuple(groups))


def test_lcov_run_passes_group(tmp_path: Path) -> None:
    cov = tmp_path / "coverage.lcov"
    cov.write_text("TN:\nSF:src/a.py\nDA:1,1\nend_of_record\n", encoding="utf-8")
    cfg = _cfg(tmp_path, cov, [{"name": "core", "files": ["src/a.py"], "threshold": 50}])
    passed, detail = run(cfg)
    assert passed is True and "core=100.00%" in detail


def test_cobertura_run_passes_group(tmp_path: Path) -> None:
    cov = tmp_path / "coverage.xml"
    cov.write_text('<coverage><packages><package><classes><class filename="src/a.py">'
                   '<lines><line number="1" hits="1"/></lines></class></classes></package></packages></coverage>',
                   encoding="utf-8")
    cfg = _cfg(tmp_path, cov, [{"name": "core", "files": ["src/a.py"], "threshold": 50}])
    passed, detail = run(cfg)
    assert passed is True and "core=100.00%" in detail
