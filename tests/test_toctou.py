from __future__ import annotations

from pathlib import Path

import pytest

from quarantine import quarantine_file, restore_quarantine
from win_path_guard import TargetGuardError, TargetSnapshot


def test_toctou_changed_target_is_rejected(tmp_path: Path):
    target = tmp_path / "draft.txt"
    target.write_text("before", encoding="utf-8")
    snapshot = TargetSnapshot.open(str(target), write=True)
    try:
        snapshot.rewrite(b"after")
        with pytest.raises(TargetGuardError, match="TOCTOU"):
            snapshot.assert_unchanged()
    finally:
        snapshot.close()


def test_quarantine_moves_file_and_writes_manifest(tmp_path: Path, monkeypatch):
    import quarantine

    monkeypatch.setattr(quarantine, "TRASH_STAGING", tmp_path / "trash_staging")
    target = tmp_path / "delete-me.txt"
    target.write_text("payload", encoding="utf-8")
    snapshot = TargetSnapshot.open(str(target), delete=True)
    entry = quarantine_file(
        snapshot,
        "req123",
        original_path=str(target),
        action="delete",
        reason="test",
    )
    assert not target.exists()
    assert (entry / "delete-me.txt").read_text(encoding="utf-8") == "payload"
    assert (entry / "manifest.json").is_file()
    restored = restore_quarantine(entry, tmp_path / "restored.txt")
    assert restored.read_text(encoding="utf-8") == "payload"
