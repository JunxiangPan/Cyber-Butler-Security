"""Diff Boundary: positive and negative pre-write semantics."""
from __future__ import annotations

from pathlib import Path

from tools.diff_boundary import DiffBoundary, check_diff


def test_modify_inside_boundary() -> None:
    boundary = DiffBoundary(root="C:/workspace")
    assert check_diff(boundary, [{"kind": "modify", "path": "C:/workspace/a.txt", "size": 3}])[0] is True


def test_path_escape_and_counts_rejected(tmp_path: Path) -> None:
    root = tmp_path / "root"
    root.mkdir()
    boundary = DiffBoundary(root=str(root), max_files=1, max_bytes=4)
    assert check_diff(boundary, [{"kind": "modify", "path": str(root / ".." / "outside.txt")}])[0] is False
    assert check_diff(boundary, [{"kind": "modify", "path": str(root / "a"), "size": 1}, {"kind": "modify", "path": str(root / "b"), "size": 1}])[0] is False
    assert check_diff(boundary, [{"kind": "modify", "path": str(root / "a"), "size": 5}])[0] is False


def test_create_delete_and_bad_kind_rejected() -> None:
    boundary = DiffBoundary(root="C:/workspace")
    assert check_diff(boundary, [{"kind": "create", "path": "C:/workspace/new.txt"}])[0] is False
    assert check_diff(boundary, [{"kind": "delete", "path": "C:/workspace/old.txt"}])[0] is False
    assert check_diff(boundary, [{"kind": "rename", "path": "C:/workspace/x"}])[0] is False
    assert check_diff(boundary, [{"kind": "modify", "path": "C:/workspace/x", "size": -1}])[0] is False
