from __future__ import annotations

import os
from pathlib import Path

import pytest

from win_path_guard import (
    TargetGuardError,
    TargetSnapshot,
    create_exclusive,
)


def test_snapshot_hashes_file_and_detects_handle_content_change(tmp_path: Path):
    target = tmp_path / "approved.txt"
    target.write_text("approved", encoding="utf-8")
    snapshot = TargetSnapshot.open(str(target), write=True)
    try:
        assert snapshot.sha256
        assert snapshot.identity[2] == len(b"approved")
        snapshot.rewrite(b"changed")
        with pytest.raises(TargetGuardError, match="TOCTOU"):
            snapshot.assert_unchanged()
    finally:
        snapshot.close()


def test_snapshot_rejects_dotdot_and_short_name(tmp_path: Path):
    with pytest.raises(TargetGuardError, match="traversal"):
        TargetSnapshot.open(str(tmp_path / ".." / "escape.txt"))
    with pytest.raises(TargetGuardError, match="short-name"):
        TargetSnapshot.open(str(tmp_path / "FILE~1.TXT"))


@pytest.mark.skipif(os.name == "nt", reason="symlink creation may require privileges")
def test_snapshot_rejects_symlink(tmp_path: Path):
    target = tmp_path / "real.txt"
    target.write_text("x", encoding="utf-8")
    link = tmp_path / "link.txt"
    link.symlink_to(target)
    with pytest.raises(TargetGuardError):
        TargetSnapshot.open(str(link))


def test_create_exclusive_never_overwrites(tmp_path: Path):
    target = tmp_path / "new.txt"
    create_exclusive(str(target), b"first")
    assert target.read_bytes() == b"first"
    with pytest.raises(FileExistsError):
        create_exclusive(str(target), b"second")
    assert target.read_bytes() == b"first"


def test_restricted_acl_uses_explicit_sids(monkeypatch, tmp_path):
    import os
    import subprocess

    if os.name != "nt":
        pytest.skip("Windows ACL only")
    calls = []

    class Result:
        returncode = 0
        stderr = ""

    monkeypatch.setattr(subprocess, "run", lambda *a, **k: calls.append((a, k)) or Result())
    from win_path_guard import apply_restricted_acl

    apply_restricted_acl(tmp_path / "x.txt")
    args = calls[0][0][0]
    assert "/inheritance:r" in args
    assert "*S-1-5-32-545:(RX)" in args
    assert "*S-1-5-32-545:(F)" not in args
