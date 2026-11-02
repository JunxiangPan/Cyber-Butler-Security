from __future__ import annotations

from pathlib import Path

import approval_preview


def test_write_preview_contains_real_diff_and_redacts_secret(tmp_path: Path):
    target = tmp_path / "worker.py"
    target.write_text("token = 'old'\nprint('old')\n", encoding="utf-8")
    preview = approval_preview.build_preview(
        "write_file",
        str(target),
        content="token = 'new'\nprint('new')\n",
    )
    assert preview["script_warning"] is True
    assert preview["diff"]
    assert "worker.py" in approval_preview.format_preview(preview)
    assert "AI" not in approval_preview.format_preview(preview)


def test_preview_is_truncated_and_binary_is_not_dumped(tmp_path: Path):
    target = tmp_path / "big.txt"
    target.write_text("a\n" * 500, encoding="utf-8")
    preview = approval_preview.build_preview(
        "write_file",
        str(target),
        content="b\n" * 500,
    )
    assert preview["diff_truncated"] is True
    assert len(preview["diff"]) <= approval_preview.MAX_DIFF_CHARS

    binary = tmp_path / "blob.bin"
    binary.write_bytes(b"\x00\x01\x02")
    preview = approval_preview.build_preview("delete", str(binary))
    assert preview["before"]["size"] == 3
    assert "diff" not in preview


def test_delete_preview_never_reads_file_content(tmp_path: Path):
    target = tmp_path / "secret.txt"
    target.write_text("do-not-print-this", encoding="utf-8")
    preview = approval_preview.build_preview("delete", str(target))
    text = approval_preview.format_preview(preview)
    assert "do-not-print-this" not in text
    assert str(target) in text
