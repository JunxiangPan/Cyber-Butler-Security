"""Tests for local-overlay rendering and production merge safety."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import pytest

import update_core
import update_merge_core


def _manifest(entries: list[tuple[str, bytes]]) -> dict:
    return update_core.validate_manifest(
        {
            "schema": 1,
            "version": "1.0.7",
            "files": [
                {
                    "path": name,
                    "size": len(data),
                    "sha256": hashlib.sha256(data).hexdigest(),
                }
                for name, data in entries
            ],
        }
    )


def test_protected_data_and_tokens_are_rejected() -> None:
    assert update_merge_core.is_protected("AstrBot/data/chat.db")
    assert update_merge_core.is_protected("tools/broker_token.txt")
    assert update_merge_core.is_protected("local-overlay.json")
    assert not update_merge_core.is_protected("tools/broker.py")
    with pytest.raises(update_merge_core.MergeError):
        update_merge_core.validate_manifest_protected(
            {"files": [{"path": "AstrBot/data/chat.db"}]}
        )


def test_render_runtime_but_not_docs(tmp_path: Path) -> None:
    staging = tmp_path / "staging"
    (staging / "tools").mkdir(parents=True)
    (staging / "docs").mkdir()
    runtime = b"ROOT = r'YOUR_PROJECT_PATH'\n"
    doc = b"# YOUR_PROJECT_PATH\n"
    (staging / "tools" / "broker.py").write_bytes(runtime)
    (staging / "docs" / "guide.md").write_bytes(doc)
    manifest = _manifest(
        [
            ("tools/broker.py", runtime),
            ("docs/guide.md", doc),
        ]
    )
    rendered = update_merge_core.render_staging(
        staging,
        manifest,
        {"values": {"YOUR_PROJECT_PATH": r"D:\deployment"}},
    )
    assert (staging / "tools" / "broker.py").read_bytes() == b"ROOT = r'D:\\deployment'\n"
    assert (staging / "docs" / "guide.md").read_bytes() == doc
    assert any(item["path"] == "tools/broker.py" for item in rendered["files"])


def test_unresolved_placeholder_is_rejected(tmp_path: Path) -> None:
    staging = tmp_path / "staging"
    (staging / "tools").mkdir(parents=True)
    data = b"ROOT = 'YOUR_PROJECT_PATH'\nQQ = 'YOUR_QQ_ID'\n"
    (staging / "tools" / "broker.py").write_bytes(data)
    manifest = _manifest([("tools/broker.py", data)])
    with pytest.raises(update_merge_core.MergeError):
        update_merge_core.render_staging(
            staging,
            manifest,
            {"values": {"YOUR_PROJECT_PATH": r"D:\deployment"}},
        )


def test_baseline_detects_local_change(tmp_path: Path) -> None:
    target = tmp_path / "target"
    (target / "tools").mkdir(parents=True)
    path = target / "tools" / "broker.py"
    path.write_bytes(b"old")
    digest = hashlib.sha256(b"old").hexdigest()
    overlay = {"values": {"YOUR_QQ_ID": "1"}, "baseline": {"tools/broker.py": digest}}
    assert update_merge_core.baseline_changes(target, overlay) == []
    path.write_bytes(b"local change")
    assert update_merge_core.baseline_changes(target, overlay) == ["tools/broker.py"]
