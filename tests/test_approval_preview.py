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


def test_txt_with_shebang_is_flagged(tmp_path: Path):
    target = tmp_path / "innocent.txt"
    preview = approval_preview.build_preview(
        "write_file",
        str(target),
        content="#!/bin/bash\necho pwned\n",
    )
    assert preview["magic_warning"] is True
    assert "Shebang" in preview["magic_types"]
    text = approval_preview.format_preview(preview)
    assert "可执行代码特征（Shebang）" in text
    assert "恶意" not in text
    assert "安全" not in text


def test_pe_with_txt_extension_is_flagged(tmp_path: Path):
    target = tmp_path / "not-really.txt"
    target.write_bytes(b"MZ" + b"\x00" * 20)
    preview = approval_preview.build_preview("overwrite", str(target), source=str(target))
    assert preview["magic_warning"] is True
    assert "PE" in preview["magic_types"]


def test_external_read_warning_is_objective_not_a_verdict(tmp_path: Path):
    target = tmp_path / "draft.txt"
    preview = approval_preview.build_preview("write_file", str(target), content="hello")
    preview["external_read_warning"] = "提示：Agent 最近读取了外部网页/文件，请仔细核对本次操作的合理性。"
    text = approval_preview.format_preview(preview)
    assert "最近读取了外部网页/文件" in text
    assert "恶意" not in text
    assert "安全" not in text


def test_intent_mismatch_flags_read_reason_on_env(tmp_path: Path):
    target = tmp_path / ".env"
    preview = approval_preview.build_preview("write_file", str(target), content="X=1", reason="查一下配置")
    assert preview["intent_mismatch"] is True
    text = approval_preview.format_preview(preview)
    assert "INTENT MISMATCH" in text
    assert "恶意" not in text


def test_intent_mismatch_flags_conftest_and_ui_reason(tmp_path: Path):
    target = tmp_path / "tests" / "conftest.py"
    preview = approval_preview.build_preview("write_file", str(target), content="x=1", reason="改UI样式")
    assert preview["intent_mismatch"] is True


def test_read_reason_on_plain_text_is_not_mismatch(tmp_path: Path):
    target = tmp_path / "notes.md"
    preview = approval_preview.build_preview("write_file", str(target), content="hello", reason="查一下资料")
    assert preview["intent_mismatch"] is False
