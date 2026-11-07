"""Generic inline suppression applies to any file/line finding."""
from pathlib import Path
from cbp.suppression import filter_text


def test_generic_suppression_removes_marked_line(tmp_path: Path) -> None:
    source = tmp_path / "a.py"
    source.write_text("# cbp: ignore\nprint('x')\n", encoding="utf-8")
    assert filter_text(tmp_path, "a.py:1: finding") == ""
    assert filter_text(tmp_path, "a.py:2: finding") == "a.py:2: finding"


def test_suppression_does_not_remove_other_lines(tmp_path: Path) -> None:
    (tmp_path / "a.py").write_text("# ordinary\nprint('x')\n", encoding="utf-8")
    assert filter_text(tmp_path, "a.py:1: finding") == "a.py:1: finding"
