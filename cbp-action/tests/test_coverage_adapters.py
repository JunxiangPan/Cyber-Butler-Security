"""Coverage adapter tests for LCOV and Cobertura inputs."""
from pathlib import Path

from cbp.coverage_gate import _load_coverage


def test_lcov_adapter_reads_statements_and_missing_lines(tmp_path: Path) -> None:
    path = tmp_path / "coverage.lcov"
    path.write_text("TN:\nSF:src/a.py\nDA:1,1\nDA:2,0\nend_of_record\n", encoding="utf-8")
    data = _load_coverage(path)
    assert data["format"] == "lcov"
    assert data["files"]["src/a.py"]["summary"]["num_statements"] == 2
    assert data["files"]["src/a.py"]["missing_lines"] == [2]


def test_cobertura_adapter_reads_classes(tmp_path: Path) -> None:
    path = tmp_path / "coverage.xml"
    path.write_text(
        '<coverage><packages><package><classes><class filename="src/a.py">'
        '<lines><line number="1" hits="1"/><line number="2" hits="0"/></lines>'
        '</class></classes></package></packages></coverage>',
        encoding="utf-8",
    )
    data = _load_coverage(path)
    assert data["format"] == "cobertura"
    assert data["files"]["src/a.py"]["summary"]["num_statements"] == 2
    assert data["files"]["src/a.py"]["missing_lines"] == [2]


def test_unknown_coverage_format_is_rejected(tmp_path: Path) -> None:
    path = tmp_path / "coverage.txt"
    path.write_text("not coverage", encoding="utf-8")
    try:
        _load_coverage(path)
    except ValueError as exc:
        assert "unsupported coverage format" in str(exc)
    else:
        raise AssertionError("unknown format was accepted")
