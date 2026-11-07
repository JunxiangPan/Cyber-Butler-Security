"""Wheel normalization removes build-container timestamp differences."""
from pathlib import Path
from tools.normalize_wheel import normalize


def test_identical_wheels_after_normalize(tmp_path: Path) -> None:
    import zipfile

    first = tmp_path / "a.whl"
    second = tmp_path / "b.whl"
    for path in (first, second):
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("x.txt", "hello")
    normalize(first)
    normalize(second)
    assert first.read_bytes() == second.read_bytes()
