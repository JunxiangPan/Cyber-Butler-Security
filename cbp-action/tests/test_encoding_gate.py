"""Strict text-encoding gate tests."""
from __future__ import annotations

import codecs
from pathlib import Path

from cbp.config import GateConfig
from cbp.encoding_gate import run


def test_clean_utf8_passes(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_text("# ok\n", encoding="utf-8")
    passed, detail = run(GateConfig(root=tmp_path))
    assert passed is True
    assert "encoding=1" in detail


def test_bom_is_rejected(tmp_path: Path) -> None:
    (tmp_path / "README.md").write_bytes(codecs.BOM_UTF8 + b"# bom\n")
    passed, detail = run(GateConfig(root=tmp_path))
    assert passed is False
    assert "UTF-8 BOM" in detail


def test_gbk_is_rejected(tmp_path: Path) -> None:
    (tmp_path / "notes.md").write_bytes("中文".encode("gbk"))
    passed, detail = run(GateConfig(root=tmp_path))
    assert passed is False
    assert "invalid UTF-8" in detail


def test_non_text_suffix_is_ignored(tmp_path: Path) -> None:
    (tmp_path / "blob.bin").write_bytes(b"\xff\xfe\x00")
    passed, _detail = run(GateConfig(root=tmp_path))
    assert passed is True
