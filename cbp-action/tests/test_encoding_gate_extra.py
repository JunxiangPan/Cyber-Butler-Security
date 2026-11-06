"""Additional encoding gate branches."""
from __future__ import annotations

import codecs
import shutil
import subprocess
from pathlib import Path
from unittest import mock

import pytest

from cbp.config import GateConfig
from cbp.encoding_gate import run


def test_utf16_bom_is_rejected(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_bytes(codecs.BOM_UTF16_LE + "hello".encode("utf-16-le"))
    passed, detail = run(GateConfig(root=tmp_path))
    assert passed is False
    assert "UTF-16 BOM" in detail


def test_read_error_is_reported(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_text("# ok\n", encoding="utf-8")
    with mock.patch.object(Path, "read_bytes", side_effect=OSError("denied")):
        passed, detail = run(GateConfig(root=tmp_path))
    assert passed is False
    assert "read error" in detail


def test_git_tracked_only_is_scanned(tmp_path: Path) -> None:
    if shutil.which("git") is None:
        pytest.skip("git is not available")
    (tmp_path / "README.md").write_text("# tracked\n", encoding="utf-8")
    (tmp_path / "untracked.md").write_bytes(codecs.BOM_UTF8 + b"# ignored\n")
    subprocess.run(["git", "init", "-q"], cwd=tmp_path, check=True)
    subprocess.run(["git", "add", "README.md"], cwd=tmp_path, check=True)
    passed, detail = run(GateConfig(root=tmp_path))
    assert passed is True
    assert "encoding=1" in detail
